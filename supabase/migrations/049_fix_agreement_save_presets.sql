-- Harden cheque-field preset upserts used during agreement save.
-- The previous multi-row INSERT … ON CONFLICT (field_kind, lower(field_value))
-- can fail on some Postgres setups and abort the whole agreement save after
-- the investment was already approved.

CREATE OR REPLACE FUNCTION public.admin_remember_cheque_field(
  p_kind TEXT,
  p_value TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_kind TEXT := lower(trim(COALESCE(p_kind, '')));
  v_value TEXT := trim(COALESCE(p_value, ''));
BEGIN
  IF v_kind NOT IN ('cheque_no', 'bank_name', 'bank_address') OR v_value = '' THEN
    RETURN;
  END IF;

  UPDATE public.agreement_cheque_field_presets
  SET
    used_count = used_count + 1,
    last_used_at = NOW(),
    field_value = v_value
  WHERE field_kind = v_kind
    AND lower(field_value) = lower(v_value);

  IF FOUND THEN
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.agreement_cheque_field_presets (field_kind, field_value)
    VALUES (v_kind, v_value);
  EXCEPTION
    WHEN unique_violation THEN
      UPDATE public.agreement_cheque_field_presets
      SET
        used_count = used_count + 1,
        last_used_at = NOW(),
        field_value = v_value
      WHERE field_kind = v_kind
        AND lower(field_value) = lower(v_value);
  END;
END;
$$;

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

  -- Preset remembering must never block the agreement row itself.
  BEGIN
    INSERT INTO public.agreement_cheque_presets (bank_name, bank_address)
    VALUES (v_bank_name, v_bank_address)
    ON CONFLICT (lower(bank_name), lower(bank_address)) DO UPDATE
      SET used_count = agreement_cheque_presets.used_count + 1,
          last_used_at = NOW();
  EXCEPTION
    WHEN undefined_table THEN
      NULL;
    WHEN OTHERS THEN
      NULL;
  END;

  BEGIN
    PERFORM public.admin_remember_cheque_field('cheque_no', v_cheque_no);
    PERFORM public.admin_remember_cheque_field('bank_name', v_bank_name);
    PERFORM public.admin_remember_cheque_field('bank_address', v_bank_address);
  EXCEPTION
    WHEN undefined_table THEN
      NULL;
    WHEN undefined_function THEN
      NULL;
    WHEN OTHERS THEN
      NULL;
  END;

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

REVOKE ALL ON FUNCTION public.admin_remember_cheque_field(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_remember_cheque_field(TEXT, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
