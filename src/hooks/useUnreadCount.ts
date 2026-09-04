import { useCallback, useEffect, useState } from 'react';
import { getUnreadNotificationCount } from '../services/notificationService';

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
    window.addEventListener('admin-notifications-changed', onChange);
    return () => window.removeEventListener('admin-notifications-changed', onChange);
  }, [load]);

  return count;
}
