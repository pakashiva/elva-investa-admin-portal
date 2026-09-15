-- Extend investment request list/detail for admin portal display only.
-- No new tables/columns: uses existing investments.code, referral_code, referrer_user_id.

CREATE OR REPLACE FUNCTION public.admin_list_investment_requests(
  p_filter TEXT DEFAULT 'pending',
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 10,
  p_offset INTEGER DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_filter TEXT := lower(COALESCE(p_filter, 'pending'));
  v_search TEXT := NULLIF(trim(COALESCE(p_search, '')), '');
  v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_limit, 10), 50));
  v_offset INTEGER := GREATEST(0, COALESCE(p_offset, 0));
  v_total BIGINT;
  v_rows JSON;
BEGIN
  WITH base AS (
    SELECT
      i.id,
      i.code,
      i.request_id,
      i.name AS plan_name,
      i.fund_amount,
      i.status,
      i.created_at,
      p.full_name AS customer_name,
      c.customer_id
    FROM public.investments i
    INNER JOIN public.profiles p ON p.user_id = i.user_id
    LEFT JOIN public.customers c ON c.user_id = i.user_id
    WHERE (
        v_search IS NULL
        OR COALESCE(i.request_id, '') ILIKE '%' || v_search || '%'
        OR COALESCE(i.code, '') ILIKE '%' || v_search || '%'
        OR p.full_name ILIKE '%' || v_search || '%'
        OR COALESCE(c.customer_id, '') ILIKE '%' || v_search || '%'
        OR i.name ILIKE '%' || v_search || '%'
      )
      AND CASE v_filter
        WHEN 'pending' THEN i.status = 'Pending'
        WHEN 'under_review' THEN i.status = 'Under Review'
        WHEN 'approved' THEN i.status IN ('Active', 'Closed')
        WHEN 'rejected' THEN i.status = 'Rejected'
        ELSE TRUE
      END
  ),
  paged AS (
    SELECT *
    FROM base
    ORDER BY created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  )
  SELECT
    (SELECT COUNT(*) FROM base),
    COALESCE((SELECT json_agg(row_to_json(p)) FROM paged p), '[]'::JSON)
  INTO v_total, v_rows;

  RETURN json_build_object(
    'rows', v_rows,
    'total', COALESCE(v_total, 0),
    'limit', v_limit,
    'offset', v_offset
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_investment_request(p_id UUID)
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
    'plan_name', i.name,
    'fund_amount', i.fund_amount,
    'interest_rate', i.interest_rate,
    'tds_percent', i.tds_percent,
    'payout_day', i.payout_day,
    'created_at', i.created_at,
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

REVOKE ALL ON FUNCTION public.admin_list_investment_requests(TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_get_investment_request(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_investment_requests(TEXT, TEXT, INTEGER, INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_investment_request(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
