-- Fix investment approval persistence (no duplicate terms table).
-- Terms already live on public.investments:
--   interest_rate, tds_percent, payout_day, referral_rate, bank_account_id, status, …
-- Opening /investment-requests/:id later reloads those columns (read-only when Active).
--
-- This migration:
-- 1) Ensures referral_settings singleton exists (stops "not configured")
-- 2) Ensures investments.referral_rate exists (default 1%)
-- 3) Recreates admin_update_investment_terms with referral_rate (fixes schema cache miss)
-- 4) Hardens get + Active trigger to work even if settings row was missing

-- ---------------------------------------------------------------------------
-- 1. Referral settings singleton (defaults: 1% commission, 2% TDS on commission)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referral_settings (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  referral_rate NUMERIC(8, 6) NOT NULL DEFAULT 0.01,
  tds_rate NUMERIC(8, 6) NOT NULL DEFAULT 0.02,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.referral_settings (id, referral_rate, tds_rate)
VALUES (1, 0.01, 0.02)
ON CONFLICT (id) DO NOTHING;

-- Lock down direct client access; SECURITY DEFINER RPCs/triggers still read it.
ALTER TABLE public.referral_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "referral_settings_no_direct_access" ON public.referral_settings;
-- No policies for anon/authenticated = no direct SELECT/INSERT/UPDATE/DELETE via API keys.
-- Admin portal and mobile use SECURITY DEFINER functions only.

-- ---------------------------------------------------------------------------
-- 2. Per-investment referral rate (what admin sets on approval screen)
-- ---------------------------------------------------------------------------
ALTER TABLE public.investments
  ADD COLUMN IF NOT EXISTS referral_rate NUMERIC(8, 6);

UPDATE public.investments
SET referral_rate = 0.01
WHERE referral_rate IS NULL;

ALTER TABLE public.investments
  ALTER COLUMN referral_rate SET DEFAULT 0.01;

-- ---------------------------------------------------------------------------
-- 3. Drop every overload of update terms, then create one canonical signature
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'admin_update_investment_terms'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
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
  v_payout_day INTEGER;
  v_referral_rate NUMERIC(8, 6);
BEGIN
  IF p_interest_rate IS NULL OR p_interest_rate <= 0 OR p_interest_rate > 1 THEN
    RAISE EXCEPTION 'Interest rate must be a decimal between 0 and 1 (e.g. 0.05).';
  END IF;

  IF p_tds_percent IS NULL OR p_tds_percent < 0 OR p_tds_percent > 1 THEN
    RAISE EXCEPTION 'TDS percent must be a decimal between 0 and 1.';
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

  v_payout_day := COALESCE(p_payout_day, v_row.payout_day, 10);
  IF NOT (v_payout_day = ANY (ARRAY[1, 5, 10, 15, 20, 25])) THEN
    RAISE EXCEPTION 'Payout day must be one of 1, 5, 10, 15, 20, or 25.';
  END IF;

  v_referral_rate := COALESCE(p_referral_rate, v_row.referral_rate, 0.01);
  IF v_referral_rate < 0 OR v_referral_rate > 1 THEN
    RAISE EXCEPTION 'Referral rate must be between 0%% and 100%%.';
  END IF;

  UPDATE public.investments
  SET
    interest_rate = p_interest_rate,
    tds_percent = p_tds_percent,
    payout_day = v_payout_day,
    referral_rate = v_referral_rate,
    updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_row;

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

-- ---------------------------------------------------------------------------
-- 4. Detail payload always returns saved terms (for later review)
-- ---------------------------------------------------------------------------
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
    'payout_day', COALESCE(i.payout_day, 10),
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

-- ---------------------------------------------------------------------------
-- 5. Active trigger: never fail if settings missing; use investment.referral_rate
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_referral_reward_on_investment_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings RECORD;
  v_rate NUMERIC(8, 6);
  v_tds_rate NUMERIC(8, 6);
  v_gross NUMERIC(15, 2);
  v_tds NUMERIC(15, 2);
  v_net NUMERIC(15, 2);
BEGIN
  IF NEW.status <> 'Active'
     OR NOT (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    RETURN NEW;
  END IF;

  IF NEW.referrer_user_id IS NULL OR NEW.referral_code IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.referrer_user_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.referral_rewards WHERE investment_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  SELECT referral_rate, tds_rate
  INTO v_settings
  FROM public.referral_settings
  WHERE id = 1;

  v_rate := COALESCE(NEW.referral_rate, v_settings.referral_rate, 0.01);
  v_tds_rate := COALESCE(v_settings.tds_rate, 0.02);

  IF v_rate <= 0 OR v_rate > 1 THEN
    v_rate := 0.01;
  END IF;

  v_gross := round(NEW.fund_amount * v_rate, 2);
  v_tds := round(v_gross * v_tds_rate, 2);
  v_net := round(v_gross - v_tds, 2);

  INSERT INTO public.referral_rewards (
    referrer_user_id,
    referred_user_id,
    investment_id,
    referral_code,
    capital_amount,
    referral_rate,
    gross_bonus,
    tds_rate,
    tds_amount,
    net_bonus,
    status
  )
  VALUES (
    NEW.referrer_user_id,
    NEW.user_id,
    NEW.id,
    NEW.referral_code,
    NEW.fund_amount,
    v_rate,
    v_gross,
    v_tds_rate,
    v_tds,
    v_net,
    'Pending'
  )
  ON CONFLICT (investment_id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_investment_request(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_investment_terms(UUID, NUMERIC, NUMERIC, INTEGER, NUMERIC) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_get_investment_request(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_investment_terms(UUID, NUMERIC, NUMERIC, INTEGER, NUMERIC) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
