import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { SKIP_ADMIN_AUTH } from '../lib/authConfig';
import { AdminLayout } from '../layouts/AdminLayout';
import { CustomersPage } from '../pages/CustomersPage';
import { DashboardPage } from '../pages/DashboardPage';
import { InvestmentRequestsPage } from '../pages/InvestmentRequestsPage';
import { InvestmentReviewPage } from '../pages/InvestmentReviewPage';
import { LoginPage } from '../pages/LoginPage';
import { NotificationsPage } from '../pages/NotificationsPage';
import { PlaceholderPage } from '../pages/PlaceholderPage';
import { ReferralsPage } from '../pages/ReferralsPage';
import { ReportsPage } from '../pages/ReportsPage';
import { TdsPage } from '../pages/TdsPage';
import { UnauthorizedPage } from '../pages/UnauthorizedPage';
import { WithdrawalsPage } from '../pages/WithdrawalsPage';

function FullPageLoading() {
  return (
    <div className="auth-screen">
      <div className="auth-card">
        <p>Loading admin session…</p>
      </div>
    </div>
  );
}

function PortalRoutes() {
  return (
    <Routes>
      <Route element={<AdminLayout />}>
        <Route path="/" element={<DashboardPage />} />
        <Route path="/customers" element={<CustomersPage />} />
        <Route path="/customers/:userId" element={<CustomersPage />} />
        <Route path="/investment-requests" element={<InvestmentRequestsPage />} />
        <Route path="/investment-requests/:requestId" element={<InvestmentReviewPage />} />
        <Route path="/withdrawals" element={<WithdrawalsPage />} />
        <Route path="/tds" element={<TdsPage />} />
        <Route path="/referrals" element={<ReferralsPage />} />
        <Route path="/reports" element={<ReportsPage />} />
        <Route path="/notifications" element={<NotificationsPage />} />
        <Route
          path="/settings"
          element={<PlaceholderPage title="Settings" subtitle="Portal configuration" />}
        />
      </Route>
      <Route path="/login" element={<Navigate to="/" replace />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export function AppRoutes() {
  const { status } = useAuth();

  if (SKIP_ADMIN_AUTH) {
    return <PortalRoutes />;
  }

  if (status === 'loading') {
    return <FullPageLoading />;
  }

  if (status === 'anonymous') {
    return (
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    );
  }

  if (status === 'unauthorized') {
    return (
      <Routes>
        <Route path="*" element={<UnauthorizedPage />} />
      </Routes>
    );
  }

  return <PortalRoutes />;
}
