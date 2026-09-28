-- Approval screen reads the stored payout cycle.
-- Do not coerce a saved payout_day to 10.
-- Leave payout_day unchanged unless the admin explicitly picks a day
-- (a database trigger then sets payout_day_overridden and rewrites pay_date).
-- Do not touch referral codes.

CREATE OR REPLACE FUNCTION public.admin_get_investment_request(p_id UUID)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
  v_default_referral NUMERIC(8, 6) := 0.01;
  v_referral_tds NUMERIC(8, 6) := 0.02;
BEGIN
  SELECT
    COALESCE(referral_rate, 0.01),
    COALESCE(tds_rate, 0.02)
  INTO v_default_referral, v_referral_tds
  FROM public.referral_settings
  WHERE id = 1;

  v_default_referral := COALESCE(v_default_referral, 0.01);
  v_referral_tds := COALESCE(v_referral_tds, 0.02);

  SELECT json_build_object(
    'id', i.id,
    'code', i.code,
    'request_id', i.request_id,
    'status', i.status,
    'plan_name', i.name,
    'fund_amount', i.fund_amount,
    'interest_rate', i.interest_rate,
    'tds_percent', i.tds_percent,
    'payout_day', i.payout_day,
    'payout_day_overridden', COALESCE((to_jsonb(i)->>'payout_day_overridden')::boolean, false),
    'pay_date', i.pay_date,
    'referral_rate', COALESCE(i.referral_rate, v_default_referral, 0.01),
    'referral_tds_rate', v_referral_tds,
    'created_at', i.created_at,
    'invested_date', i.invested_date,
    'user_id', i.user_id,
    'customer_name', p.full_name,
    'customer_id', c.customer_id,
    'referral_code', i.referral_code,
    'referrer_user_id', i.referrer_user_id,
    'referrer_name', ref.full_name,
    'active_portfolio', COALESCE((
      SELECT SUM(x.fund_amount) FROM public.investments x
      WHERE x.user_id = i.user_id AND x.status = 'Active'
    ), 0),
    'active_plans', COALESCE((
      SELECT COUNT(*) FROM public.investments x
      WHERE x.user_id = i.user_id AND x.status = 'Active'
    ), 0),
    'bank', CASE WHEN ba.id IS NULL THEN NULL ELSE json_build_object(
      'bank_name', ba.bank_name,
      'account_number', ba.account_number,
      'ifsc_code', ba.ifsc_code
    ) END
  )
  INTO v_result
  FROM public.investments i
  INNER JOIN public.profiles p ON p.user_id = i.user_id
  LEFT JOIN public.customers c ON c.user_id = i.user_id
  LEFT JOIN public.profiles ref ON ref.user_id = i.referrer_user_id
  LEFT JOIN public.bank_accounts ba ON ba.id = i.bank_account_id
  WHERE i.id = p_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Investment request not found';
  END IF;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_investment_terms(
  p_id UUID,
  p_interest_rate NUMERIC,
  p_tds_percent NUMERIC,
  p_payout_day INTEGER DEFAULT NULL,
  p_referral_rate NUMERIC DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.investments%ROWTYPE;
  v_referral_rate NUMERIC(8, 6);
BEGIN
  IF p_interest_rate IS NULL OR p_interest_rate <= 0 OR p_interest_rate > 1 THEN
    RAISE EXCEPTION 'Interest rate must be a decimal between 0 and 1 (e.g. 0.05).';
  END IF;

  IF p_tds_percent IS NULL OR p_tds_percent < 0 OR p_tds_percent > 1 THEN
    RAISE EXCEPTION 'TDS percent must be a decimal between 0 and 1.';
  END IF;

  IF p_payout_day IS NOT NULL AND NOT (p_payout_day = ANY (ARRAY[1, 5, 10, 15, 20, 25])) THEN
    RAISE EXCEPTION 'Payout day must be one of 1, 5, 10, 15, 20, or 25.';
  END IF;

  SELECT * INTO v_row
  FROM public.investments
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Investment request not found';
  END IF;

  IF v_row.status NOT IN ('Pending', 'Under Review') THEN
    RAISE EXCEPTION 'Only pending or held requests can have terms updated.';
  END IF;

  v_referral_rate := COALESCE(p_referral_rate, v_row.referral_rate, 0.01);
  IF v_referral_rate < 0 OR v_referral_rate > 1 THEN
    RAISE EXCEPTION 'Referral rate must be between 0%% and 100%%.';
  END IF;

  -- Omit payout_day unless the admin picked a day. Writing the column
  -- (even to the same value) would fire the override trigger.
  IF p_payout_day IS NULL THEN
    UPDATE public.investments
    SET
      interest_rate = p_interest_rate,
      tds_percent = p_tds_percent,
      referral_rate = v_referral_rate,
      updated_at = NOW()
    WHERE id = p_id
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.investments
    SET
      interest_rate = p_interest_rate,
      tds_percent = p_tds_percent,
      payout_day = p_payout_day,
      referral_rate = v_referral_rate,
      updated_at = NOW()
    WHERE id = p_id
    RETURNING * INTO v_row;
  END IF;

  RETURN json_build_object(
    'ok', true,
    'id', v_row.id,
    'interest_rate', v_row.interest_rate,
    'tds_percent', v_row.tds_percent,
    'payout_day', v_row.payout_day,
    'referral_rate', v_row.referral_rate,
    'status', v_row.status
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
