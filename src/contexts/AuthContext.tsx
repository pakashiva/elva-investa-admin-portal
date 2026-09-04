import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { Session } from '@supabase/supabase-js';
import { SKIP_ADMIN_AUTH } from '../lib/authConfig';
import { supabase } from '../lib/supabase';
import { getAdminMe, signOutAdmin } from '../services/authService';
import type { AdminMe } from '../types/admin';

type AuthStatus = 'loading' | 'anonymous' | 'unauthorized' | 'admin';

type AuthContextValue = {
  status: AuthStatus;
  session: Session | null;
  admin: AdminMe | null;
  error: string | null;
  signOut: () => Promise<void>;
  refresh: () => Promise<void>;
};

const DEV_ADMIN: AdminMe = {
  user_id: 'dev-bypass',
  role: 'operator',
  full_name: 'Developer',
  email: null,
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [admin, setAdmin] = useState<AdminMe | null>(SKIP_ADMIN_AUTH ? DEV_ADMIN : null);
  const [status, setStatus] = useState<AuthStatus>(SKIP_ADMIN_AUTH ? 'admin' : 'loading');
  const [error, setError] = useState<string | null>(null);

  const resolveSession = useCallback(async (nextSession: Session | null) => {
    if (SKIP_ADMIN_AUTH) {
      setSession(nextSession);
      setAdmin(DEV_ADMIN);
      setStatus('admin');
      setError(null);
      return;
    }

    setSession(nextSession);
    setError(null);

    if (!nextSession) {
      setAdmin(null);
      setStatus('anonymous');
      return;
    }

    try {
      const me = await getAdminMe();
      setAdmin(me);
      setStatus('admin');
    } catch (err) {
      setAdmin(null);
      setStatus('unauthorized');
      setError(err instanceof Error ? err.message : 'Not authorized');
    }
  }, []);

  useEffect(() => {
    if (SKIP_ADMIN_AUTH) {
      return;
    }

    let mounted = true;

    supabase.auth.getSession().then(({ data }) => {
      if (mounted) {
        void resolveSession(data.session);
      }
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      void resolveSession(nextSession);
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, [resolveSession]);

  const signOut = useCallback(async () => {
    if (SKIP_ADMIN_AUTH) {
      return;
    }
    await signOutAdmin();
    setAdmin(null);
    setStatus('anonymous');
  }, []);

  const refresh = useCallback(async () => {
    if (SKIP_ADMIN_AUTH) {
      setAdmin(DEV_ADMIN);
      setStatus('admin');
      return;
    }
    const { data } = await supabase.auth.getSession();
    await resolveSession(data.session);
  }, [resolveSession]);

  const value = useMemo(
    () => ({
      status,
      session,
      admin,
      error,
      signOut,
      refresh,
    }),
    [status, session, admin, error, signOut, refresh]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
