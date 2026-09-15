-- Admin customer edit RPCs (no new tables).
-- Uses existing profiles, kyc_documents, bank_accounts, investments columns.

-- ---------------------------------------------------------------------------
-- Enriched customer details (banks + investments for payout bank changes)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_customer_details(p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile JSON;
  v_banks JSON;
  v_investments JSON;
  v_transactions JSON;
  v_active_count BIGINT;
  v_total_invested NUMERIC(15, 2);
  v_returns NUMERIC(15, 2);
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  SELECT json_build_object(
    'user_id', c.user_id,
    'customer_id', c.customer_id,
    'full_name', p.full_name,
    'mobile_number', p.mobile_number,
    'email_address', p.email_address,
    'date_of_birth', p.date_of_birth,
    'address', p.address,
    'city', p.city,
    'state', p.state,
    'pin_code', p.pin_code,
    'pan_number', k.pan_number
  )
  INTO v_profile
  FROM public.customers c
  INNER JOIN public.profiles p ON p.user_id = c.user_id
  LEFT JOIN public.kyc_documents k ON k.user_id = c.user_id
  WHERE c.user_id = p_user_id;

  IF v_profile IS NULL THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE i.status = 'Active'),
    COALESCE(SUM(i.fund_amount) FILTER (WHERE i.status = 'Active'), 0),
    COALESCE(SUM(i.total_earnings) FILTER (WHERE i.status IN ('Active', 'Closed')), 0)
  INTO v_active_count, v_total_invested, v_returns
  FROM public.investments i
  WHERE i.user_id = p_user_id;

  SELECT COALESCE(json_agg(bank_row ORDER BY is_primary DESC, created_at ASC), '[]'::JSON)
  INTO v_banks
  FROM (
    SELECT
      json_build_object(
        'id', ba.id,
        'bank_name', ba.bank_name,
        'account_number', ba.account_number,
        'ifsc_code', ba.ifsc_code,
        'account_type', ba.account_type,
        'is_primary', ba.is_primary,
        'account_holder_name', COALESCE(to_jsonb(ba)->>'account_holder_name', ''),
        'branch_name', COALESCE(to_jsonb(ba)->>'branch_name', '')
      ) AS bank_row,
      ba.is_primary,
      ba.created_at
    FROM public.bank_accounts ba
    WHERE ba.user_id = p_user_id
  ) banks;

  SELECT COALESCE(json_agg(inv_row ORDER BY created_at DESC), '[]'::JSON)
  INTO v_investments
  FROM (
    SELECT
      json_build_object(
        'id', i.id,
        'code', i.code,
        'plan_name', i.name,
        'fund_amount', i.fund_amount,
        'status', i.status,
        'bank_account_id', i.bank_account_id,
        'created_at', i.created_at
      ) AS inv_row,
      i.created_at
    FROM public.investments i
    WHERE i.user_id = p_user_id
      AND i.status IN ('Pending', 'Under Review', 'Active')
  ) invs;

  SELECT COALESCE(json_agg(txn_row ORDER BY sort_date DESC, sort_ts DESC), '[]'::JSON)
  INTO v_transactions
  FROM (
    SELECT
      json_build_object(
        'id', t.id,
        'occurred_on', t.transaction_date,
        'transaction_type', t.transaction_type,
        'amount', t.amount,
        'status', 'Completed'
      ) AS txn_row,
      t.transaction_date::TIMESTAMPTZ AS sort_date,
      t.created_at AS sort_ts
    FROM public.transactions t
    WHERE t.user_id = p_user_id

    UNION ALL

    SELECT
      json_build_object(
        'id', w.id,
        'occurred_on', w.requested_on,
        'transaction_type', 'withdrawal',
        'amount', COALESCE(w.net_payout, w.withdrawal_amount),
        'status', 'Pending'
      ) AS txn_row,
      w.requested_on::TIMESTAMPTZ AS sort_date,
      w.created_at AS sort_ts
    FROM public.withdrawals w
    WHERE w.user_id = p_user_id
      AND w.status IN ('Processing', 'Approved')
      AND NOT EXISTS (
        SELECT 1
        FROM public.transactions t
        WHERE t.source_type = 'withdrawal'
          AND t.source_id = w.id
      )
  ) ledger;

  RETURN json_build_object(
    'profile', v_profile,
    'account_active', COALESCE(v_active_count, 0) > 0,
    'summary', json_build_object(
      'total_invested', COALESCE(v_total_invested, 0),
      'active_plans', COALESCE(v_active_count, 0),
      'returns_earned', COALESCE(v_returns, 0)
    ),
    'banks', v_banks,
    'investments', v_investments,
    'transactions', v_transactions
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Update profile (+ optional PAN on kyc_documents)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_customer_profile(
  p_user_id UUID,
  p_full_name TEXT,
  p_email TEXT,
  p_mobile TEXT,
  p_date_of_birth DATE,
  p_address TEXT,
  p_city TEXT,
  p_state TEXT,
  p_pin_code TEXT,
  p_pan_number TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_full_name TEXT := trim(COALESCE(p_full_name, ''));
  v_email TEXT := lower(trim(COALESCE(p_email, '')));
  v_mobile_digits TEXT := public.normalize_mobile_digits(p_mobile);
  v_address TEXT := trim(COALESCE(p_address, ''));
  v_city TEXT := trim(COALESCE(p_city, ''));
  v_state TEXT := trim(COALESCE(p_state, ''));
  v_pin TEXT := trim(COALESCE(p_pin_code, ''));
  v_pan TEXT := upper(regexp_replace(COALESCE(p_pan_number, ''), '\s', '', 'g'));
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.customers WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'Customer not found.';
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

  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE lower(email_address) = v_email
      AND user_id <> p_user_id
  ) THEN
    RAISE EXCEPTION 'Another customer already uses this email.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE public.normalize_mobile_digits(mobile_number) = v_mobile_digits
      AND user_id <> p_user_id
  ) THEN
    RAISE EXCEPTION 'Another customer already uses this mobile number.';
  END IF;

  UPDATE public.profiles
  SET
    full_name = v_full_name,
    email_address = v_email,
    mobile_number = '+91' || v_mobile_digits,
    date_of_birth = p_date_of_birth,
    address = v_address,
    city = COALESCE(NULLIF(v_city, ''), city),
    state = COALESCE(NULLIF(v_state, ''), state),
    pin_code = COALESCE(NULLIF(v_pin, ''), pin_code),
    updated_at = NOW()
  WHERE user_id = p_user_id;

  IF v_pan <> '' THEN
    IF v_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' THEN
      RAISE EXCEPTION 'Enter a valid PAN (e.g. ABCDE1234F).';
    END IF;

    INSERT INTO public.kyc_documents (user_id, aadhaar_number, pan_number)
    VALUES (p_user_id, '000000000000', v_pan)
    ON CONFLICT (user_id) DO UPDATE
      SET pan_number = EXCLUDED.pan_number;
  END IF;

  RETURN json_build_object('ok', true, 'user_id', p_user_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Update existing bank account
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_bank_account(
  p_user_id UUID,
  p_bank_id UUID,
  p_bank_name TEXT,
  p_account_number TEXT,
  p_ifsc_code TEXT,
  p_account_type TEXT,
  p_account_holder_name TEXT DEFAULT NULL,
  p_branch_name TEXT DEFAULT NULL,
  p_is_primary BOOLEAN DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bank_name TEXT := trim(COALESCE(p_bank_name, ''));
  v_account TEXT := regexp_replace(COALESCE(p_account_number, ''), '\s', '', 'g');
  v_ifsc TEXT := upper(regexp_replace(COALESCE(p_ifsc_code, ''), '\s', '', 'g'));
  v_type TEXT := initcap(trim(COALESCE(p_account_type, 'Savings')));
  v_holder TEXT := trim(COALESCE(p_account_holder_name, ''));
  v_branch TEXT := trim(COALESCE(p_branch_name, ''));
BEGIN
  IF p_user_id IS NULL OR p_bank_id IS NULL THEN
    RAISE EXCEPTION 'Bank account not found.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.bank_accounts
    WHERE id = p_bank_id AND user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'Bank account does not belong to this customer.';
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

  IF COALESCE(p_is_primary, FALSE) THEN
    UPDATE public.bank_accounts
    SET is_primary = FALSE
    WHERE user_id = p_user_id
      AND id <> p_bank_id;
  END IF;

  BEGIN
    UPDATE public.bank_accounts
    SET
      bank_name = v_bank_name,
      account_number = v_account,
      ifsc_code = v_ifsc,
      account_type = v_type,
      is_primary = COALESCE(p_is_primary, is_primary),
      account_holder_name = COALESCE(NULLIF(v_holder, ''), account_holder_name),
      branch_name = COALESCE(NULLIF(v_branch, ''), branch_name)
    WHERE id = p_bank_id
      AND user_id = p_user_id;
  EXCEPTION
    WHEN undefined_column THEN
      UPDATE public.bank_accounts
      SET
        bank_name = v_bank_name,
        account_number = v_account,
        ifsc_code = v_ifsc,
        account_type = v_type,
        is_primary = COALESCE(p_is_primary, is_primary)
      WHERE id = p_bank_id
        AND user_id = p_user_id;
  END;

  RETURN json_build_object('ok', true, 'id', p_bank_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Add bank account for customer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_add_bank_account(
  p_user_id UUID,
  p_bank_name TEXT,
  p_account_number TEXT,
  p_ifsc_code TEXT,
  p_account_type TEXT,
  p_account_holder_name TEXT DEFAULT NULL,
  p_branch_name TEXT DEFAULT NULL,
  p_is_primary BOOLEAN DEFAULT FALSE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bank_name TEXT := trim(COALESCE(p_bank_name, ''));
  v_account TEXT := regexp_replace(COALESCE(p_account_number, ''), '\s', '', 'g');
  v_ifsc TEXT := upper(regexp_replace(COALESCE(p_ifsc_code, ''), '\s', '', 'g'));
  v_type TEXT := initcap(trim(COALESCE(p_account_type, 'Savings')));
  v_holder TEXT := trim(COALESCE(p_account_holder_name, ''));
  v_branch TEXT := trim(COALESCE(p_branch_name, ''));
  v_id UUID;
  v_make_primary BOOLEAN := COALESCE(p_is_primary, FALSE);
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.customers WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'Customer not found.';
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

  IF v_holder = '' THEN
    v_holder := COALESCE(
      (SELECT full_name FROM public.profiles WHERE user_id = p_user_id),
      'Account Holder'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.bank_accounts WHERE user_id = p_user_id) THEN
    v_make_primary := TRUE;
  END IF;

  IF v_make_primary THEN
    UPDATE public.bank_accounts SET is_primary = FALSE WHERE user_id = p_user_id;
  END IF;

  BEGIN
    INSERT INTO public.bank_accounts (
      user_id, bank_name, account_number, ifsc_code, account_type, is_primary,
      account_holder_name, branch_name
    ) VALUES (
      p_user_id, v_bank_name, v_account, v_ifsc, v_type, v_make_primary,
      v_holder, NULLIF(v_branch, '')
    )
    RETURNING id INTO v_id;
  EXCEPTION
    WHEN undefined_column THEN
      INSERT INTO public.bank_accounts (
        user_id, bank_name, account_number, ifsc_code, account_type, is_primary
      ) VALUES (
        p_user_id, v_bank_name, v_account, v_ifsc, v_type, v_make_primary
      )
      RETURNING id INTO v_id;
  END;

  RETURN json_build_object('ok', true, 'id', v_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Change payout bank on an investment (Pending / Under Review / Active)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_investment_bank(
  p_investment_id UUID,
  p_bank_account_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_status TEXT;
BEGIN
  IF p_investment_id IS NULL OR p_bank_account_id IS NULL THEN
    RAISE EXCEPTION 'Select an investment and bank account.';
  END IF;

  SELECT user_id, status
  INTO v_user_id, v_status
  FROM public.investments
  WHERE id = p_investment_id
  FOR UPDATE;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Investment not found.';
  END IF;

  IF v_status NOT IN ('Pending', 'Under Review', 'Active') THEN
    RAISE EXCEPTION 'Only pending, under review, or active investments can change bank account.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.bank_accounts
    WHERE id = p_bank_account_id
      AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Selected bank account does not belong to this customer.';
  END IF;

  UPDATE public.investments
  SET
    bank_account_id = p_bank_account_id,
    updated_at = NOW()
  WHERE id = p_investment_id;

  RETURN json_build_object(
    'ok', true,
    'id', p_investment_id,
    'bank_account_id', p_bank_account_id,
    'status', v_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_customer_details(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_customer_profile(UUID, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_bank_account(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_add_bank_account(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_investment_bank(UUID, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_get_customer_details(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_customer_profile(UUID, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_bank_account(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_bank_account(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_investment_bank(UUID, UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
