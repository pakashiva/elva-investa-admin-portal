-- Post-approval actions: load/edit approved investment details, cancel, keep
-- agreement fund_amount in sync so Regenerate reflects DB changes.

-- ---------------------------------------------------------------------------
-- Snapshot for the Edit Approved Investment modal
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_approved_investment_edit(p_id UUID)
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
    'id', i.id,
    'code', i.code,
    'request_id', i.request_id,
    'status', i.status,
    'user_id', i.user_id,
    'customer_id', c.customer_id,
    'plan_name', i.name,
    'fund_amount', i.fund_amount,
    'interest_rate', i.interest_rate,
    'tds_percent', i.tds_percent,
    'payout_day', COALESCE(i.payout_day, 10),
    'customer', json_build_object(
      'full_name', p.full_name,
      'email', p.email_address,
      'mobile', p.mobile_number,
      'date_of_birth', p.date_of_birth,
      'address', p.address,
      'pan', COALESCE(k.pan_number, ''),
      'aadhaar', COALESCE(NULLIF(k.aadhaar_number, '000000000000'), '')
    ),
    'bank', CASE
      WHEN ba.id IS NULL THEN NULL
      ELSE json_build_object(
        'id', ba.id,
        'bank_name', ba.bank_name,
        'account_number', ba.account_number,
        'ifsc_code', ba.ifsc_code,
        'account_type', ba.account_type,
        'account_holder_name', COALESCE(to_jsonb(ba)->>'account_holder_name', p.full_name),
        'branch_name', COALESCE(to_jsonb(ba)->>'branch_name', '')
      )
    END,
    'nominee', CASE
      WHEN n.id IS NULL THEN NULL
      ELSE json_build_object(
        'name', n.nominee_name,
        'relation', n.relationship,
        'aadhaar', COALESCE(NULLIF(n.nominee_aadhaar, '000000000000'), ''),
        'pan', COALESCE(n.nominee_pan, ''),
        'mobile', COALESCE(n.nominee_mobile, '')
      )
    END,
    'agreement', CASE
      WHEN a.id IS NULL THEN NULL
      ELSE json_build_object(
        'branch', a.branch,
        'cheque_no', a.cheque_no,
        'cheque_bank_name', a.cheque_bank_name,
        'cheque_bank_address', a.cheque_bank_address
      )
    END
  )
  INTO v_result
  FROM public.investments i
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
  LEFT JOIN public.investment_agreements a
    ON a.investment_id = i.id AND a.renewal_id IS NULL
  WHERE i.id = p_id
    AND i.status IN ('Active', 'Closed');

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Approved investment not found.';
  END IF;

  RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- Persist edits: profile/KYC/nominee/investment; new bank row when bank changes
-- ---------------------------------------------------------------------------
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
  v_status TEXT;
  v_bank_id UUID;
  v_cur_account TEXT;
  v_cur_ifsc TEXT;
  v_cur_bank TEXT;
  v_cur_type TEXT;
  v_cur_holder TEXT;
  v_cur_branch TEXT;
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
  v_new_bank_id UUID;
  v_bank_changed BOOLEAN;
BEGIN
  SELECT user_id, status, bank_account_id
  INTO v_user_id, v_status, v_bank_id
  FROM public.investments
  WHERE id = p_id
  FOR UPDATE;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Investment not found.';
  END IF;

  IF v_status <> 'Active' THEN
    RAISE EXCEPTION 'Only active approved investments can be edited.';
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

  -- Profile / KYC / nominee via existing updater
  PERFORM public.admin_update_customer_profile(
    v_user_id,
    p_full_name,
    p_email,
    p_mobile,
    p_date_of_birth,
    p_address,
    NULL,
    NULL,
    NULL,
    p_pan_number,
    p_aadhaar_number,
    p_nominee_name,
    p_nominee_relationship,
    p_nominee_aadhaar,
    p_nominee_pan,
    p_nominee_mobile
  );

  IF v_holder = '' THEN
    v_holder := trim(COALESCE(p_full_name, ''));
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
    WHERE id = v_bank_id;
  END IF;

  v_bank_changed :=
    v_bank_id IS NULL
    OR v_cur_account IS DISTINCT FROM v_account
    OR v_cur_ifsc IS DISTINCT FROM v_ifsc
    OR lower(v_cur_bank) IS DISTINCT FROM lower(v_bank_name)
    OR v_cur_type IS DISTINCT FROM v_type
    OR lower(COALESCE(v_cur_holder, '')) IS DISTINCT FROM lower(v_holder)
    OR lower(COALESCE(v_cur_branch, '')) IS DISTINCT FROM lower(v_branch);

  IF v_bank_changed THEN
    -- Prefer an existing matching account for this customer before inserting.
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
    WHERE id = p_id;
  END IF;

  UPDATE public.investments
  SET
    name = v_plan,
    fund_amount = v_amount,
    interest_rate = v_rate,
    tds_percent = v_tds,
    payout_day = v_payout,
    updated_at = NOW()
  WHERE id = p_id;

  -- Keep stored agreement cheque + snapshot amount aligned for regenerate
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

  RETURN json_build_object('ok', true, 'id', p_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Withdraw / Cancel an active approved investment → Rejected (leaves Approved)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_cancel_approved_investment(p_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM public.investments
  WHERE id = p_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Investment not found.';
  END IF;

  IF v_status <> 'Active' THEN
    RAISE EXCEPTION 'Only active approved investments can be cancelled.';
  END IF;

  UPDATE public.investments
  SET status = 'Rejected',
      updated_at = NOW()
  WHERE id = p_id;

  -- Drop unpaid referral bonus tied to this investment
  DELETE FROM public.referral_rewards
  WHERE investment_id = p_id
    AND status = 'Pending';

  RETURN json_build_object('ok', true, 'id', p_id, 'status', 'Rejected');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_approved_investment_edit(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_approved_investment(
  UUID, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_cancel_approved_investment(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_get_approved_investment_edit(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_approved_investment(
  UUID, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TEXT, TEXT, TEXT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cancel_approved_investment(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
