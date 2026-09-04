import { ADMIN_SESSION_KEY, type PortalSession } from '../lib/authConfig';
import { supabase } from '../lib/supabase';
import { parseRpcError } from '../utils/format';

export function readPortalSession(): PortalSession | null {
  try {
    const raw = localStorage.getItem(ADMIN_SESSION_KEY);
    if (!raw) {
      return null;
    }
    const parsed = JSON.parse(raw) as PortalSession;
    if (!parsed?.username) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export function writePortalSession(username: string): PortalSession {
  const session: PortalSession = {
    username,
    loggedInAt: new Date().toISOString(),
  };
  localStorage.setItem(ADMIN_SESSION_KEY, JSON.stringify(session));
  return session;
}

export function clearPortalSession() {
  localStorage.removeItem(ADMIN_SESSION_KEY);
}

export async function portalLogin(username: string, password: string): Promise<PortalSession> {
  const { data, error } = await supabase.rpc('admin_portal_login', {
    p_username: username.trim(),
    p_password: password,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as { ok?: boolean; username?: string };
  if (!row.ok || !row.username) {
    throw new Error('Invalid username or password.');
  }

  return writePortalSession(row.username);
}

export async function portalChangePassword(
  username: string,
  oldPassword: string,
  newPassword: string
): Promise<void> {
  const { data, error } = await supabase.rpc('admin_portal_change_password', {
    p_username: username.trim(),
    p_old_password: oldPassword,
    p_new_password: newPassword,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as { ok?: boolean };
  if (!row.ok) {
    throw new Error('Unable to update password.');
  }
}

export function portalSignOut() {
  clearPortalSession();
}
