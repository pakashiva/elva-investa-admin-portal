-- Agreement renewal requests for admin Investments queue.
-- Additive: ensures increment_amount, admin list union, get + decide RPCs.

ALTER TABLE public.agreement_renewal_requests
  ADD COLUMN IF NOT EXISTS increment_amount NUMERIC(14, 2) NULL;

COMMENT ON COLUMN public.agreement_renewal_requests.increment_amount IS
  'Extra principal when mode = increase; null for same_amount.';

-- ---------------------------------------------------------------------------
-- Unified list: normal investment requests + agreement renewals
-- ---------------------------------------------------------------------------
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
  WITH inv AS (
    SELECT
      i.id,
      'investment'::TEXT AS kind,
      i.code,
      i.request_id,
      i.name AS plan_name,
      i.fund_amount,
      NULL::NUMERIC AS increment_amount,
      NULL::TEXT AS mode,
      NULL::TEXT AS agreement_id,
      i.status::TEXT AS status,
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
  ren AS (
    SELECT
      r.id,
      'renewal'::TEXT AS kind,
      i.code,
      COALESCE(r.agreement_id, i.request_id) AS request_id,
      CASE
        WHEN r.mode = 'increase' THEN 'Agreement Renewal · Increase'
        ELSE 'Agreement Renewal · Same Amount'
      END AS plan_name,
      CASE
        WHEN r.mode = 'increase'
          THEN COALESCE(r.current_amount, 0) + COALESCE(r.increment_amount, 0)
        ELSE COALESCE(r.current_amount, i.fund_amount, 0)
      END AS fund_amount,
      r.increment_amount,
      r.mode,
      r.agreement_id,
      r.status::TEXT AS status,
      r.created_at,
      p.full_name AS customer_name,
      COALESCE(r.customer_id, c.customer_id) AS customer_id
    FROM public.agreement_renewal_requests r
    INNER JOIN public.investments i ON i.id = r.investment_id
    INNER JOIN public.profiles p ON p.user_id = r.user_id
    LEFT JOIN public.customers c ON c.user_id = r.user_id
    WHERE (
        v_search IS NULL
        OR COALESCE(r.agreement_id, '') ILIKE '%' || v_search || '%'
        OR COALESCE(i.code, '') ILIKE '%' || v_search || '%'
        OR p.full_name ILIKE '%' || v_search || '%'
        OR COALESCE(r.customer_id, c.customer_id, '') ILIKE '%' || v_search || '%'
        OR COALESCE(i.name, '') ILIKE '%' || v_search || '%'
      )
      AND CASE v_filter
        WHEN 'pending' THEN r.status = 'Pending'
        WHEN 'under_review' THEN FALSE
        WHEN 'approved' THEN r.status = 'Approved'
        WHEN 'rejected' THEN r.status = 'Rejected'
        ELSE TRUE
      END
  ),
  base AS (
    SELECT * FROM inv
    UNION ALL
    SELECT * FROM ren
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
    COALESCE((
      SELECT json_agg(json_build_object(
        'id', p.id,
        'kind', p.kind,
        'code', p.code,
        'request_id', p.request_id,
        'plan_name', p.plan_name,
        'fund_amount', p.fund_amount,
        'increment_amount', p.increment_amount,
        'mode', p.mode,
        'agreement_id', p.agreement_id,
        'status', p.status,
        'created_at', p.created_at,
        'customer_name', p.customer_name,
        'customer_id', p.customer_id
      ) ORDER BY p.created_at DESC)
      FROM paged p
    ), '[]'::JSON)
  INTO v_total, v_rows;

  RETURN json_build_object(
    'rows', v_rows,
    'total', COALESCE(v_total, 0),
    'limit', v_limit,
    'offset', v_offset
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Get renewal detail
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_agreement_renewal(p_id UUID)
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
    'id', r.id,
    'kind', 'renewal',
    'status', r.status,
    'mode', r.mode,
    'agreement_id', r.agreement_id,
    'customer_id', COALESCE(r.customer_id, c.customer_id),
    'customer_name', p.full_name,
    'current_amount', r.current_amount,
    'increment_amount', r.increment_amount,
    'new_principal', CASE
      WHEN r.mode = 'increase'
        THEN COALESCE(r.current_amount, 0) + COALESCE(r.increment_amount, 0)
      ELSE COALESCE(r.current_amount, i.fund_amount, 0)
    END,
    'created_at', r.created_at,
    'updated_at', r.updated_at,
    'user_id', r.user_id,
    'investment_id', i.id,
    'plan_no', i.code,
    'plan_name', i.name,
    'investment_status', i.status,
    'fund_amount', i.fund_amount,
    'interest_rate', i.interest_rate,
    'tds_percent', i.tds_percent,
    'payout_day', i.payout_day,
    'invested_date', i.invested_date,
    'bank', CASE
      WHEN ba.id IS NULL THEN NULL
      ELSE json_build_object(
        'bank_name', ba.bank_name,
        'account_number', ba.account_number,
        'ifsc_code', ba.ifsc_code
      )
    END
  )
  INTO v_result
  FROM public.agreement_renewal_requests r
  INNER JOIN public.investments i ON i.id = r.investment_id
  INNER JOIN public.profiles p ON p.user_id = r.user_id
  LEFT JOIN public.customers c ON c.user_id = r.user_id
  LEFT JOIN public.bank_accounts ba ON ba.id = i.bank_account_id
  WHERE r.id = p_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Renewal request not found.';
  END IF;

  RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- Decide renewal: approve | reject
-- Approve: accrue due interest, reset invested_date to today,
-- reset completed_interest_periods, optionally add increment to principal.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_decide_agreement_renewal(
  p_id UUID,
  p_action TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action TEXT := lower(trim(COALESCE(p_action, '')));
  v_req public.agreement_renewal_requests%ROWTYPE;
  v_inv public.investments%ROWTYPE;
  v_today DATE := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_new_principal NUMERIC(14, 2);
BEGIN
  IF v_action NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'Action must be approve or reject.';
  END IF;

  SELECT *
  INTO v_req
  FROM public.agreement_renewal_requests
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Renewal request not found.';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'Only Pending renewal requests can be decided.';
  END IF;

  IF v_action = 'reject' THEN
    UPDATE public.agreement_renewal_requests
    SET status = 'Rejected', updated_at = NOW()
    WHERE id = p_id
    RETURNING * INTO v_req;

    RETURN json_build_object(
      'id', v_req.id,
      'status', v_req.status,
      'mode', v_req.mode,
      'fund_amount', v_req.current_amount,
      'agreement_id', v_req.agreement_id,
      'action', 'reject'
    );
  END IF;

  SELECT *
  INTO v_inv
  FROM public.investments
  WHERE id = v_req.investment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Linked investment not found.';
  END IF;

  IF v_inv.status <> 'Active' THEN
    RAISE EXCEPTION 'Linked investment must be Active to renew.';
  END IF;

  -- Accrue any completed 30-day periods on the old principal first.
  PERFORM public.process_investment_interest(v_inv.id);

  SELECT * INTO v_inv
  FROM public.investments
  WHERE id = v_req.investment_id
  FOR UPDATE;

  IF v_req.mode = 'increase' THEN
    IF COALESCE(v_req.increment_amount, 0) <= 0 THEN
      RAISE EXCEPTION 'Increase renewal requires a positive increment amount.';
    END IF;
    v_new_principal := ROUND(COALESCE(v_inv.fund_amount, 0) + v_req.increment_amount, 2);
  ELSE
    v_new_principal := COALESCE(v_inv.fund_amount, v_req.current_amount);
  END IF;

  UPDATE public.investments
  SET
    fund_amount = v_new_principal,
    invested_date = v_today,
    completed_interest_periods = 0,
    current_value = v_new_principal + COALESCE(total_earnings, 0),
    updated_at = NOW()
  WHERE id = v_inv.id
    AND status = 'Active';

  UPDATE public.agreement_renewal_requests
  SET status = 'Approved', updated_at = NOW()
  WHERE id = p_id
  RETURNING * INTO v_req;

  RETURN json_build_object(
    'id', v_req.id,
    'status', v_req.status,
    'mode', v_req.mode,
    'fund_amount', v_new_principal,
    'increment_amount', v_req.increment_amount,
    'agreement_id', v_req.agreement_id,
    'invested_date', v_today,
    'action', 'approve'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_investment_requests(TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_get_agreement_renewal(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_decide_agreement_renewal(UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_investment_requests(TEXT, TEXT, INTEGER, INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_agreement_renewal(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_decide_agreement_renewal(UUID, TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
