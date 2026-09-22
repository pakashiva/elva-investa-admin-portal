-- Fix approved-investment edit: always update the investment's own customer
-- (profiles / KYC / nominee for that user_id). Skip email/mobile uniqueness
-- checks when the value is unchanged so existing duplicates cannot block edits.

CREATE OR REPLACE FUNCTION public.admin_update_approved_investment(
  p_id UUID,
  p_full_name TEXT,
  p_email TEXT,
  p_mobile TEXT,
  p_date_of_birth DATE,
  p_address TEXT,
  p_pan_number TEXT,
  p_aadhaar_number TEXT,
  p_nominee_name TEXT,
  p_nominee_relationship TEXT,
  p_nominee_aadhaar TEXT,
  p_nominee_pan TEXT,
  p_nominee_mobile TEXT,
  p_plan_name TEXT,
  p_fund_amount NUMERIC,
  p_interest_rate NUMERIC,
  p_tds_percent NUMERIC,
  p_payout_day INTEGER,
  p_bank_name TEXT,
  p_account_number TEXT,
  p_ifsc_code TEXT,
  p_account_type TEXT,
  p_account_holder_name TEXT,
  p_branch_name TEXT,
  p_agreement_branch TEXT DEFAULT NULL,
  p_cheque_no TEXT DEFAULT NULL,
  p_cheque_bank_name TEXT DEFAULT NULL,
  p_cheque_bank_address TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_customer_id TEXT;
  v_status TEXT;
  v_bank_id UUID;
  v_cur_account TEXT;
  v_cur_ifsc TEXT;
  v_cur_bank TEXT;
  v_cur_type TEXT;
  v_cur_holder TEXT;
  v_cur_branch TEXT;
  v_cur_email TEXT;
  v_cur_mobile TEXT;
  v_bank_name TEXT := trim(COALESCE(p_bank_name, ''));
  v_account TEXT := regexp_replace(COALESCE(p_account_number, ''), '\s', '', 'g');
  v_ifsc TEXT := upper(regexp_replace(COALESCE(p_ifsc_code, ''), '\s', '', 'g'));
  v_type TEXT := initcap(trim(COALESCE(p_account_type, 'Savings')));
  v_holder TEXT := trim(COALESCE(p_account_holder_name, ''));
  v_branch TEXT := trim(COALESCE(p_branch_name, ''));
  v_plan TEXT := trim(COALESCE(p_plan_name, ''));
  v_amount NUMERIC(15, 2) := round(COALESCE(p_fund_amount, 0), 2);
  v_rate NUMERIC(8, 6) := COALESCE(p_interest_rate, 0);
  v_tds NUMERIC(8, 6) := COALESCE(p_tds_percent, 0);
  v_payout INTEGER := COALESCE(p_payout_day, 10);
  v_agr_branch TEXT := lower(trim(COALESCE(p_agreement_branch, '')));
  v_cheque_no TEXT := trim(COALESCE(p_cheque_no, ''));
  v_cheque_bank TEXT := trim(COALESCE(p_cheque_bank_name, ''));
  v_cheque_addr TEXT := trim(COALESCE(p_cheque_bank_address, ''));
  v_full_name TEXT := trim(COALESCE(p_full_name, ''));
  v_email TEXT := lower(trim(COALESCE(p_email, '')));
  v_mobile_digits TEXT := public.normalize_mobile_digits(p_mobile);
  v_address TEXT := trim(COALESCE(p_address, ''));
  v_pan TEXT := upper(regexp_replace(COALESCE(p_pan_number, ''), '\s', '', 'g'));
  v_aadhaar TEXT := regexp_replace(COALESCE(p_aadhaar_number, ''), '\D', '', 'g');
  v_nominee_name TEXT := trim(COALESCE(p_nominee_name, ''));
  v_relationship TEXT := trim(COALESCE(p_nominee_relationship, ''));
  v_nominee_aadhaar TEXT := regexp_replace(COALESCE(p_nominee_aadhaar, ''), '\D', '', 'g');
  v_nominee_pan TEXT := upper(regexp_replace(COALESCE(p_nominee_pan, ''), '\s', '', 'g'));
  v_nominee_mobile TEXT := regexp_replace(COALESCE(p_nominee_mobile, ''), '\D', '', 'g');
  v_nominee_id UUID;
  v_new_bank_id UUID;
  v_bank_changed BOOLEAN;
BEGIN
  SELECT i.user_id, i.status, i.bank_account_id, c.customer_id
  INTO v_user_id, v_status, v_bank_id, v_customer_id
  FROM public.investments i
  LEFT JOIN public.customers c ON c.user_id = i.user_id
  WHERE i.id = p_id
  FOR UPDATE OF i;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Investment not found.';
  END IF;

  IF v_status <> 'Active' THEN
    RAISE EXCEPTION 'Only active approved investments can be edited.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Customer record not found for this investment.';
  END IF;

  IF v_plan = '' THEN
    RAISE EXCEPTION 'Plan / fund title is required.';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Enter a valid fund amount.';
  END IF;

  IF v_rate < 0 OR v_rate > 1 THEN
    RAISE EXCEPTION 'Interest rate must be between 0 and 1 (e.g. 0.12 for 12%%).';
  END IF;

  IF v_tds < 0 OR v_tds > 1 THEN
    RAISE EXCEPTION 'TDS percent must be between 0 and 1 (e.g. 0.10 for 10%%).';
  END IF;

  IF v_payout NOT IN (1, 5, 10, 15, 20, 25) THEN
    RAISE EXCEPTION 'Select a valid payout day.';
  END IF;

  IF v_full_name = '' THEN
    RAISE EXCEPTION 'Full name is required.';
  END IF;

  IF v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' THEN
    RAISE EXCEPTION 'Enter a valid email address.';
  END IF;

  IF v_mobile_digits IS NULL OR length(v_mobile_digits) <> 10 OR v_mobile_digits !~ '^[6-9][0-9]{9}$' THEN
    RAISE EXCEPTION 'Enter a valid 10-digit Indian mobile number.';
  END IF;

  IF p_date_of_birth IS NULL THEN
    RAISE EXCEPTION 'Enter a valid date of birth.';
  END IF;

  IF v_address = '' THEN
    RAISE EXCEPTION 'Address is required.';
  END IF;

  IF v_pan <> '' AND v_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' THEN
    RAISE EXCEPTION 'Enter a valid PAN (e.g. ABCDE1234F).';
  END IF;

  IF v_aadhaar <> '' AND v_aadhaar !~ '^[0-9]{12}$' THEN
    RAISE EXCEPTION 'Aadhaar number must be 12 digits.';
  END IF;

  IF v_nominee_aadhaar <> '' AND v_nominee_aadhaar !~ '^[0-9]{12}$' THEN
    RAISE EXCEPTION 'Nominee Aadhaar number must be 12 digits.';
  END IF;

  IF v_nominee_pan <> '' AND v_nominee_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' THEN
    RAISE EXCEPTION 'Enter a valid nominee PAN (e.g. ABCDE1234F).';
  END IF;

  IF v_nominee_mobile <> '' AND v_nominee_mobile !~ '^[6-9][0-9]{9}$' THEN
    RAISE EXCEPTION 'Enter a valid 10-digit nominee mobile number.';
  END IF;

  IF v_bank_name = '' THEN
    RAISE EXCEPTION 'Bank name is required.';
  END IF;

  IF v_account !~ '^[0-9]{9,18}$' THEN
    RAISE EXCEPTION 'Account number must be 9 to 18 digits.';
  END IF;

  IF v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' THEN
    RAISE EXCEPTION 'Enter a valid IFSC code.';
  END IF;

  IF v_type NOT IN ('Savings', 'Current') THEN
    RAISE EXCEPTION 'Account type must be Savings or Current.';
  END IF;

  -- Current identity on THIS customer only
  SELECT
    lower(trim(COALESCE(email_address, ''))),
    public.normalize_mobile_digits(mobile_number)
  INTO v_cur_email, v_cur_mobile
  FROM public.profiles
  WHERE user_id = v_user_id;

  -- Uniqueness only when email/mobile actually change
  IF v_email IS DISTINCT FROM v_cur_email
     AND EXISTS (
       SELECT 1
       FROM public.profiles p
       INNER JOIN public.customers c ON c.user_id = p.user_id
       WHERE lower(trim(COALESCE(p.email_address, ''))) = v_email
         AND p.user_id <> v_user_id
     ) THEN
    RAISE EXCEPTION 'Another customer already uses this email.';
  END IF;

  IF v_mobile_digits IS DISTINCT FROM v_cur_mobile
     AND EXISTS (
       SELECT 1
       FROM public.profiles p
       INNER JOIN public.customers c ON c.user_id = p.user_id
       WHERE public.normalize_mobile_digits(p.mobile_number) = v_mobile_digits
         AND p.user_id <> v_user_id
     ) THEN
    RAISE EXCEPTION 'Another customer already uses this mobile number.';
  END IF;

  -- Update the customer linked to this investment (CUST-xx via user_id)
  UPDATE public.profiles
  SET
    full_name = v_full_name,
    email_address = v_email,
    mobile_number = '+91' || v_mobile_digits,
    date_of_birth = p_date_of_birth,
    address = v_address,
    updated_at = NOW()
  WHERE user_id = v_user_id;

  IF v_pan <> '' OR v_aadhaar <> '' THEN
    INSERT INTO public.kyc_documents (user_id, aadhaar_number, pan_number)
    VALUES (
      v_user_id,
      COALESCE(NULLIF(v_aadhaar, ''), '000000000000'),
      COALESCE(NULLIF(v_pan, ''), '')
    )
    ON CONFLICT (user_id) DO UPDATE
      SET aadhaar_number = COALESCE(NULLIF(v_aadhaar, ''), kyc_documents.aadhaar_number),
          pan_number = COALESCE(NULLIF(v_pan, ''), kyc_documents.pan_number);
  END IF;

  IF v_nominee_name <> ''
     OR v_relationship <> ''
     OR v_nominee_aadhaar <> ''
     OR v_nominee_pan <> ''
     OR v_nominee_mobile <> '' THEN
    SELECT id INTO v_nominee_id
    FROM public.nominees
    WHERE user_id = v_user_id
    ORDER BY created_at ASC
    LIMIT 1;

    IF v_nominee_id IS NULL THEN
      INSERT INTO public.nominees (
        user_id,
        nominee_name,
        relationship,
        nominee_aadhaar
      ) VALUES (
        v_user_id,
        COALESCE(NULLIF(v_nominee_name, ''), 'Nominee'),
        COALESCE(NULLIF(v_relationship, ''), 'Other'),
        COALESCE(NULLIF(v_nominee_aadhaar, ''), '000000000000')
      )
      RETURNING id INTO v_nominee_id;
    ELSE
      UPDATE public.nominees
      SET
        nominee_name = COALESCE(NULLIF(v_nominee_name, ''), nominee_name),
        relationship = COALESCE(NULLIF(v_relationship, ''), relationship),
        nominee_aadhaar = COALESCE(NULLIF(v_nominee_aadhaar, ''), nominee_aadhaar)
      WHERE id = v_nominee_id
        AND user_id = v_user_id;
    END IF;

    BEGIN
      IF v_nominee_pan <> '' THEN
        EXECUTE 'UPDATE public.nominees SET nominee_pan = $1 WHERE id = $2 AND user_id = $3'
          USING v_nominee_pan, v_nominee_id, v_user_id;
      END IF;
      IF v_nominee_mobile <> '' THEN
        EXECUTE 'UPDATE public.nominees SET nominee_mobile = $1 WHERE id = $2 AND user_id = $3'
          USING v_nominee_mobile, v_nominee_id, v_user_id;
      END IF;
    EXCEPTION
      WHEN undefined_column THEN
        NULL;
    END;
  END IF;

  IF v_holder = '' THEN
    v_holder := v_full_name;
  END IF;

  IF v_bank_id IS NOT NULL THEN
    SELECT
      regexp_replace(COALESCE(account_number, ''), '\s', '', 'g'),
      upper(regexp_replace(COALESCE(ifsc_code, ''), '\s', '', 'g')),
      trim(COALESCE(bank_name, '')),
      initcap(trim(COALESCE(account_type, 'Savings'))),
      trim(COALESCE(to_jsonb(ba)->>'account_holder_name', '')),
      trim(COALESCE(to_jsonb(ba)->>'branch_name', ''))
    INTO v_cur_account, v_cur_ifsc, v_cur_bank, v_cur_type, v_cur_holder, v_cur_branch
    FROM public.bank_accounts ba
    WHERE id = v_bank_id
      AND user_id = v_user_id;
  END IF;

  v_bank_changed :=
    v_bank_id IS NULL
    OR v_cur_account IS DISTINCT FROM v_account
    OR v_cur_ifsc IS DISTINCT FROM v_ifsc
    OR lower(COALESCE(v_cur_bank, '')) IS DISTINCT FROM lower(v_bank_name)
    OR v_cur_type IS DISTINCT FROM v_type
    OR lower(COALESCE(v_cur_holder, '')) IS DISTINCT FROM lower(v_holder)
    OR lower(COALESCE(v_cur_branch, '')) IS DISTINCT FROM lower(v_branch);

  IF v_bank_changed THEN
    SELECT id INTO v_new_bank_id
    FROM public.bank_accounts
    WHERE user_id = v_user_id
      AND regexp_replace(COALESCE(account_number, ''), '\s', '', 'g') = v_account
      AND upper(regexp_replace(COALESCE(ifsc_code, ''), '\s', '', 'g')) = v_ifsc
    LIMIT 1;

    IF v_new_bank_id IS NULL THEN
      v_new_bank_id := (
        public.admin_add_bank_account(
          v_user_id,
          v_bank_name,
          v_account,
          v_ifsc,
          v_type,
          v_holder,
          NULLIF(v_branch, ''),
          FALSE
        )->>'id'
      )::UUID;
    ELSE
      PERFORM public.admin_update_bank_account(
        v_user_id,
        v_new_bank_id,
        v_bank_name,
        v_account,
        v_ifsc,
        v_type,
        v_holder,
        NULLIF(v_branch, ''),
        NULL
      );
    END IF;

    UPDATE public.investments
    SET bank_account_id = v_new_bank_id,
        updated_at = NOW()
    WHERE id = p_id
      AND user_id = v_user_id;
  END IF;

  UPDATE public.investments
  SET
    name = v_plan,
    fund_amount = v_amount,
    interest_rate = v_rate,
    tds_percent = v_tds,
    payout_day = v_payout,
    updated_at = NOW()
  WHERE id = p_id
    AND user_id = v_user_id;

  IF EXISTS (
    SELECT 1 FROM public.investment_agreements
    WHERE investment_id = p_id AND renewal_id IS NULL
  ) THEN
    IF v_agr_branch IN ('ballari', 'raichur')
       AND v_cheque_no <> ''
       AND v_cheque_bank <> ''
       AND v_cheque_addr <> '' THEN
      UPDATE public.investment_agreements
      SET
        branch = v_agr_branch,
        cheque_no = v_cheque_no,
        cheque_bank_name = v_cheque_bank,
        cheque_bank_address = v_cheque_addr,
        fund_amount = v_amount,
        updated_at = NOW()
      WHERE investment_id = p_id
        AND renewal_id IS NULL;
    ELSE
      UPDATE public.investment_agreements
      SET fund_amount = v_amount,
          updated_at = NOW()
      WHERE investment_id = p_id
        AND renewal_id IS NULL;
    END IF;
  END IF;

  RETURN json_build_object(
    'ok', true,
    'id', p_id,
    'user_id', v_user_id,
    'customer_id', v_customer_id
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
