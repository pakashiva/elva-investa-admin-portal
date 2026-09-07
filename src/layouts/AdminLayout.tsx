import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import { NotificationToastHost } from '../components/NotificationToastHost';
import { Sidebar } from '../components/Sidebar';

export function AdminLayout() {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <div className="app-shell">
      <Sidebar open={menuOpen} onClose={() => setMenuOpen(false)} />
      <main className="main">
        <Outlet context={{ onOpenMenu: () => setMenuOpen(true) }} />
      </main>
      <NotificationToastHost />
    </div>
  );
}

export type AdminOutletContext = {
  onOpenMenu: () => void;
};
