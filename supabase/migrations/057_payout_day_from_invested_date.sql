-- Stop using 10 as the payout-day default.
-- The cycle is the next date (1, 5, 10, 15, 20, 25) on or after the invested
-- date. After the 25th, that is the 1st of the next month.

CREATE OR REPLACE FUNCTION public.investment_cycle_day(p_on DATE)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_on IS NULL THEN NULL
    WHEN EXTRACT(DAY FROM p_on)::INT <= 1 THEN 1
    WHEN EXTRACT(DAY FROM p_on)::INT <= 5 THEN 5
    WHEN EXTRACT(DAY FROM p_on)::INT <= 10 THEN 10
    WHEN EXTRACT(DAY FROM p_on)::INT <= 15 THEN 15
    WHEN EXTRACT(DAY FROM p_on)::INT <= 20 THEN 20
    WHEN EXTRACT(DAY FROM p_on)::INT <= 25 THEN 25
    ELSE 1
  END;
$$;

ALTER TABLE public.investments
  ALTER COLUMN payout_day DROP DEFAULT;

CREATE OR REPLACE FUNCTION public.apply_investment_payout_cycle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_anchor DATE;
  v_cycle INTEGER;
  v_overridden BOOLEAN;
BEGIN
  v_overridden := COALESCE((to_jsonb(NEW)->>'payout_day_overridden')::boolean, FALSE);
  v_anchor := COALESCE(NEW.invested_date, (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE);
  v_cycle := public.investment_cycle_day(v_anchor);

  -- Leave an explicit admin choice alone. The stored 10 is only kept when
  -- the invested date really falls on the 10th cycle.
  IF v_overridden AND NEW.payout_day IS NOT NULL AND NEW.payout_day <> 10 THEN
    RETURN NEW;
  END IF;

  IF NEW.payout_day IS NULL OR NEW.payout_day = 10 THEN
    NEW.payout_day := v_cycle;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS investments_apply_payout_cycle ON public.investments;
CREATE TRIGGER investments_apply_payout_cycle
  BEFORE INSERT OR UPDATE OF payout_day, invested_date
  ON public.investments
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_investment_payout_cycle();

-- Correct rows still sitting on the old default.
UPDATE public.investments
SET payout_day = public.investment_cycle_day(
  COALESCE(invested_date, (created_at AT TIME ZONE 'Asia/Kolkata')::DATE)
)
WHERE payout_day = 10
  AND public.investment_cycle_day(
    COALESCE(invested_date, (created_at AT TIME ZONE 'Asia/Kolkata')::DATE)
  ) IS DISTINCT FROM 10;

CREATE OR REPLACE FUNCTION public.admin_create_investment_request(
  p_user_id UUID,
  p_amount NUMERIC,
  p_bank_account_id UUID,
  p_fund_title TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id TEXT;
  v_amount NUMERIC(15, 2) := COALESCE(p_amount, 0);
  v_min NUMERIC(15, 2);
  v_max NUMERIC(15, 2);
  v_bank_id UUID;
  v_nominee_id UUID;
  v_investment_id UUID;
  v_title TEXT := trim(COALESCE(p_fund_title, ''));
  v_next_n INTEGER;
  v_anchor DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_cycle INTEGER := public.investment_cycle_day(v_anchor);
  v_pay_date DATE;
  v_has_payout_day BOOLEAN;
BEGIN
  IF EXTRACT(DAY FROM v_anchor)::INT <= v_cycle THEN
    v_pay_date := make_date(
      EXTRACT(YEAR FROM v_anchor)::INT,
      EXTRACT(MONTH FROM v_anchor)::INT,
      v_cycle
    );
  ELSE
    v_pay_date := (date_trunc('month', v_anchor) + INTERVAL '1 month')::DATE;
    v_pay_date := make_date(
      EXTRACT(YEAR FROM v_pay_date)::INT,
      EXTRACT(MONTH FROM v_pay_date)::INT,
      v_cycle
    );
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Select a customer.';
  END IF;

  IF p_bank_account_id IS NULL THEN
    RAISE EXCEPTION 'Select a bank account number.';
  END IF;

  SELECT c.customer_id
  INTO v_customer_id
  FROM public.customers c
  WHERE c.user_id = p_user_id;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found.';
  END IF;

  SELECT ba.id
  INTO v_bank_id
  FROM public.bank_accounts ba
  WHERE ba.id = p_bank_account_id
    AND ba.user_id = p_user_id;

  IF v_bank_id IS NULL THEN
    RAISE EXCEPTION 'Selected bank account does not belong to this customer.';
  END IF;

  SELECT min_investment_amount, max_investment_amount
  INTO v_min, v_max
  FROM public.admin_portal_settings
  WHERE id = 1;

  v_min := COALESCE(v_min, 10000);
  v_max := COALESCE(v_max, 10000000);

  IF v_amount < v_min OR v_amount > v_max THEN
    RAISE EXCEPTION 'Investment amount must be between ₹% and ₹%.',
      to_char(v_min, 'FM999,999,999,990'),
      to_char(v_max, 'FM999,999,999,990');
  END IF;

  IF v_title = '' THEN
    SELECT COUNT(*)::INTEGER + 1
    INTO v_next_n
    FROM public.investments i
    WHERE i.user_id = p_user_id;

    v_title := 'Investment ' || v_next_n::TEXT;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.investments i
    WHERE i.user_id = p_user_id
      AND lower(trim(i.name)) = lower(v_title)
  ) THEN
    RAISE EXCEPTION 'An investment with this title already exists for this customer.';
  END IF;

  SELECT n.id
  INTO v_nominee_id
  FROM public.nominees n
  WHERE n.user_id = p_user_id
  ORDER BY n.created_at ASC
  LIMIT 1;

  IF v_nominee_id IS NULL THEN
    RAISE EXCEPTION 'Customer has no nominee. Add a nominee before creating an investment.';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'investments'
      AND column_name = 'payout_day'
  ) INTO v_has_payout_day;

  IF v_has_payout_day THEN
    EXECUTE
      'INSERT INTO public.investments (
         user_id, name, detail_subtitle, fund_amount, interest_rate, tds_percent,
         status, bank_account_id, nominee_id, pay_date, agreement_charges,
         current_value, total_earnings, tds_deducted_amount, completed_interest_periods,
         payout_day
       ) VALUES (
         $1, $2, $2, $3, 0.05, 0.10,
         ''Pending'', $4, $5, $6, 1000,
         $3, 0, 0, 0,
         $7
       )
       RETURNING id'
      INTO v_investment_id
      USING p_user_id, v_title, v_amount, v_bank_id, v_nominee_id, v_pay_date, v_cycle;
  ELSE
    INSERT INTO public.investments (
      user_id,
      name,
      detail_subtitle,
      fund_amount,
      interest_rate,
      tds_percent,
      status,
      bank_account_id,
      nominee_id,
      pay_date,
      agreement_charges,
      current_value,
      total_earnings,
      tds_deducted_amount,
      completed_interest_periods
    ) VALUES (
      p_user_id,
      v_title,
      v_title,
      v_amount,
      0.05,
      0.10,
      'Pending',
      v_bank_id,
      v_nominee_id,
      v_pay_date,
      1000,
      v_amount,
      0,
      0,
      0
    )
    RETURNING id INTO v_investment_id;
  END IF;

  RETURN json_build_object(
    'ok', true,
    'id', v_investment_id,
    'user_id', p_user_id,
    'customer_id', v_customer_id,
    'bank_account_id', v_bank_id,
    'fund_amount', v_amount,
    'name', v_title,
    'detail_subtitle', v_title,
    'status', 'Pending'
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
