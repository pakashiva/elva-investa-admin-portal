import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard,
  Users,
  TrendingUp,
  Wallet,
  Receipt,
  Gift,
  FileBarChart,
  Bell,
  Settings,
  KeyRound,
  LogOut,
  Menu,
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

const NAV_ITEMS = [
  { to: '/', label: 'Dashboard', end: true },
  { to: '/customers', label: 'Customers', end: false },
  { to: '/investment-requests', label: 'Investment Requests', end: false },
  { to: '/withdrawals', label: 'Withdrawals', end: false },
  { to: '/tds', label: 'TDS', end: false },
  { to: '/referrals', label: 'Referrals & Commission', end: false },
  { to: '/reports', label: 'Reports', end: false },
  { to: '/notifications', label: 'Notifications', end: false },
  { to: '/settings', label: 'Settings', end: false },
  { to: '/manage-passwords', label: 'Manage Passwords', end: false },
] as const;

const ICONS = {
  Dashboard: LayoutDashboard,
  Customers: Users,
  'Investment Requests': TrendingUp,
  Withdrawals: Wallet,
  TDS: Receipt,
  'Referrals & Commission': Gift,
  Reports: FileBarChart,
  Notifications: Bell,
  Settings: Settings,
  'Manage Passwords': KeyRound,
} as const;

type SidebarProps = {
  open: boolean;
  onClose: () => void;
};

export function Sidebar({ open, onClose }: SidebarProps) {
  const { signOut } = useAuth();

  return (
    <>
      {open ? <div className="sidebar-backdrop" onClick={onClose} /> : null}
      <aside className={`sidebar${open ? ' open' : ''}`}>
        <div className="sidebar-brand">
          <img src="/logo-mark.png" alt="" />
          <div className="sidebar-brand-text">
            <strong>Venkatesh Traders</strong>
            <span>ADMIN PORTAL</span>
          </div>
        </div>

        <nav className="sidebar-nav">
          {NAV_ITEMS.map((item) => {
            const Icon = ICONS[item.label];
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}
                onClick={onClose}
              >
                <Icon />
                {item.label}
              </NavLink>
            );
          })}
        </nav>

        <div className="ops-card">
          <strong>Operations Support</strong>
          <p>Escalations and portal issues</p>
          <a className="gold-btn" href="mailto:support@roxrufinancial.in">
            Contact Ops Dev
          </a>
        </div>

        <button type="button" className="logout-btn" onClick={() => void signOut()}>
          <LogOut size={16} />
          Logout
        </button>
      </aside>
    </>
  );
}

export function MenuButton({ onClick }: { onClick: () => void }) {
  return (
    <button type="button" className="menu-btn" onClick={onClick} aria-label="Open menu">
      <Menu size={20} />
    </button>
  );
}
