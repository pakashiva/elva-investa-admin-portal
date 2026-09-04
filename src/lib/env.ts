export function getSupabaseUrl(): string {
  const url = import.meta.env.VITE_SUPABASE_URL?.trim();
  if (!url) {
    throw new Error('Missing VITE_SUPABASE_URL. Add it to your .env file.');
  }
  return url;
}

export function getSupabasePublishableKey(): string {
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!key) {
    throw new Error('Missing VITE_SUPABASE_PUBLISHABLE_KEY. Add it to your .env file.');
  }
  return key;
}
