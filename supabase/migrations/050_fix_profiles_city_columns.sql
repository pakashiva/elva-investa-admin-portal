-- Customer Details / profile RPCs: use profiles.address only.
-- Do NOT require city / state / pin_code (those columns are not collected
-- and may not exist on the live profiles table).
-- Additive / replace-functions only. No drops of tables or data.

-- ---------------------------------------------------------------------------
-- Customer details
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
  v_nominee JSON;
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
    'pan_number', k.pan_number,
    'aadhaar_number', NULLIF(k.aadhaar_number, '000000000000')
  )
  INTO v_profile
  FROM public.customers c
  INNER JOIN public.profiles p ON p.user_id = c.user_id
  LEFT JOIN public.kyc_documents k ON k.user_id = c.user_id
  WHERE c.user_id = p_user_id;

  IF v_profile IS NULL THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  SELECT json_build_object(
    'id', n.id,
    'nominee_name', n.nominee_name,
    'relationship', n.relationship,
    'nominee_aadhaar', NULLIF(n.nominee_aadhaar, '000000000000'),
    'nominee_pan', to_jsonb(n)->>'nominee_pan',
    'nominee_mobile', to_jsonb(n)->>'nominee_mobile'
  )
  INTO v_nominee
  FROM public.nominees n
  WHERE n.user_id = p_user_id
  ORDER BY n.created_at ASC
  LIMIT 1;

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
    'nominee', v_nominee,
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
-- Update profile: address only (p_city / p_state / p_pin_code kept for
-- signature compatibility but ignored)
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
  p_pan_number TEXT DEFAULT NULL,
  p_aadhaar_number TEXT DEFAULT NULL,
  p_nominee_name TEXT DEFAULT NULL,
  p_nominee_relationship TEXT DEFAULT NULL,
  p_nominee_aadhaar TEXT DEFAULT NULL,
  p_nominee_pan TEXT DEFAULT NULL,
  p_nominee_mobile TEXT DEFAULT NULL
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
  v_pan TEXT := upper(regexp_replace(COALESCE(p_pan_number, ''), '\s', '', 'g'));
  v_aadhaar TEXT := regexp_replace(COALESCE(p_aadhaar_number, ''), '\D', '', 'g');
  v_nominee_name TEXT := trim(COALESCE(p_nominee_name, ''));
  v_relationship TEXT := trim(COALESCE(p_nominee_relationship, ''));
  v_nominee_aadhaar TEXT := regexp_replace(COALESCE(p_nominee_aadhaar, ''), '\D', '', 'g');
  v_nominee_pan TEXT := upper(regexp_replace(COALESCE(p_nominee_pan, ''), '\s', '', 'g'));
  v_nominee_mobile TEXT := regexp_replace(COALESCE(p_nominee_mobile, ''), '\D', '', 'g');
  v_nominee_id UUID;
BEGIN
  -- Unused legacy params kept so existing portal clients keep working.
  PERFORM p_city, p_state, p_pin_code;

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
    updated_at = NOW()
  WHERE user_id = p_user_id;

  IF v_pan <> '' OR v_aadhaar <> '' THEN
    INSERT INTO public.kyc_documents (user_id, aadhaar_number, pan_number)
    VALUES (
      p_user_id,
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
    WHERE user_id = p_user_id
    ORDER BY created_at ASC
    LIMIT 1;

    IF v_nominee_id IS NULL THEN
      INSERT INTO public.nominees (
        user_id,
        nominee_name,
        relationship,
        nominee_aadhaar
      ) VALUES (
        p_user_id,
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
      WHERE id = v_nominee_id;
    END IF;

    BEGIN
      IF v_nominee_pan <> '' THEN
        EXECUTE 'UPDATE public.nominees SET nominee_pan = $1 WHERE id = $2'
          USING v_nominee_pan, v_nominee_id;
      END IF;
      IF v_nominee_mobile <> '' THEN
        EXECUTE 'UPDATE public.nominees SET nominee_mobile = $1 WHERE id = $2'
          USING v_nominee_mobile, v_nominee_id;
      END IF;
    EXCEPTION
      WHEN undefined_column THEN
        NULL;
    END;
  END IF;

  RETURN json_build_object('ok', true, 'user_id', p_user_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Create customer: insert profiles without city / state / pin_code
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_create_customer(
  p_full_name TEXT,
  p_email TEXT,
  p_mobile TEXT,
  p_date_of_birth DATE,
  p_nominee_name TEXT,
  p_nominee_relationship TEXT,
  p_address TEXT,
  p_account_holder_name TEXT,
  p_account_number TEXT,
  p_ifsc_code TEXT,
  p_branch_name TEXT,
  p_account_type TEXT,
  p_pan_number TEXT DEFAULT NULL,
  p_aadhaar_number TEXT DEFAULT NULL,
  p_nominee_aadhaar TEXT DEFAULT NULL,
  p_nominee_pan TEXT DEFAULT NULL,
  p_nominee_mobile TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_email TEXT := lower(trim(COALESCE(p_email, '')));
  v_mobile_digits TEXT := public.normalize_mobile_digits(p_mobile);
  v_full_name TEXT := trim(COALESCE(p_full_name, ''));
  v_nominee_name TEXT := trim(COALESCE(p_nominee_name, ''));
  v_relationship TEXT := trim(COALESCE(p_nominee_relationship, ''));
  v_address TEXT := trim(COALESCE(p_address, ''));
  v_holder TEXT := trim(COALESCE(p_account_holder_name, ''));
  v_account TEXT := regexp_replace(COALESCE(p_account_number, ''), '\s', '', 'g');
  v_ifsc TEXT := upper(regexp_replace(COALESCE(p_ifsc_code, ''), '\s', '', 'g'));
  v_branch TEXT := trim(COALESCE(p_branch_name, ''));
  v_account_type TEXT := initcap(trim(COALESCE(p_account_type, 'Savings')));
  v_pan TEXT := upper(regexp_replace(COALESCE(p_pan_number, ''), '\s', '', 'g'));
  v_aadhaar TEXT := regexp_replace(COALESCE(p_aadhaar_number, ''), '\D', '', 'g');
  v_nominee_aadhaar TEXT := regexp_replace(COALESCE(p_nominee_aadhaar, ''), '\D', '', 'g');
  v_nominee_pan TEXT := upper(regexp_replace(COALESCE(p_nominee_pan, ''), '\s', '', 'g'));
  v_nominee_mobile TEXT := regexp_replace(COALESCE(p_nominee_mobile, ''), '\D', '', 'g');
  v_temp_password TEXT;
  v_customer_id TEXT;
  v_bank_id UUID;
  v_nominee_id UUID;
  v_instance_id UUID;
BEGIN
  IF v_full_name = '' THEN
    RAISE EXCEPTION 'Full name is required.';
  END IF;

  IF v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' THEN
    RAISE EXCEPTION 'Enter a valid email address.';
  END IF;

  IF v_mobile_digits IS NULL OR length(v_mobile_digits) <> 10 OR v_mobile_digits !~ '^[6-9][0-9]{9}$' THEN
    RAISE EXCEPTION 'Enter a valid 10-digit Indian mobile number.';
  END IF;

  IF p_date_of_birth IS NULL OR p_date_of_birth > (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE THEN
    RAISE EXCEPTION 'Enter a valid date of birth.';
  END IF;

  IF p_date_of_birth > ((NOW() AT TIME ZONE 'Asia/Kolkata')::DATE - INTERVAL '18 years') THEN
    RAISE EXCEPTION 'Customer must be at least 18 years old.';
  END IF;

  IF v_nominee_name = '' THEN
    RAISE EXCEPTION 'Nominee name is required.';
  END IF;

  IF v_relationship = '' THEN
    RAISE EXCEPTION 'Nominee relationship is required.';
  END IF;

  IF v_address = '' THEN
    RAISE EXCEPTION 'Full address is required.';
  END IF;

  IF v_pan = '' THEN
    RAISE EXCEPTION 'PAN number is required.';
  END IF;

  IF v_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' THEN
    RAISE EXCEPTION 'Enter a valid PAN (e.g. ABCDE1234F).';
  END IF;

  IF v_aadhaar = '' THEN
    RAISE EXCEPTION 'Aadhaar number is required.';
  END IF;

  IF v_aadhaar !~ '^[0-9]{12}$' THEN
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

  IF v_holder = '' THEN
    RAISE EXCEPTION 'Account holder name is required.';
  END IF;

  IF v_account !~ '^[0-9]{9,18}$' THEN
    RAISE EXCEPTION 'Account number must be 9 to 18 digits.';
  END IF;

  IF v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' THEN
    RAISE EXCEPTION 'Enter a valid IFSC code (e.g. SBIN0001234).';
  END IF;

  IF v_branch = '' THEN
    RAISE EXCEPTION 'Branch name is required.';
  END IF;

  IF v_account_type NOT IN ('Savings', 'Current') THEN
    RAISE EXCEPTION 'Account type must be Savings or Current.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM auth.users WHERE lower(email) = v_email
  ) THEN
    RAISE EXCEPTION 'An account with this email already exists.';
  END IF;

  IF NOT public.is_email_mobile_combo_available(v_email, v_mobile_digits) THEN
    RAISE EXCEPTION 'This email and mobile combination is already registered.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE public.normalize_mobile_digits(mobile_number) = v_mobile_digits
  ) THEN
    RAISE EXCEPTION 'This mobile number is already registered.';
  END IF;

  v_temp_password := 'Cust@' || right(v_mobile_digits, 4) || '!';

  SELECT id INTO v_instance_id FROM auth.instances LIMIT 1;
  IF v_instance_id IS NULL THEN
    v_instance_id := '00000000-0000-0000-0000-000000000000';
  END IF;

  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  ) VALUES (
    v_instance_id,
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(v_temp_password, gen_salt('bf')),
    NOW(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', v_full_name, 'created_by', 'admin_portal'),
    NOW(),
    NOW(),
    '',
    '',
    '',
    ''
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email',
    v_email,
    NOW(),
    NOW(),
    NOW()
  );

  -- Address only — no city / state / pin_code
  INSERT INTO public.profiles (
    user_id,
    full_name,
    mobile_number,
    email_address,
    date_of_birth,
    address,
    authorized,
    mobile_verified
  ) VALUES (
    v_user_id,
    v_full_name,
    '+91' || v_mobile_digits,
    v_email,
    p_date_of_birth,
    v_address,
    TRUE,
    TRUE
  );

  SELECT customer_id INTO v_customer_id
  FROM public.customers
  WHERE user_id = v_user_id;

  IF v_customer_id IS NULL THEN
    v_customer_id := public.ensure_customer_for_user(v_user_id);
  END IF;

  INSERT INTO public.kyc_documents (
    user_id,
    aadhaar_number,
    pan_number
  ) VALUES (
    v_user_id,
    v_aadhaar,
    v_pan
  )
  ON CONFLICT (user_id) DO UPDATE
    SET aadhaar_number = EXCLUDED.aadhaar_number,
        pan_number = EXCLUDED.pan_number;

  INSERT INTO public.bank_accounts (
    user_id,
    bank_name,
    account_number,
    ifsc_code,
    account_type,
    is_primary,
    account_holder_name,
    branch_name
  ) VALUES (
    v_user_id,
    COALESCE(NULLIF(v_branch, ''), left(v_ifsc, 4)),
    v_account,
    v_ifsc,
    v_account_type,
    TRUE,
    v_holder,
    v_branch
  )
  RETURNING id INTO v_bank_id;

  INSERT INTO public.nominees (
    user_id,
    nominee_name,
    relationship,
    nominee_aadhaar
  ) VALUES (
    v_user_id,
    v_nominee_name,
    v_relationship,
    COALESCE(NULLIF(v_nominee_aadhaar, ''), '000000000000')
  )
  RETURNING id INTO v_nominee_id;

  BEGIN
    IF v_nominee_pan <> '' THEN
      EXECUTE 'UPDATE public.nominees SET nominee_pan = $1 WHERE id = $2'
        USING v_nominee_pan, v_nominee_id;
    END IF;
    IF v_nominee_mobile <> '' THEN
      EXECUTE 'UPDATE public.nominees SET nominee_mobile = $1 WHERE id = $2'
        USING v_nominee_mobile, v_nominee_id;
    END IF;
  EXCEPTION
    WHEN undefined_column THEN
      NULL;
  END;

  RETURN json_build_object(
    'ok', true,
    'user_id', v_user_id,
    'customer_id', v_customer_id,
    'bank_account_id', v_bank_id,
    'nominee_id', v_nominee_id
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Customer with this email or mobile already exists.';
  WHEN OTHERS THEN
    RAISE EXCEPTION '%', SQLERRM;
END;
$$;

NOTIFY pgrst, 'reload schema';
