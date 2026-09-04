import { useState } from 'react';
import { useNavigate, useOutletContext } from 'react-router-dom';
import { AppHeader } from '../components/AppHeader';
import { EmptyState, ErrorBanner } from '../components/States';
import { useInvestmentRequests } from '../hooks/useInvestmentRequests';
import type { AdminOutletContext } from '../layouts/AdminLayout';
import type { InvestmentRequestFilter } from '../types/admin';
import {
  displayCustomerId,
  displayRequestId,
  formatDate,
  formatInr,
  requestStatusLabel,
} from '../utils/format';

const FILTERS: { id: InvestmentRequestFilter; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'pending', label: 'Pending' },
  { id: 'under_review', label: 'Under Review' },
  { id: 'approved', label: 'Approved' },
  { id: 'rejected', label: 'Rejected' },
];

export function InvestmentRequestsPage() {
  const { onOpenMenu } = useOutletContext<AdminOutletContext>();
  const navigate = useNavigate();
  const [notice, setNotice] = useState<string | null>(null);
  const requests = useInvestmentRequests();

  const rows = requests.result?.rows ?? [];
  const total = requests.result?.total ?? 0;
  const from = total === 0 ? 0 : (requests.page - 1) * requests.pageSize + 1;
  const to = Math.min(requests.page * requests.pageSize, total);

  return (
    <>
      <AppHeader
        title="Investment Requests"
        subtitle="Process and sign off client capital deployments."
        showSearch
        onOpenMenu={onOpenMenu}
        actions={
          <button
            type="button"
            className="primary-btn"
            onClick={() =>
              setNotice(
                'Fund requests are submitted by investors in the mobile app. Admin creation will be added later.'
              )
            }
          >
            + Create Investment Request
          </button>
        }
      />

      {notice ? <div className="notice-box">{notice}</div> : null}
      {requests.error ? (
        <ErrorBanner message={requests.error} onRetry={() => void requests.reload()} />
      ) : null}

      <section className="table-shell">
        <div className="table-toolbar">
          <div className="filter-tabs">
            {FILTERS.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`filter-tab${requests.filter === item.id ? ' active' : ''}`}
                onClick={() => requests.changeFilter(item.id)}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>

        {requests.isLoading ? (
          <div className="state-box">Loading requests…</div>
        ) : rows.length === 0 ? (
          <EmptyState
            title="No investment requests"
            message="No matching fund requests for this filter."
          />
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>REQUEST ID</th>
                  <th>CUSTOMER NAME</th>
                  <th>CUSTOMER ID</th>
                  <th>REQUESTED PLAN</th>
                  <th>AMOUNT</th>
                  <th>REQUEST DATE</th>
                  <th>STATUS</th>
                  <th>ACTION</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => {
                  const label = requestStatusLabel(row.status);
                  return (
                    <tr key={row.id}>
                      <td>{displayRequestId(row.request_id)}</td>
                      <td>
                        <strong>{row.customer_name}</strong>
                      </td>
                      <td>{displayCustomerId(row.customer_id)}</td>
                      <td>{row.plan_name}</td>
                      <td>{formatInr(row.fund_amount)}</td>
                      <td>{formatDate(row.created_at)}</td>
                      <td>
                        <span
                          className={`status-pill ${
                            label === 'Approved'
                              ? 'approved'
                              : label === 'Rejected'
                                ? 'rejected'
                                : label === 'Under Review'
                                  ? 'review'
                                  : 'pending'
                          }`}
                        >
                          {label}
                        </span>
                      </td>
                      <td>
                        <button
                          type="button"
                          className="ghost-btn"
                          onClick={() => navigate(`/investment-requests/${row.id}`)}
                        >
                          Review
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        <div className="table-footer">
          <span>{total === 0 ? '0 requests' : `Showing ${from}–${to} of ${total}`}</span>
          <div className="pager">
            <button
              type="button"
              className="ghost-btn"
              disabled={requests.page <= 1}
              onClick={() => requests.setPage(Math.max(1, requests.page - 1))}
            >
              Previous
            </button>
            <button
              type="button"
              className="ghost-btn"
              disabled={requests.page >= requests.pageCount || total === 0}
              onClick={() => requests.setPage(requests.page + 1)}
            >
              Next
            </button>
          </div>
        </div>
      </section>
    </>
  );
}
