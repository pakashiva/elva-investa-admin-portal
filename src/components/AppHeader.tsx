import type { ReactNode } from 'react';
import { Bell } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { useUnreadCount } from '../hooks/useUnreadCount';
import { adminRoleLabel, firstName } from '../utils/format';
import { MenuButton } from './Sidebar';

type AppHeaderProps = {
  title: string;
  subtitle: string;
  showSearch?: boolean;
  actions?: ReactNode;
  onOpenMenu: () => void;
};

export function AppHeader({
  title,
  subtitle,
  showSearch = false,
  actions,
  onOpenMenu,
}: AppHeaderProps) {
  const { admin } = useAuth();
  const unreadCount = useUnreadCount();

  return (
    <header className="page-header">
      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
        <MenuButton onClick={onOpenMenu} />
        <div className="page-title">
          <h1>{title}</h1>
          <p>{subtitle}</p>
        </div>
      </div>

      <div className="header-tools">
        {showSearch ? (
          <form className="search-pill" action="/customers">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden>
              <circle cx="11" cy="11" r="7" stroke="currentColor" strokeWidth="2" />
              <path d="M20 20L17 17" stroke="currentColor" strokeWidth="2" />
            </svg>
            <input name="q" placeholder="Search operations..." />
          </form>
        ) : null}
        {actions}
        <Link to="/notifications" className="icon-btn" aria-label="Notifications">
          <Bell size={18} />
          {unreadCount > 0 ? <span className="dot" /> : null}
        </Link>
        <div className="profile-chip">
          <img className="avatar" src="/avatar.png" alt="" />
          <div>
            <strong>{admin ? firstName(admin.full_name) : 'Admin'}</strong>
            <span>{admin ? adminRoleLabel(admin.role) : ''}</span>
          </div>
        </div>
      </div>
    </header>
  );
}
