import { Calculator, CalendarDays, FilePenLine } from 'lucide-react';
import type { ReactNode } from 'react';
import { useOutletContext } from 'react-router-dom';
import { AppHeader } from '../components/AppHeader';
import { ErrorBanner } from '../components/States';
import { TdsQuarterChart } from '../components/TdsQuarterChart';
import { useTdsDashboard } from '../hooks/useTdsDashboard';
import type { AdminOutletContext } from '../layouts/AdminLayout';
import { formatDate, formatInr, formatTdsRate } from '../utils/format';

function TdsKpi({
  label,
  value,
  subtext,
  icon,
  tone,
}: {
  label: string;
  value: string;
  subtext: string;
  icon: ReactNode;
  tone: 'orange' | 'green' | 'purple';
}) {
  return (
    <article className="card tds-kpi">
      <div className={`tds-kpi-icon ${tone}`}>{icon}</div>
      <p className="kpi-label">{label}</p>
      <p className="kpi-value">{value}</p>
      <p className="kpi-sub">{subtext}</p>
    </article>
  );
}

function breakdownLine(interest: number, referral: number): string {
  return `Interest ${formatInr(interest)} + Referral ${formatInr(referral)}`;
}

export function TdsPage() {
  const { onOpenMenu } = useOutletContext<AdminOutletContext>();
  const { data, isLoading, error, reload } = useTdsDashboard();

  const interestFyTotal =
    data?.rows.reduce((sum, row) => sum + row.tds_amount, 0) ?? 0;
  const referralFyTotal =
    data?.referralRows.reduce((sum, row) => sum + row.tds_amount, 0) ?? 0;

  return (
    <>
      <AppHeader
        title="TDS Dashboard"
        subtitle="Track tax deductions at source and manage Quarterly Form 16A filings."
        onOpenMenu={onOpenMenu}
      />

      {error ? <ErrorBanner message={error} onRetry={() => void reload()} /> : null}

      <section className="tds-kpi-grid">
        {isLoading || !data ? (
          <>
            <article className="card tds-kpi">
              <p className="kpi-label">Loading</p>
              <p className="kpi-value">—</p>
              <p className="kpi-sub">Fetching live data</p>
            </article>
            <article className="card tds-kpi">
              <p className="kpi-label">Loading</p>
              <p className="kpi-value">—</p>
              <p className="kpi-sub">Fetching live data</p>
            </article>
            <article className="card tds-kpi">
              <p className="kpi-label">Loading</p>
              <p className="kpi-value">—</p>
              <p className="kpi-sub">Fetching live data</p>
            </article>
          </>
        ) : (
          <>
            <TdsKpi
              label="TOTAL TDS DEDUCTED"
              value={formatInr(data.kpis.totalTds)}
              subtext={breakdownLine(
                data.kpis.totalInterestTds,
                data.kpis.totalReferralTds
              )}
              tone="orange"
              icon={<Calculator size={18} />}
            />
            <TdsKpi
              label="CURRENT MONTH TDS"
              value={formatInr(data.kpis.currentMonthTds)}
              subtext={breakdownLine(
                data.kpis.monthInterestTds,
                data.kpis.monthReferralTds
              )}
              tone="green"
              icon={<CalendarDays size={18} />}
            />
            <TdsKpi
              label="CURRENT FY TDS"
              value={formatInr(data.kpis.currentFyTds)}
              subtext={breakdownLine(data.kpis.fyInterestTds, data.kpis.fyReferralTds)}
              tone="purple"
              icon={<FilePenLine size={18} />}
            />
          </>
        )}
      </section>

      {!isLoading && data ? (
        <p className="tds-math-hint">
          Current FY = Interest filings {formatInr(data.kpis.fyInterestTds)} + Referral TDS{' '}
          {formatInr(data.kpis.fyReferralTds)} ={' '}
          <strong>{formatInr(data.kpis.currentFyTds)}</strong>
          {data.kpis.fyLabel ? ` · ${data.kpis.fyLabel}` : ''}
        </p>
      ) : null}

      <section className="tds-layout">
        <div className="tds-tables-stack">
          <article className="card tds-table-card">
            <div className="tds-table-head">
              <h2>Interest TDS (investments)</h2>
              {!isLoading && data ? (
                <span className="tds-table-total">
                  FY total {formatInr(interestFyTotal)}
                </span>
              ) : null}
            </div>
            {isLoading ? (
              <div className="state-box">Loading filings…</div>
            ) : !data || data.rows.length === 0 ? (
              <div className="state-box">
                No completed interest periods in the current financial year.
              </div>
            ) : (
              <div style={{ overflowX: 'auto' }}>
                <table className="data-table tds-table">
                  <thead>
                    <tr>
                      <th>CUSTOMER NAME</th>
                      <th>INVESTMENT ID</th>
                      <th>PRINCIPAL</th>
                      <th>GROSS INT.</th>
                      <th>TDS RATE</th>
                      <th>TDS AMOUNT</th>
                      <th>PERIOD</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.rows.map((row) => (
                      <tr key={`${row.investment_id}-${row.quarter}`}>
                        <td>
                          <strong>{row.customer_name}</strong>
                        </td>
                        <td>{row.investment_code}</td>
                        <td>{formatInr(row.principal)}</td>
                        <td>{formatInr(row.gross_interest)}</td>
                        <td>{formatTdsRate(row.tds_percent)}</td>
                        <td>
                          <strong>{formatInr(row.tds_amount)}</strong>
                        </td>
                        <td>{row.period}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </article>

          <article className="card tds-table-card">
            <div className="tds-table-head">
              <h2>Referral TDS</h2>
              {!isLoading && data ? (
                <span className="tds-table-total">
                  FY total {formatInr(referralFyTotal)}
                </span>
              ) : null}
            </div>
            {isLoading ? (
              <div className="state-box">Loading referral TDS…</div>
            ) : !data || data.referralRows.length === 0 ? (
              <div className="state-box">
                No referral TDS in the current financial year.
              </div>
            ) : (
              <div style={{ overflowX: 'auto' }}>
                <table className="data-table tds-table">
                  <thead>
                    <tr>
                      <th>REFERRER</th>
                      <th>REFERRED</th>
                      <th>INVESTMENT</th>
                      <th>GROSS BONUS</th>
                      <th>TDS RATE</th>
                      <th>TDS AMOUNT</th>
                      <th>PERIOD</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.referralRows.map((row) => (
                      <tr key={row.id}>
                        <td>
                          <strong>{row.referrer_name}</strong>
                        </td>
                        <td>{row.referred_name}</td>
                        <td>{row.investment_code}</td>
                        <td>{formatInr(row.gross_bonus)}</td>
                        <td>{formatTdsRate(row.tds_rate)}</td>
                        <td>
                          <strong>{formatInr(row.tds_amount)}</strong>
                        </td>
                        <td title={formatDate(row.credited_on)}>{row.period}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </article>
        </div>

        {isLoading ? (
          <section className="card tds-chart-card">
            <h2>TDS Distribution by Quarter</h2>
            <p className="state-box">Loading distribution…</p>
          </section>
        ) : (
          <TdsQuarterChart
            slices={data?.quarters ?? []}
            fyTotal={data?.kpis.currentFyTds ?? 0}
            fyShort={data?.kpis.fyShort ?? ''}
          />
        )}
      </section>
    </>
  );
}
