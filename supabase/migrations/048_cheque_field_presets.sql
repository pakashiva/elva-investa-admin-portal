-- Remember cheque number, bank name, and bank address independently
-- so each can be picked from a dropdown on the agreement approval dialog.
-- Additive only: new table + RPC updates. No data/table drops.

CREATE TABLE IF NOT EXISTS public.agreement_cheque_field_presets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  field_kind TEXT NOT NULL
    CHECK (field_kind IN ('cheque_no', 'bank_name', 'bank_address')),
  field_value TEXT NOT NULL,
  used_count INTEGER NOT NULL DEFAULT 1,
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS agreement_cheque_field_presets_unique
  ON public.agreement_cheque_field_presets (field_kind, lower(field_value));

ALTER TABLE public.agreement_cheque_field_presets ENABLE ROW LEVEL SECURITY;

-- Seed from previously saved bank pairs and any agreements already printed.
INSERT INTO public.agreement_cheque_field_presets (field_kind, field_value, used_count, last_used_at)
SELECT 'bank_name', bank_name, used_count, last_used_at
FROM public.agreement_cheque_presets
WHERE trim(bank_name) <> ''
ON CONFLICT (field_kind, lower(field_value)) DO NOTHING;

INSERT INTO public.agreement_cheque_field_presets (field_kind, field_value, used_count, last_used_at)
SELECT 'bank_address', bank_address, used_count, last_used_at
FROM public.agreement_cheque_presets
WHERE trim(bank_address) <> ''
ON CONFLICT (field_kind, lower(field_value)) DO NOTHING;

INSERT INTO public.agreement_cheque_field_presets (field_kind, field_value, last_used_at)
SELECT DISTINCT ON (lower(cheque_no))
  'cheque_no', cheque_no, updated_at
FROM public.investment_agreements
WHERE trim(cheque_no) <> ''
ORDER BY lower(cheque_no), updated_at DESC
ON CONFLICT (field_kind, lower(field_value)) DO NOTHING;

INSERT INTO public.agreement_cheque_field_presets (field_kind, field_value, last_used_at)
SELECT DISTINCT ON (lower(cheque_bank_name))
  'bank_name', cheque_bank_name, updated_at
FROM public.investment_agreements
WHERE trim(cheque_bank_name) <> ''
ORDER BY lower(cheque_bank_name), updated_at DESC
ON CONFLICT (field_kind, lower(field_value)) DO NOTHING;

INSERT INTO public.agreement_cheque_field_presets (field_kind, field_value, last_used_at)
SELECT DISTINCT ON (lower(cheque_bank_address))
  'bank_address', cheque_bank_address, updated_at
FROM public.investment_agreements
WHERE trim(cheque_bank_address) <> ''
ORDER BY lower(cheque_bank_address), updated_at DESC
ON CONFLICT (field_kind, lower(field_value)) DO NOTHING;

-- ---------------------------------------------------------------------------
-- List: three independent value lists for the approval dialog dropdowns
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_cheque_presets()
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'cheque_nos', COALESCE((
      SELECT json_agg(field_value ORDER BY last_used_at DESC)
      FROM (
        SELECT field_value, last_used_at
        FROM public.agreement_cheque_field_presets
        WHERE field_kind = 'cheque_no'
        ORDER BY last_used_at DESC
        LIMIT 100
      ) src
    ), '[]'::JSON),
    'bank_names', COALESCE((
      SELECT json_agg(field_value ORDER BY last_used_at DESC)
      FROM (
        SELECT field_value, last_used_at
        FROM public.agreement_cheque_field_presets
        WHERE field_kind = 'bank_name'
        ORDER BY last_used_at DESC
        LIMIT 100
      ) src
    ), '[]'::JSON),
    'bank_addresses', COALESCE((
      SELECT json_agg(field_value ORDER BY last_used_at DESC)
      FROM (
        SELECT field_value, last_used_at
        FROM public.agreement_cheque_field_presets
        WHERE field_kind = 'bank_address'
        ORDER BY last_used_at DESC
        LIMIT 100
      ) src
    ), '[]'::JSON)
  );
$$;

-- ---------------------------------------------------------------------------
-- Save: remember each of the three fields independently
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_save_investment_agreement(
  p_investment_id UUID,
  p_branch TEXT,
  p_cheque_no TEXT,
  p_cheque_bank_name TEXT,
  p_cheque_bank_address TEXT,
  p_renewal_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch TEXT := lower(trim(COALESCE(p_branch, '')));
  v_cheque_no TEXT := trim(COALESCE(p_cheque_no, ''));
  v_bank_name TEXT := trim(COALESCE(p_cheque_bank_name, ''));
  v_bank_address TEXT := trim(COALESCE(p_cheque_bank_address, ''));
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_amount NUMERIC(14, 2);
  v_agreement_id UUID;
  v_start DATE;
BEGIN
  IF v_branch NOT IN ('ballari', 'raichur') THEN
    RAISE EXCEPTION 'Select the branch for this agreement.';
  END IF;

  IF v_cheque_no = '' THEN
    RAISE EXCEPTION 'Cheque number is required.';
  END IF;

  IF v_bank_name = '' THEN
    RAISE EXCEPTION 'Cheque bank name is required.';
  END IF;

  IF v_bank_address = '' THEN
    RAISE EXCEPTION 'Cheque bank address is required.';
  END IF;

  SELECT i.fund_amount
  INTO v_amount
  FROM public.investments i
  WHERE i.id = p_investment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Investment not found.';
  END IF;

  IF p_renewal_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.agreement_renewal_requests
    WHERE id = p_renewal_id AND investment_id = p_investment_id
  ) THEN
    RAISE EXCEPTION 'Renewal request does not belong to this investment.';
  END IF;

  -- Keep legacy combined bank presets in sync (harmless if unused).
  INSERT INTO public.agreement_cheque_presets (bank_name, bank_address)
  VALUES (v_bank_name, v_bank_address)
  ON CONFLICT (lower(bank_name), lower(bank_address)) DO UPDATE
    SET used_count = agreement_cheque_presets.used_count + 1,
        last_used_at = NOW();

  INSERT INTO public.agreement_cheque_field_presets (field_kind, field_value)
  VALUES
    ('cheque_no', v_cheque_no),
    ('bank_name', v_bank_name),
    ('bank_address', v_bank_address)
  ON CONFLICT (field_kind, lower(field_value)) DO UPDATE
    SET used_count = agreement_cheque_field_presets.used_count + 1,
        last_used_at = NOW();

  -- The agreement is dated the day the admin approved it, so that date is
  -- captured once and a later re-print never moves it.
  IF p_renewal_id IS NULL THEN
    SELECT id, agreement_date INTO v_agreement_id, v_start
    FROM public.investment_agreements
    WHERE investment_id = p_investment_id AND renewal_id IS NULL;
  ELSE
    SELECT id, agreement_date INTO v_agreement_id, v_start
    FROM public.investment_agreements
    WHERE renewal_id = p_renewal_id;
  END IF;

  v_start := COALESCE(v_start, v_today);

  IF v_agreement_id IS NULL THEN
    INSERT INTO public.investment_agreements (
      investment_id,
      renewal_id,
      branch,
      agreement_date,
      period_from,
      period_to,
      fund_amount,
      cheque_no,
      cheque_bank_name,
      cheque_bank_address
    ) VALUES (
      p_investment_id,
      p_renewal_id,
      v_branch,
      v_start,
      v_start,
      (v_start + INTERVAL '1 year' - INTERVAL '1 day')::DATE,
      v_amount,
      v_cheque_no,
      v_bank_name,
      v_bank_address
    )
    RETURNING id INTO v_agreement_id;
  ELSE
    UPDATE public.investment_agreements
    SET
      branch = v_branch,
      agreement_date = v_start,
      period_from = v_start,
      period_to = (v_start + INTERVAL '1 year' - INTERVAL '1 day')::DATE,
      fund_amount = v_amount,
      cheque_no = v_cheque_no,
      cheque_bank_name = v_bank_name,
      cheque_bank_address = v_bank_address,
      updated_at = NOW()
    WHERE id = v_agreement_id;
  END IF;

  RETURN public.admin_agreement_payload(v_agreement_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_cheque_presets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_cheque_presets() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
