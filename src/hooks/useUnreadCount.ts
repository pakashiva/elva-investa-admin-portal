import { useCallback, useEffect, useState } from 'react';
import { getUnreadNotificationCount } from '../services/notificationService';

const POLL_MS = 3_000;

export function useUnreadCount() {
  const [count, setCount] = useState(0);

  const load = useCallback(async () => {
    try {
      setCount(await getUnreadNotificationCount());
    } catch {
      setCount(0);
    }
  }, []);

  useEffect(() => {
    void load();
    const onChange = () => void load();
    const interval = window.setInterval(() => void load(), POLL_MS);
    window.addEventListener('admin-notifications-changed', onChange);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener('admin-notifications-changed', onChange);
    };
  }, [load]);

  return count;
}
