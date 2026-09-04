import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import {
  portalLogin,
  portalSignOut,
  readPortalSession,
} from '../services/authService';
import type { AdminMe } from '../types/admin';

type AuthStatus = 'loading' | 'anonymous' | 'admin';

type AuthContextValue = {
  status: AuthStatus;
  admin: AdminMe | null;
  error: string | null;
  signIn: (username: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  refresh: () => Promise<void>;
};

function toAdmin(username: string): AdminMe {
  return {
    user_id: username,
    role: 'super_admin',
    full_name: username,
    email: null,
  };
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [admin, setAdmin] = useState<AdminMe | null>(null);
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const session = readPortalSession();
    if (session) {
      setAdmin(toAdmin(session.username));
      setStatus('admin');
      setError(null);
      return;
    }
    setAdmin(null);
    setStatus('anonymous');
    setError(null);
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const signIn = useCallback(async (username: string, password: string) => {
    setError(null);
    const session = await portalLogin(username, password);
    setAdmin(toAdmin(session.username));
    setStatus('admin');
  }, []);

  const signOut = useCallback(async () => {
    portalSignOut();
    setAdmin(null);
    setStatus('anonymous');
    setError(null);
  }, []);

  const value = useMemo(
    () => ({
      status,
      admin,
      error,
      signIn,
      signOut,
      refresh,
    }),
    [status, admin, error, signIn, signOut, refresh]
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
