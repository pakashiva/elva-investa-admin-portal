-- Report columns: File TDS (boolean). When it is false, interest TDS rate and
-- TDS amount columns are 0. File TDS follows investments.tds_percent > 0
-- (the approval-screen checkbox). Referral commission TDS is unchanged.

CREATE OR REPLACE FUNCTION public.admin_report_sheet_investments(p_from DATE, p_to DATE)
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(json_agg(row_obj ORDER BY created_at DESC), '[]'::JSON)
  FROM (
    SELECT
      json_build_object(
        'Customer Name', p.full_name,
        'Investment ID', i.code,
        'Plan', i.name,
        'Status', i.status,
        'Principal', i.fund_amount,
        'Current Value', COALESCE(i.current_value, i.fund_amount + COALESCE(i.total_earnings, 0)),
        'Net Earnings', COALESCE(i.total_earnings, 0),
        'File TDS', (COALESCE(i.tds_percent, 0) > 0),
        'TDS %', CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END,
        'TDS Deducted', CASE
          WHEN COALESCE(i.tds_percent, 0) > 0 THEN COALESCE(i.tds_deducted_amount, 0)
          ELSE 0
        END,
        'Interest Rate', i.interest_rate,
        'Invested Date', i.invested_date,
        'Created', (i.created_at AT TIME ZONE 'Asia/Kolkata')::DATE
      ) AS row_obj,
      i.created_at
    FROM public.investments i
    INNER JOIN public.profiles p ON p.user_id = i.user_id
    WHERE (i.created_at AT TIME ZONE 'Asia/Kolkata')::DATE <= p_to
    LIMIT 2000
  ) src;
$$;

CREATE OR REPLACE FUNCTION public.admin_report_sheet_interest(p_from DATE, p_to DATE)
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(json_agg(row_obj ORDER BY period_end DESC, customer_name), '[]'::JSON)
  FROM (
    SELECT
      json_build_object(
        'Customer Name', p.full_name,
        'Investment ID', i.code,
        'Principal', i.fund_amount,
        'Rate', i.interest_rate,
        'Period End', (i.invested_date + (period_no * 30)),
        'Gross Interest', public.admin_monthly_interest(i.fund_amount, i.interest_rate),
        'File TDS', (COALESCE(i.tds_percent, 0) > 0),
        'TDS %', CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END,
        'TDS', public.admin_monthly_tds(
          i.fund_amount,
          i.interest_rate,
          CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END
        ),
        'Net Interest', public.admin_monthly_net(
          i.fund_amount,
          i.interest_rate,
          CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END
        )
      ) AS row_obj,
      (i.invested_date + (period_no * 30)) AS period_end,
      p.full_name AS customer_name
    FROM public.investments i
    INNER JOIN public.profiles p ON p.user_id = i.user_id
    CROSS JOIN LATERAL generate_series(1, GREATEST(i.completed_interest_periods, 0)) AS period_no
    WHERE i.invested_date IS NOT NULL
      AND i.completed_interest_periods > 0
      AND (i.invested_date + (period_no * 30)) BETWEEN p_from AND p_to
    LIMIT 2000
  ) src;
$$;

CREATE OR REPLACE FUNCTION public.admin_report_sheet_tds(p_from DATE, p_to DATE)
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(json_agg(row_obj ORDER BY period_end DESC), '[]'::JSON)
  FROM (
    SELECT
      json_build_object(
        'Customer Name', p.full_name,
        'Investment ID', i.code,
        'Principal', i.fund_amount,
        'Gross Interest', public.admin_monthly_interest(i.fund_amount, i.interest_rate),
        'File TDS', (COALESCE(i.tds_percent, 0) > 0),
        'TDS Rate', CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END,
        'TDS Amount', public.admin_monthly_tds(
          i.fund_amount,
          i.interest_rate,
          CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END
        ),
        'Period End', (i.invested_date + (period_no * 30))
      ) AS row_obj,
      (i.invested_date + (period_no * 30)) AS period_end
    FROM public.investments i
    INNER JOIN public.profiles p ON p.user_id = i.user_id
    CROSS JOIN LATERAL generate_series(1, GREATEST(i.completed_interest_periods, 0)) AS period_no
    WHERE i.invested_date IS NOT NULL
      AND i.completed_interest_periods > 0
      AND (i.invested_date + (period_no * 30)) BETWEEN p_from AND p_to
    LIMIT 2000
  ) src;
$$;

CREATE OR REPLACE FUNCTION public.admin_report_sheet_payouts(
  p_from DATE,
  p_to DATE
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from DATE := COALESCE(p_from, public.admin_ist_today());
  v_to DATE := COALESCE(p_to, public.admin_ist_today() + 31);
BEGIN
  IF v_from > v_to THEN
    RAISE EXCEPTION 'Start date must be on or before end date.';
  END IF;

  RETURN COALESCE((
    SELECT json_agg(row_json ORDER BY payout_date ASC, customer_name ASC, plan_no ASC)
    FROM (
      SELECT
        json_build_object(
          'Payout Date', d.payout_date,
          'Payout Day', COALESCE(i.payout_day, 10),
          'Customer Name', p.full_name,
          'Customer ID', c.customer_id,
          'Mobile', p.mobile_number,
          'Email', p.email_address,
          'PAN', k.pan_number,
          'Plan No', i.code,
          'Plan Name', i.name,
          'Investment Status', i.status,
          'Principal', i.fund_amount,
          'Interest Rate', i.interest_rate,
          'File TDS', (COALESCE(i.tds_percent, 0) > 0),
          'Interest TDS %', CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END,
          'Gross Interest', public.admin_monthly_interest(i.fund_amount, i.interest_rate),
          'Interest TDS', public.admin_monthly_tds(
            i.fund_amount,
            i.interest_rate,
            CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END
          ),
          'Net Interest Payable', public.admin_monthly_net(
            i.fund_amount,
            i.interest_rate,
            CASE WHEN COALESCE(i.tds_percent, 0) > 0 THEN i.tds_percent ELSE 0 END
          ),
          'Invested Date', i.invested_date,
          'Account Holder', COALESCE(to_jsonb(ba)->>'account_holder_name', p.full_name),
          'Bank Name', ba.bank_name,
          'Account Number', ba.account_number,
          'IFSC', ba.ifsc_code,
          'Branch', COALESCE(to_jsonb(ba)->>'branch_name', ''),
          'Account Type', ba.account_type,
          'Referrer Name', CASE WHEN rr.id IS NOT NULL THEN ref.full_name END,
          'Referral Code', CASE WHEN rr.id IS NOT NULL THEN COALESCE(rr.referral_code, i.referral_code) END,
          'Referral Rate', rr.referral_rate,
          'Referral Gross Commission', rr.gross_bonus,
          'Referral TDS Rate', rr.tds_rate,
          'Referral TDS', rr.tds_amount,
          'Referral Net Payout', rr.net_bonus,
          'Referral Status', rr.status
        ) AS row_json,
        d.payout_date,
        p.full_name AS customer_name,
        i.code AS plan_no
      FROM public.investments i
      INNER JOIN public.profiles p ON p.user_id = i.user_id
      LEFT JOIN public.customers c ON c.user_id = i.user_id
      LEFT JOIN public.kyc_documents k ON k.user_id = i.user_id
      LEFT JOIN public.bank_accounts ba ON ba.id = i.bank_account_id
      LEFT JOIN public.referral_rewards rr
        ON rr.investment_id = i.id
       AND rr.status = 'Pending'
      LEFT JOIN public.profiles ref ON ref.user_id = COALESCE(rr.referrer_user_id, i.referrer_user_id)
      CROSS JOIN LATERAL (
        SELECT make_date(
          EXTRACT(YEAR FROM month_start)::INT,
          EXTRACT(MONTH FROM month_start)::INT,
          COALESCE(i.payout_day, 10)
        ) AS payout_date
        FROM generate_series(
          date_trunc('month', v_from)::DATE,
          date_trunc('month', v_to)::DATE,
          INTERVAL '1 month'
        ) AS month_start
      ) d
      WHERE i.status = 'Active'
        AND i.invested_date IS NOT NULL
        AND COALESCE(i.payout_day, 10) = ANY (ARRAY[1, 5, 10, 15, 20, 25])
        AND d.payout_date BETWEEN v_from AND v_to
        AND d.payout_date >= i.invested_date
    ) q
  ), '[]'::JSON);
END;
$$;

NOTIFY pgrst, 'reload schema';
