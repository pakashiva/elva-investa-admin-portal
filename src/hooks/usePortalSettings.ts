import { useCallback, useEffect, useState } from 'react';
import {
  getPortalSettings,
  resetPortalSettings,
  savePortalSettings,
} from '../services/settingsService';
import type { PortalSettings } from '../types/admin';

export function usePortalSettings() {
  const [settings, setSettings] = useState<PortalSettings | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      setSettings(await getPortalSettings());
    } catch (err) {
      setSettings(null);
      setError(err instanceof Error ? err.message : 'Failed to load settings');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const save = useCallback(async (next: Omit<PortalSettings, 'updated_at'>) => {
    setIsSaving(true);
    setError(null);
    setNotice(null);
    try {
      const saved = await savePortalSettings(next);
      setSettings(saved);
      setNotice('Settings saved.');
      return saved;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save settings');
      throw err;
    } finally {
      setIsSaving(false);
    }
  }, []);

  const reset = useCallback(async () => {
    setIsSaving(true);
    setError(null);
    setNotice(null);
    try {
      const saved = await resetPortalSettings();
      setSettings(saved);
      setNotice('Settings reset to defaults.');
      return saved;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to reset settings');
      throw err;
    } finally {
      setIsSaving(false);
    }
  }, []);

  return {
    settings,
    isLoading,
    isSaving,
    error,
    notice,
    setNotice,
    reload: load,
    save,
    reset,
  };
}
