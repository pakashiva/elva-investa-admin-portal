import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useOutletContext, useParams } from 'react-router-dom';
import { AppHeader } from '../components/AppHeader';
import { DecisionResultModal } from '../components/DecisionResultModal';
import { ErrorBanner } from '../components/States';
import type { AdminOutletContext } from '../layouts/AdminLayout';
import {
  decideInvestment,
  getInvestmentRequest,
  updateInvestmentTerms,
} from '../services/investmentRequestService';
import type {
  InvestmentDecision,
  InvestmentRequestDetail,
} from '../types/admin';
import {
  displayCustomerId,
  displayRequestId,
  formatInr,
  formatPercent,
  last4Account,
} from '../utils/format';

const RATE_OPTIONS = [0.04, 0.05, 0.06, 0.07, 0.08];
const PAYOUT_DAYS = [1, 5, 10, 15, 20, 25];

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

export function InvestmentReviewPage() {
  const { onOpenMenu } = useOutletContext<AdminOutletContext>();
  const { requestId } = useParams();
  const navigate = useNavigate();
  const [detail, setDetail] = useState<InvestmentRequestDetail | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [decision, setDecision] = useState<InvestmentDecision | null>(null);

  const load = async () => {
    if (!requestId) {
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setDetail(await getInvestmentRequest(requestId));
    } catch (err) {
      setDetail(null);
      setError(err instanceof Error ? err.message : 'Failed to load request');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, [requestId]);

  const editable = detail?.status === 'Pending' || detail?.status === 'Under Review';
  const payoutDay = detail?.payout_day ?? 10;

  const preview = useMemo(() => {
    const principal = detail?.fund_amount ?? 0;
    const rate = detail?.interest_rate ?? 0.05;
    const tds = detail?.tds_percent ?? 0.1;
    const gross = roundMoney(principal * rate);
    const tax = roundMoney(gross * tds);
    const net = roundMoney(gross - tax);
    return { principal, gross, tax, net, maturity: roundMoney(principal + net) };
  }, [detail]);

  async function persistTerms(rate: number, tds: number, day: number) {
    if (!detail || !editable) {
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await updateInvestmentTerms(detail.id, rate, tds, day);
      setDetail({ ...detail, interest_rate: rate, tds_percent: tds, payout_day: day });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save terms');
    } finally {
      setSaving(false);
    }
  }

  async function onDecide(action: InvestmentDecision) {
    if (!detail || !editable) {
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const result = await decideInvestment(detail.id, action);
      setDetail({ ...detail, status: result.status });
      setDecision(action);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not update request');
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <AppHeader
        title="Investment Approval Console"
        subtitle={`Awaiting decision for ${displayRequestId(detail?.request_id)}.`}
        showSearch
        onOpenMenu={onOpenMenu}
      />

      {error ? <ErrorBanner message={error} onRetry={() => void load()} /> : null}

      {isLoading || !detail ? (
        <div className="card state-box">{isLoading ? 'Loading request…' : 'Request not found'}</div>
      ) : (
        <div className="review-grid">
          <div className="review-col">
            <article className="card review-card">
              <h3>Customer Information</h3>
              <div className="review-customer">
                <img className="avatar" src="/avatar.png" alt="" />
                <div>
                  <strong>{detail.customer_name}</strong>
                  <p>Customer ID: {displayCustomerId(detail.customer_id)}</p>
                </div>
              </div>
              <div className="detail-grid">
                <div className="detail-field">
                  <span>TOTAL ACTIVE PORTFOLIO</span>
                  <strong>{formatInr(detail.active_portfolio)}</strong>
                </div>
                <div className="detail-field">
                  <span>ACTIVE SCHEMES</span>
                  <strong>{detail.active_plans} active plans</strong>
                </div>
              </div>
            </article>

            <article className="card review-card">
              <h3>Request Parameters</h3>
              <div className="detail-grid">
                <div className="detail-field">
                  <span>PROPOSED PLAN</span>
                  <strong>
                    {detail.plan_name} ({formatPercent(detail.interest_rate)} p.m.)
                  </strong>
                </div>
                <div className="detail-field">
                  <span>FUNDING AMOUNT</span>
                  <strong>{formatInr(detail.fund_amount)}</strong>
                </div>
              </div>
              <div className="linked-bank">
                <span>LINKED BANK ACCOUNT</span>
                {detail.bank ? (
                  <>
                    <strong>
                      {detail.bank.bank_name} (Acct ending **{last4Account(detail.bank.account_number)})
                    </strong>
                    <p>IFSC: {detail.bank.ifsc_code}</p>
                  </>
                ) : (
                  <p>No bank account linked.</p>
                )}
              </div>
            </article>
          </div>

          <article className="card review-card">
            <h3>Plan Validation Configuration</h3>

            <label className="toggle-row">
              <span>
                <strong>TDS Deduction Policy</strong>
                <p>Automate statutory 10% lock-in</p>
              </span>
              <input
                type="checkbox"
                checked={detail.tds_percent > 0}
                disabled={!editable || saving}
                onChange={(event) =>
                  void persistTerms(detail.interest_rate, event.target.checked ? 0.1 : 0, payoutDay)
                }
              />
            </label>

            <label className="config-field">
              Assign Interest Yield (p.m.)
              <select
                className="select"
                value={detail.interest_rate}
                disabled={!editable || saving}
                onChange={(event) =>
                  void persistTerms(Number(event.target.value), detail.tds_percent, payoutDay)
                }
              >
                {RATE_OPTIONS.map((rate) => (
                  <option key={rate} value={rate}>
                    {formatPercent(rate)} p.m.
                    {rate === 0.05 ? ' (Standard Rate)' : ''}
                  </option>
                ))}
              </select>
            </label>

            <div className="config-field">
              Monthly Payout Cycle
              <div className="payout-days">
                {PAYOUT_DAYS.map((day) => (
                  <button
                    key={day}
                    type="button"
                    className={payoutDay === day ? 'active' : ''}
                    disabled={!editable || saving}
                    onClick={() => void persistTerms(detail.interest_rate, detail.tds_percent, day)}
                  >
                    {day === 1 ? '1st' : `${day}th`}
                  </button>
                ))}
              </div>
            </div>

            <div className="accrual-preview">
              <h4>Interest Accrual Summary Preview</h4>
              <p>Uses the live monthly interest formula (not annual).</p>
              <ul>
                <li>
                  <span>Principal</span>
                  <strong>{formatInr(preview.principal)}</strong>
                </li>
                <li>
                  <span>Gross yield (monthly)</span>
                  <strong>{formatInr(preview.gross)}</strong>
                </li>
                <li>
                  <span>TDS {formatPercent(detail.tds_percent)} deduction</span>
                  <strong className="debit">-{formatInr(preview.tax)}</strong>
                </li>
                <li>
                  <span>Net monthly yield</span>
                  <strong className="credit">{formatInr(preview.net)}</strong>
                </li>
                <li>
                  <span>Estimated value after 1 period</span>
                  <strong>{formatInr(preview.maturity)}</strong>
                </li>
              </ul>
            </div>

            {editable ? (
              <div className="decision-actions">
                <button
                  type="button"
                  className="approve-btn"
                  disabled={saving}
                  onClick={() => void onDecide('approve')}
                >
                  Approve Investment
                </button>
                <button
                  type="button"
                  className="hold-btn"
                  disabled={saving}
                  onClick={() => void onDecide('hold')}
                >
                  Hold Request
                </button>
                <button
                  type="button"
                  className="reject-btn"
                  disabled={saving}
                  onClick={() => void onDecide('reject')}
                >
                  Reject Request
                </button>
              </div>
            ) : (
              <p className="muted">This request is already {requestStatusLabelSafe(detail.status)}.</p>
            )}
          </article>
        </div>
      )}

      {decision && detail ? (
        <DecisionResultModal
          action={decision}
          requestId={detail.request_id}
          amount={detail.fund_amount}
          onClose={() => navigate('/investment-requests')}
        />
      ) : null}
    </>
  );
}

function requestStatusLabelSafe(status: string): string {
  if (status === 'Active' || status === 'Closed') return 'approved';
  return status.toLowerCase();
}
