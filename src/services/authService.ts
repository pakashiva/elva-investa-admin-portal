import { supabase } from '../lib/supabase';
import type { AdminMe } from '../types/admin';
import { parseRpcError } from '../utils/format';

export async function signInAdmin(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim().toLowerCase(),
    password,
  });

  if (error) {
    throw new Error(
      error.message.toLowerCase().includes('invalid login credentials')
        ? 'Invalid email or password.'
        : error.message
    );
  }

  return data.session;
}

export async function signOutAdmin() {
  const { error } = await supabase.auth.signOut();
  if (error) {
    throw new Error(error.message);
  }
}

export async function getAdminMe(): Promise<AdminMe> {
  const { data, error } = await supabase.rpc('admin_get_me');

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = data as AdminMe | null;
  if (!row?.user_id) {
    throw new Error('This account is not authorized for the Admin Portal.');
  }

  return row;
}
