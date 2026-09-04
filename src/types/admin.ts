export type AdminRole = 'super_admin' | 'operator';

export type AdminMe = {
  user_id: string;
  role: AdminRole;
  full_name: string;
  email: string | null;
};

export type DashboardKpis = {
  totalWealthManaged: number;
  totalInvested: number;
  activeInvestments: number;
  activeInvestmentsThisWeek: number;
  interestPaidYtd: number;
  tdsDeductedYtd: number;
  totalWithdrawals: number;
  verifiedCustomers: number;
  newRegistrationsThisWeek: number;
  pendingRequests: number;
  pendingInvestments: number;
  pendingWithdrawals: number;
};

export type WealthPoint = {
  month: string;
  label: string;
  wealth: number;
};

export type FlowPoint = {
  month: string;
  label: string;
  inflow: number;
  outflow: number;
};

export type DashboardData = {
  kpis: DashboardKpis;
  wealthSeries: WealthPoint[];
  flowSeries: FlowPoint[];
};

export type ChartRangeMonths = 3 | 6 | 12;

export type CustomerFilter =
  | 'all'
  | 'active'
  | 'inactive'
  | 'with_investments'
  | 'no_investment';

export type CustomerSort = 'joined_desc' | 'joined_asc';

export type CustomerListRow = {
  user_id: string;
  customer_id: string | null;
  full_name: string;
  mobile_number: string;
  email_address: string;
  pan_number: string | null;
  active_investments: number;
  pending_investments: number;
  closed_investments: number;
  total_investments: number;
  total_invested: number;
  joined_at: string;
};

export type CustomerListResult = {
  rows: CustomerListRow[];
  total: number;
  limit: number;
  offset: number;
};

export type CustomerListParams = {
  filter: CustomerFilter;
  search: string;
  joinFrom: string | null;
  joinTo: string | null;
  sort: CustomerSort;
  page: number;
  pageSize: number;
};

export type CustomerProfile = {
  user_id: string;
  customer_id: string | null;
  full_name: string;
  mobile_number: string;
  email_address: string;
  date_of_birth: string;
  address: string;
  city: string;
  state: string;
  pin_code: string;
  pan_number: string | null;
};

export type CustomerBankAccount = {
  id: string;
  bank_name: string;
  account_number: string;
  ifsc_code: string;
  account_type: string;
  is_primary: boolean;
  verified: boolean;
};

export type CustomerLedgerStatus = 'Completed' | 'Pending';
export type CustomerLedgerType = 'instant_credit' | 'withdrawal' | 'referral_bonus';

export type CustomerLedgerRow = {
  id: string;
  occurred_on: string;
  transaction_type: CustomerLedgerType;
  amount: number;
  status: CustomerLedgerStatus;
};

export type CustomerDetails = {
  profile: CustomerProfile;
  kyc_verified: boolean;
  account_active: boolean;
  summary: {
    total_invested: number;
    active_plans: number;
    returns_earned: number;
  };
  banks: CustomerBankAccount[];
  transactions: CustomerLedgerRow[];
};

export type CustomerDetailsTab = 'profile' | 'banks' | 'transactions';

export type InvestmentRequestFilter =
  | 'all'
  | 'pending'
  | 'under_review'
  | 'approved'
  | 'rejected';

export type InvestmentRequestStatus =
  | 'Pending'
  | 'Under Review'
  | 'Active'
  | 'Closed'
  | 'Rejected';

export type InvestmentRequestListRow = {
  id: string;
  request_id: string | null;
  customer_name: string;
  customer_id: string | null;
  plan_name: string;
  fund_amount: number;
  status: InvestmentRequestStatus;
  created_at: string;
};

export type InvestmentRequestListResult = {
  rows: InvestmentRequestListRow[];
  total: number;
  limit: number;
  offset: number;
};

export type InvestmentRequestDetail = {
  id: string;
  request_id: string | null;
  status: InvestmentRequestStatus;
  plan_name: string;
  fund_amount: number;
  interest_rate: number;
  tds_percent: number;
  created_at: string;
  user_id: string;
  customer_name: string;
  customer_id: string | null;
  kyc_verified: boolean;
  active_portfolio: number;
  active_plans: number;
  bank: {
    bank_name: string;
    account_number: string;
    ifsc_code: string;
    verified: boolean;
  } | null;
};

export type InvestmentDecision = 'approve' | 'hold' | 'reject';

export type WithdrawalFilter = 'pending' | 'approved' | 'rejected';

export type WithdrawalStatus =
  | 'Processing'
  | 'On Hold'
  | 'Approved'
  | 'Paid'
  | 'Rejected';

export type WithdrawalListRow = {
  id: string;
  status: WithdrawalStatus;
  strategy: 'full' | 'partial';
  customer_name: string;
  investment_code: string;
  plan_name: string;
  available_principal: number;
  withdrawal_amount: number;
  tds_amount: number;
  tds_percent: number;
  net_payout: number;
  bank_name: string | null;
  account_number: string | null;
  requested_on: string;
  updated_at: string;
  agreement_ok: boolean;
};

export type WithdrawalListResult = {
  rows: WithdrawalListRow[];
  total: number;
  limit: number;
  offset: number;
};

export type WithdrawalDecision = InvestmentDecision;

export type TdsFilingRow = {
  investment_id: string;
  customer_name: string;
  investment_code: string;
  principal: number;
  gross_interest: number;
  tds_percent: number;
  tds_amount: number;
  quarter: number;
  period: string;
};

export type TdsQuarterSlice = {
  quarter: number;
  label: string;
  amount: number;
  isCurrent: boolean;
};

export type TdsDashboardData = {
  kpis: {
    totalTds: number;
    currentMonthTds: number;
    currentFyTds: number;
    fyLabel: string;
    fyShort: string;
  };
  rows: TdsFilingRow[];
  quarters: TdsQuarterSlice[];
};

export type ReferralPayoutStatus = 'Pending' | 'Paid';

export type ReferralListRow = {
  id: string;
  status: ReferralPayoutStatus;
  referrer_user_id: string;
  referred_user_id: string;
  referrer_name: string;
  referred_name: string;
  investment_id: string;
  investment_code: string | null;
  referral_code: string;
  capital_amount: number;
  referral_rate: number;
  gross_bonus: number;
  tds_rate: number;
  tds_amount: number;
  net_bonus: number;
  lifetime_paid_net: number;
  created_at: string;
};

export type ReferralsPageData = {
  settings: {
    referral_rate: number;
    tds_rate: number;
  };
  kpis: {
    totalReferrals: number;
    grossCommission: number;
    tdsAmount: number;
    netCommission: number;
  };
  rows: ReferralListRow[];
  total: number;
  limit: number;
  offset: number;
};

export type ReportKind =
  | 'investment'
  | 'interest'
  | 'withdrawal'
  | 'tds'
  | 'referral'
  | 'wealth'
  | 'bulk';

export type ReportFormat = 'xlsx' | 'csv' | 'pdf';

export type ReportDatePreset = 'last_7' | 'last_30' | 'last_90' | 'this_fy' | 'inception';

export type ReportSheet = {
  name: string;
  rows: Record<string, unknown>[];
};

export type BuiltReport = {
  name: string;
  type: string;
  sheets: ReportSheet[];
};

export type GeneratedReportRow = {
  id: string;
  report_name: string;
  report_type: string;
  date_range_label: string;
  generated_by: string;
  generated_date: string;
  format: ReportFormat;
  created_at: string;
};

export type NotificationKind = 'investment' | 'withdrawal' | 'customer';

export type NotificationFilter = 'all' | 'unread' | NotificationKind;

export type AdminNotification = {
  key: string;
  kind: NotificationKind;
  customer_name: string;
  amount: number | null;
  plan_name: string | null;
  occurred_at: string;
  href: string;
  unread: boolean;
};


