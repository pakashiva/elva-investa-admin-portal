-- Loan agreement documents generated on investment / renewal approval.
-- Stores the admin-entered branch + cheque details per agreement so the same
-- Word file can be re-downloaded later, and remembers cheque bank presets.

-- ---------------------------------------------------------------------------
-- Remembered cheque banks (dropdown on the approval dialog)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.agreement_cheque_presets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bank_name TEXT NOT NULL,
  bank_address TEXT NOT NULL,
  used_count INTEGER NOT NULL DEFAULT 1,
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS agreement_cheque_presets_unique
  ON public.agreement_cheque_presets (lower(bank_name), lower(bank_address));

ALTER TABLE public.agreement_cheque_presets ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- One row per generated agreement (renewal_id NULL = original approval)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.investment_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  investment_id UUID NOT NULL REFERENCES public.investments (id) ON DELETE CASCADE,
  renewal_id UUID REFERENCES public.agreement_renewal_requests (id) ON DELETE CASCADE,
  branch TEXT NOT NULL CHECK (branch IN ('ballari', 'raichur')),
  agreement_date DATE NOT NULL,
  period_from DATE NOT NULL,
  period_to DATE NOT NULL,
  fund_amount NUMERIC(14, 2) NOT NULL,
  cheque_no TEXT NOT NULL,
  cheque_bank_name TEXT NOT NULL,
  cheque_bank_address TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS investment_agreements_investment_unique
  ON public.investment_agreements (investment_id)
  WHERE renewal_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS investment_agreements_renewal_unique
  ON public.investment_agreements (renewal_id)
  WHERE renewal_id IS NOT NULL;

ALTER TABLE public.investment_agreements ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Cheque bank presets
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_cheque_presets()
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(json_agg(row_json ORDER BY last_used_at DESC), '[]'::JSON)
  FROM (
    SELECT
      json_build_object(
        'id', p.id,
        'bank_name', p.bank_name,
        'bank_address', p.bank_address
      ) AS row_json,
      p.last_used_at
    FROM public.agreement_cheque_presets p
    ORDER BY p.last_used_at DESC
    LIMIT 100
  ) src;
$$;

-- ---------------------------------------------------------------------------
-- Merge payload for the Word template
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_agreement_payload(p_agreement_id UUID)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_build_object(
    'agreement', json_build_object(
      'id', a.id,
      'branch', a.branch,
      'agreement_date', a.agreement_date,
      'period_from', a.period_from,
      'period_to', a.period_to,
      'cheque_no', a.cheque_no,
      'cheque_bank_name', a.cheque_bank_name,
      'cheque_bank_address', a.cheque_bank_address,
      'renewal_id', a.renewal_id
    ),
    'investment', json_build_object(
      'id', i.id,
      'code', i.code,
      'plan_name', i.name,
      'fund_amount', a.fund_amount,
      'interest_rate', i.interest_rate,
      'tds_percent', i.tds_percent
    ),
    'customer', json_build_object(
      'user_id', p.user_id,
      'customer_id', c.customer_id,
      'full_name', p.full_name,
      'address', p.address,
      'email', p.email_address,
      'mobile', p.mobile_number,
      'pan', k.pan_number,
      'aadhaar', NULLIF(k.aadhaar_number, '000000000000')
    ),
    'bank', CASE
      WHEN ba.id IS NULL THEN NULL
      ELSE json_build_object(
        'holder', COALESCE(NULLIF(to_jsonb(ba)->>'account_holder_name', ''), p.full_name),
        'account_number', ba.account_number,
        'ifsc_code', ba.ifsc_code,
        'bank_name', ba.bank_name,
        'branch_name', COALESCE(to_jsonb(ba)->>'branch_name', '')
      )
    END,
    'nominee', CASE
      WHEN n.id IS NULL THEN NULL
      ELSE json_build_object(
        'name', n.nominee_name,
        'relation', n.relationship,
        'aadhaar', NULLIF(n.nominee_aadhaar, '000000000000'),
        'pan', n.nominee_pan,
        'mobile', n.nominee_mobile
      )
    END
  )
  INTO v_result
  FROM public.investment_agreements a
  INNER JOIN public.investments i ON i.id = a.investment_id
  INNER JOIN public.profiles p ON p.user_id = i.user_id
  LEFT JOIN public.customers c ON c.user_id = i.user_id
  LEFT JOIN public.kyc_documents k ON k.user_id = i.user_id
  LEFT JOIN public.bank_accounts ba ON ba.id = i.bank_account_id
  LEFT JOIN LATERAL (
    SELECT * FROM public.nominees nn
    WHERE nn.user_id = i.user_id
    ORDER BY nn.created_at ASC
    LIMIT 1
  ) n ON TRUE
  WHERE a.id = p_agreement_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Agreement not found.';
  END IF;

  RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- Save (or refresh) the agreement for an investment / renewal
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

  INSERT INTO public.agreement_cheque_presets (bank_name, bank_address)
  VALUES (v_bank_name, v_bank_address)
  ON CONFLICT (lower(bank_name), lower(bank_address)) DO UPDATE
    SET used_count = agreement_cheque_presets.used_count + 1,
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

-- ---------------------------------------------------------------------------
-- Fetch a stored agreement for re-download (NULL when never generated)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_investment_agreement(
  p_investment_id UUID,
  p_renewal_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_agreement_id UUID;
BEGIN
  IF p_renewal_id IS NULL THEN
    SELECT id INTO v_agreement_id
    FROM public.investment_agreements
    WHERE investment_id = p_investment_id AND renewal_id IS NULL;
  ELSE
    SELECT id INTO v_agreement_id
    FROM public.investment_agreements
    WHERE renewal_id = p_renewal_id;
  END IF;

  IF v_agreement_id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN public.admin_agreement_payload(v_agreement_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_cheque_presets() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_agreement_payload(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_save_investment_agreement(UUID, TEXT, TEXT, TEXT, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_get_investment_agreement(UUID, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_cheque_presets() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_save_investment_agreement(UUID, TEXT, TEXT, TEXT, TEXT, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_investment_agreement(UUID, UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
