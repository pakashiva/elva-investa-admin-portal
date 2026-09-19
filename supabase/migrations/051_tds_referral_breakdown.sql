-- TDS dashboard: expose referral TDS rows + KPI breakdown so cards match
-- interest filings + referral filings.
-- CREATE OR REPLACE only — no destructive operations.

CREATE OR REPLACE FUNCTION public.admin_get_tds_dashboard()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := public.admin_ist_today();
  v_fy_start DATE;
  v_fy_end DATE;
  v_month_start DATE;
  v_current_q INTEGER;
  v_fy_short TEXT;
  v_fy_long TEXT;
  v_total_interest NUMERIC(15, 2);
  v_total_referral NUMERIC(15, 2);
  v_month_interest NUMERIC(15, 2);
  v_month_referral NUMERIC(15, 2);
  v_fy_interest NUMERIC(15, 2);
  v_fy_referral NUMERIC(15, 2);
  v_rows JSON;
  v_referral_rows JSON;
  v_quarters JSON;
BEGIN
  v_fy_start := public.admin_india_fy_start(v_today);
  v_fy_end := (v_fy_start + INTERVAL '1 year')::DATE;
  v_month_start := date_trunc('month', v_today)::DATE;
  v_current_q := public.admin_india_fy_quarter(v_today);
  v_fy_short :=
    'FY' || to_char(v_fy_start, 'YY') || '-' || to_char(v_fy_end - 1, 'YY');
  v_fy_long :=
    'Financial Year ' || to_char(v_fy_start, 'YYYY') || '-' || to_char(v_fy_end - 1, 'YY');

  SELECT COALESCE(SUM(i.tds_deducted_amount), 0)
  INTO v_total_interest
  FROM public.investments i;

  SELECT COALESCE(SUM(r.tds_amount), 0)
  INTO v_total_referral
  FROM public.referral_rewards r;

  WITH periods AS (
    SELECT
      i.id,
      i.code,
      i.fund_amount,
      i.tds_percent,
      p.full_name,
      public.admin_monthly_interest(i.fund_amount, i.interest_rate) AS gross_interest,
      public.admin_monthly_tds(i.fund_amount, i.interest_rate, i.tds_percent) AS tds_amount,
      (i.invested_date + (period_no * 30)) AS period_end
    FROM public.investments i
    INNER JOIN public.profiles p ON p.user_id = i.user_id
    CROSS JOIN LATERAL generate_series(1, GREATEST(i.completed_interest_periods, 0)) AS period_no
    WHERE i.invested_date IS NOT NULL
      AND i.completed_interest_periods > 0
  ),
  referral_days AS (
    SELECT
      r.id,
      r.investment_id,
      r.referral_code,
      r.capital_amount,
      r.gross_bonus,
      r.tds_rate,
      r.tds_amount,
      r.net_bonus,
      r.status,
      ref.full_name AS referrer_name,
      cust.full_name AS referred_name,
      i.code AS investment_code,
      (r.created_at AT TIME ZONE 'Asia/Kolkata')::DATE AS credited_on
    FROM public.referral_rewards r
    LEFT JOIN public.profiles ref ON ref.user_id = r.referrer_user_id
    LEFT JOIN public.profiles cust ON cust.user_id = r.referred_user_id
    LEFT JOIN public.investments i ON i.id = r.investment_id
  )
  SELECT
    COALESCE((
      SELECT SUM(pr.tds_amount) FROM periods pr
      WHERE pr.period_end >= v_month_start AND pr.period_end <= v_today
    ), 0),
    COALESCE((
      SELECT SUM(rd.tds_amount) FROM referral_days rd
      WHERE rd.credited_on >= v_month_start AND rd.credited_on <= v_today
    ), 0),
    COALESCE((
      SELECT SUM(pr.tds_amount) FROM periods pr
      WHERE pr.period_end >= v_fy_start AND pr.period_end < v_fy_end AND pr.period_end <= v_today
    ), 0),
    COALESCE((
      SELECT SUM(rd.tds_amount) FROM referral_days rd
      WHERE rd.credited_on >= v_fy_start AND rd.credited_on < v_fy_end AND rd.credited_on <= v_today
    ), 0),
    COALESCE((
      SELECT json_agg(row_json ORDER BY quarter DESC, customer_name, investment_code)
      FROM (
        SELECT
          json_build_object(
            'investment_id', pr.id,
            'customer_name', pr.full_name,
            'investment_code', pr.code,
            'principal', pr.fund_amount,
            'gross_interest', SUM(pr.gross_interest),
            'tds_percent', pr.tds_percent,
            'tds_amount', SUM(pr.tds_amount),
            'quarter', public.admin_india_fy_quarter(pr.period_end),
            'period',
              'Q' || public.admin_india_fy_quarter(pr.period_end)::TEXT || ' ' || v_fy_short
          ) AS row_json,
          public.admin_india_fy_quarter(pr.period_end) AS quarter,
          pr.full_name AS customer_name,
          pr.code AS investment_code
        FROM periods pr
        WHERE pr.period_end >= v_fy_start
          AND pr.period_end < v_fy_end
          AND pr.period_end <= v_today
        GROUP BY
          pr.id,
          pr.full_name,
          pr.code,
          pr.fund_amount,
          pr.tds_percent,
          public.admin_india_fy_quarter(pr.period_end)
      ) filings
    ), '[]'::JSON),
    COALESCE((
      SELECT json_agg(row_json ORDER BY credited_on DESC, referrer_name)
      FROM (
        SELECT
          json_build_object(
            'id', rd.id,
            'referrer_name', COALESCE(rd.referrer_name, '—'),
            'referred_name', COALESCE(rd.referred_name, '—'),
            'investment_id', rd.investment_id,
            'investment_code', COALESCE(rd.investment_code, '—'),
            'referral_code', COALESCE(rd.referral_code, '—'),
            'capital_amount', rd.capital_amount,
            'gross_bonus', rd.gross_bonus,
            'tds_rate', rd.tds_rate,
            'tds_amount', rd.tds_amount,
            'net_bonus', rd.net_bonus,
            'status', rd.status,
            'credited_on', rd.credited_on,
            'quarter', public.admin_india_fy_quarter(rd.credited_on),
            'period',
              'Q' || public.admin_india_fy_quarter(rd.credited_on)::TEXT || ' ' || v_fy_short
          ) AS row_json,
          rd.credited_on,
          rd.referrer_name
        FROM referral_days rd
        WHERE rd.credited_on >= v_fy_start
          AND rd.credited_on < v_fy_end
          AND rd.credited_on <= v_today
      ) referral_filings
    ), '[]'::JSON),
    COALESCE((
      SELECT json_agg(q_json ORDER BY quarter)
      FROM (
        SELECT
          q.quarter,
          json_build_object(
            'quarter', q.quarter,
            'label', 'Q' || q.quarter::TEXT || ' Deductions',
            'amount', COALESCE(sums.amount, 0),
            'isCurrent', q.quarter = v_current_q
          ) AS q_json
        FROM generate_series(1, v_current_q) AS q(quarter)
        LEFT JOIN (
          SELECT quarter, SUM(amount) AS amount
          FROM (
            SELECT
              public.admin_india_fy_quarter(pr.period_end) AS quarter,
              SUM(pr.tds_amount) AS amount
            FROM periods pr
            WHERE pr.period_end >= v_fy_start
              AND pr.period_end < v_fy_end
              AND pr.period_end <= v_today
            GROUP BY 1
            UNION ALL
            SELECT
              public.admin_india_fy_quarter(rd.credited_on) AS quarter,
              SUM(rd.tds_amount) AS amount
            FROM referral_days rd
            WHERE rd.credited_on >= v_fy_start
              AND rd.credited_on < v_fy_end
              AND rd.credited_on <= v_today
            GROUP BY 1
          ) combined
          GROUP BY quarter
        ) sums ON sums.quarter = q.quarter
      ) quarter_rows
    ), '[]'::JSON)
  INTO
    v_month_interest,
    v_month_referral,
    v_fy_interest,
    v_fy_referral,
    v_rows,
    v_referral_rows,
    v_quarters;

  RETURN json_build_object(
    'kpis', json_build_object(
      'totalTds', v_total_interest + v_total_referral,
      'totalInterestTds', v_total_interest,
      'totalReferralTds', v_total_referral,
      'currentMonthTds', v_month_interest + v_month_referral,
      'monthInterestTds', v_month_interest,
      'monthReferralTds', v_month_referral,
      'currentFyTds', v_fy_interest + v_fy_referral,
      'fyInterestTds', v_fy_interest,
      'fyReferralTds', v_fy_referral,
      'fyLabel', v_fy_long,
      'fyShort', v_fy_short
    ),
    'rows', v_rows,
    'referral_rows', v_referral_rows,
    'quarters', v_quarters
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_tds_dashboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_tds_dashboard() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
