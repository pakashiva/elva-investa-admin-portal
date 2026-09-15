-- Upcoming / ranged payout reports for Active investments.
-- Uses investments.payout_day (1/5/10/15/20/25). Includes every calendar
-- payout date that falls inside [p_from, p_to]. No destructive changes.

-- ---------------------------------------------------------------------------
-- Next calendar payout date on/after p_from for a given payout_day
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_next_payout_date(
  p_from DATE,
  p_payout_day INTEGER
)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_day INTEGER := COALESCE(p_payout_day, 10);
  v_from DATE := COALESCE(p_from, CURRENT_DATE);
  v_year INTEGER;
  v_month INTEGER;
BEGIN
  IF NOT (v_day = ANY (ARRAY[1, 5, 10, 15, 20, 25])) THEN
    v_day := 10;
  END IF;

  v_year := EXTRACT(YEAR FROM v_from)::INT;
  v_month := EXTRACT(MONTH FROM v_from)::INT;

  IF EXTRACT(DAY FROM v_from)::INT <= v_day THEN
    RETURN make_date(v_year, v_month, v_day);
  END IF;

  v_month := v_month + 1;
  IF v_month > 12 THEN
    v_month := 1;
    v_year := v_year + 1;
  END IF;
  RETURN make_date(v_year, v_month, v_day);
END;
$$;

-- ---------------------------------------------------------------------------
-- Shared payout sheet (interest due by payout_day + referral columns)
-- One row per Active investment per payout date inside the range.
-- ---------------------------------------------------------------------------
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
          'Interest TDS %', i.tds_percent,
          'Gross Interest', public.admin_monthly_interest(i.fund_amount, i.interest_rate),
          'Interest TDS', public.admin_monthly_tds(i.fund_amount, i.interest_rate, i.tds_percent),
          'Net Interest Payable', public.admin_monthly_net(i.fund_amount, i.interest_rate, i.tds_percent),
          'Invested Date', i.invested_date,
          'Account Holder', COALESCE(to_jsonb(ba)->>'account_holder_name', p.full_name),
          'Bank Name', ba.bank_name,
          'Account Number', ba.account_number,
          'IFSC', ba.ifsc_code,
          'Branch', COALESCE(to_jsonb(ba)->>'branch_name', ''),
          'Account Type', ba.account_type,
          -- Referral amounts only when reward is still Pending (not yet paid).
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

-- ---------------------------------------------------------------------------
-- Extend admin_build_report with upcoming_payout + payout_range
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_build_report(
  p_kind TEXT,
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
  v_kind TEXT := lower(trim(COALESCE(p_kind, '')));
  v_from DATE := COALESCE(p_from, DATE '2000-01-01');
  v_to DATE := COALESCE(p_to, public.admin_ist_today());
  v_name TEXT;
  v_type TEXT;
  v_sheets JSON;
BEGIN
  IF v_from > v_to THEN
    RAISE EXCEPTION 'Start date must be on or before end date.';
  END IF;

  IF v_kind = 'investment' THEN
    v_name := 'Investment Master Ledger';
    v_type := 'Investment';
    v_sheets := json_build_array(json_build_object(
      'name', 'Investments',
      'rows', public.admin_report_sheet_investments(v_from, v_to)
    ));
  ELSIF v_kind = 'interest' THEN
    v_name := 'Interest Accrual Report';
    v_type := 'Interest';
    v_sheets := json_build_array(json_build_object(
      'name', 'Interest',
      'rows', public.admin_report_sheet_interest(v_from, v_to)
    ));
  ELSIF v_kind = 'withdrawal' THEN
    v_name := 'Withdrawal Status Report';
    v_type := 'Withdrawal';
    v_sheets := json_build_array(json_build_object(
      'name', 'Withdrawals',
      'rows', public.admin_report_sheet_withdrawals(v_from, v_to)
    ));
  ELSIF v_kind = 'tds' THEN
    v_name := 'TDS Deduction Ledger';
    v_type := 'TDS';
    v_sheets := json_build_array(json_build_object(
      'name', 'TDS',
      'rows', public.admin_report_sheet_tds(v_from, v_to)
    ));
  ELSIF v_kind = 'referral' THEN
    v_name := 'Referral Commission Report';
    v_type := 'Referral';
    v_sheets := json_build_array(json_build_object(
      'name', 'Referrals',
      'rows', public.admin_report_sheet_referrals(v_from, v_to)
    ));
  ELSIF v_kind = 'wealth' THEN
    v_name := 'AUM and Portfolio Health';
    v_type := 'Wealth';
    v_sheets := json_build_array(json_build_object(
      'name', 'Wealth',
      'rows', public.admin_report_sheet_wealth(v_from, v_to)
    ));
  ELSIF v_kind = 'upcoming_payout' THEN
    v_name := 'Upcoming Payout Report (Next 31 Days)';
    v_type := 'Upcoming Payout';
    v_sheets := json_build_array(json_build_object(
      'name', 'Payouts',
      'rows', public.admin_report_sheet_payouts(v_from, v_to)
    ));
  ELSIF v_kind = 'payout_range' THEN
    v_name := 'Payout Report (Date Range)';
    v_type := 'Payout Range';
    v_sheets := json_build_array(json_build_object(
      'name', 'Payouts',
      'rows', public.admin_report_sheet_payouts(v_from, v_to)
    ));
  ELSIF v_kind = 'bulk' THEN
    v_name := 'Bulk Audit Export';
    v_type := 'Bulk';
    v_sheets := json_build_array(
      json_build_object('name', 'Investments', 'rows', public.admin_report_sheet_investments(v_from, v_to)),
      json_build_object('name', 'Interest', 'rows', public.admin_report_sheet_interest(v_from, v_to)),
      json_build_object('name', 'Withdrawals', 'rows', public.admin_report_sheet_withdrawals(v_from, v_to)),
      json_build_object('name', 'TDS', 'rows', public.admin_report_sheet_tds(v_from, v_to)),
      json_build_object('name', 'Referrals', 'rows', public.admin_report_sheet_referrals(v_from, v_to)),
      json_build_object('name', 'Wealth', 'rows', public.admin_report_sheet_wealth(v_from, v_to)),
      json_build_object('name', 'Payouts', 'rows', public.admin_report_sheet_payouts(v_from, v_to))
    );
  ELSE
    RAISE EXCEPTION 'Unknown report type.';
  END IF;

  RETURN json_build_object(
    'name', v_name,
    'type', v_type,
    'sheets', v_sheets
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_next_payout_date(DATE, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_report_sheet_payouts(DATE, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_build_report(TEXT, DATE, DATE) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_next_payout_date(DATE, INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_build_report(TEXT, DATE, DATE) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
