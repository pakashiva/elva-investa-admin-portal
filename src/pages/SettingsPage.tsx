import { useEffect, useState, type FormEvent } from 'react';
import { useOutletContext } from 'react-router-dom';
import { AppHeader } from '../components/AppHeader';
import { ErrorBanner } from '../components/States';
import { usePortalSettings } from '../hooks/usePortalSettings';
import type { AdminOutletContext } from '../layouts/AdminLayout';
import type { PortalSettings } from '../types/admin';

type FormState = Omit<PortalSettings, 'updated_at'>;

const EMPTY: FormState = {
  platform_name: '',
  support_email: '',
  support_phone: '',
  default_currency: 'INR',
  min_investment_amount: 0,
  max_investment_amount: 0,
  gateway_provider: '',
  merchant_id: '',
  api_key: '',
  api_secret: '',
  max_single_transaction: 0,
  daily_transfer_limit: 0,
};

function formatAmountInput(value: number): string {
  if (!Number.isFinite(value) || value === 0) {
    return '';
  }
  return value.toLocaleString('en-IN', {
    maximumFractionDigits: 0,
    minimumFractionDigits: 0,
  });
}

function parseAmountInput(value: string): number {
  const cleaned = value.replace(/[₹,\s]/g, '');
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function SettingsPage() {
  const { onOpenMenu } = useOutletContext<AdminOutletContext>();
  const portal = usePortalSettings();
  const [form, setForm] = useState<FormState>(EMPTY);
  const [amountText, setAmountText] = useState({
    min: '',
    max: '',
    single: '',
    daily: '',
  });

  useEffect(() => {
    if (!portal.settings) {
      return;
    }
    setForm({
      platform_name: portal.settings.platform_name,
      support_email: portal.settings.support_email,
      support_phone: portal.settings.support_phone,
      default_currency: portal.settings.default_currency,
      min_investment_amount: portal.settings.min_investment_amount,
      max_investment_amount: portal.settings.max_investment_amount,
      gateway_provider: portal.settings.gateway_provider,
      merchant_id: portal.settings.merchant_id,
      api_key: portal.settings.api_key,
      api_secret: portal.settings.api_secret,
      max_single_transaction: portal.settings.max_single_transaction,
      daily_transfer_limit: portal.settings.daily_transfer_limit,
    });
    setAmountText({
      min: formatAmountInput(portal.settings.min_investment_amount),
      max: formatAmountInput(portal.settings.max_investment_amount),
      single: formatAmountInput(portal.settings.max_single_transaction),
      daily: formatAmountInput(portal.settings.daily_transfer_limit),
    });
  }, [portal.settings]);

  function updateField<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  async function onSave(event: FormEvent) {
    event.preventDefault();
    try {
      await portal.save({
        ...form,
        min_investment_amount: parseAmountInput(amountText.min),
        max_investment_amount: parseAmountInput(amountText.max),
        max_single_transaction: parseAmountInput(amountText.single),
        daily_transfer_limit: parseAmountInput(amountText.daily),
      });
    } catch {
      /* error banner already set */
    }
  }

  async function onReset() {
    try {
      await portal.reset();
    } catch {
      /* error banner already set */
    }
  }

  return (
    <>
      <AppHeader
        title="Settings"
        subtitle="Configure platform defaults, payment gateway, and operational settings."
        onOpenMenu={onOpenMenu}
      />

      {portal.error ? (
        <ErrorBanner message={portal.error} onRetry={() => void portal.reload()} />
      ) : null}
      {portal.notice ? <div className="notice-box">{portal.notice}</div> : null}

      <form className="card settings-card" onSubmit={(event) => void onSave(event)}>
        {portal.isLoading ? (
          <p className="state-box">Loading settings…</p>
        ) : (
          <>
            <label className="settings-field">
              <span>Platform Name</span>
              <input
                className="settings-input"
                value={form.platform_name}
                onChange={(event) => updateField('platform_name', event.target.value)}
                placeholder="Venkatesh Traders"
              />
            </label>

            <label className="settings-field">
              <span>Support Email</span>
              <input
                className="settings-input"
                type="email"
                value={form.support_email}
                onChange={(event) => updateField('support_email', event.target.value)}
                placeholder="support@rouru.finance"
              />
            </label>

            <label className="settings-field">
              <span>Support Phone</span>
              <input
                className="settings-input"
                type="tel"
                value={form.support_phone}
                onChange={(event) => updateField('support_phone', event.target.value)}
                placeholder="+91 98765 43210"
              />
            </label>

            <label className="settings-field">
              <span>Default Currency</span>
              <select
                className="settings-input"
                value={form.default_currency}
                onChange={(event) => updateField('default_currency', event.target.value)}
              >
                <option value="INR">INR</option>
                <option value="USD">USD</option>
                <option value="EUR">EUR</option>
              </select>
            </label>

            <div className="settings-row">
              <label className="settings-field">
                <span>Minimum Investment Amount</span>
                <input
                  className="settings-input"
                  value={amountText.min ? `₹${amountText.min}` : ''}
                  onChange={(event) =>
                    setAmountText((prev) => ({
                      ...prev,
                      min: formatAmountInput(parseAmountInput(event.target.value)),
                    }))
                  }
                  placeholder="₹10,000"
                />
              </label>
              <label className="settings-field">
                <span>Maximum Investment Amount</span>
                <input
                  className="settings-input"
                  value={amountText.max ? `₹${amountText.max}` : ''}
                  onChange={(event) =>
                    setAmountText((prev) => ({
                      ...prev,
                      max: formatAmountInput(parseAmountInput(event.target.value)),
                    }))
                  }
                  placeholder="₹1,00,00,000"
                />
              </label>
            </div>

            <h3>Primary Gateway</h3>

            <label className="settings-field">
              <span>Gateway Provider</span>
              <input
                className="settings-input"
                value={form.gateway_provider}
                onChange={(event) => updateField('gateway_provider', event.target.value)}
              />
            </label>

            <label className="settings-field">
              <span>Merchant ID</span>
              <input
                className="settings-input"
                value={form.merchant_id}
                onChange={(event) => updateField('merchant_id', event.target.value)}
              />
            </label>

            <label className="settings-field">
              <span>API Key</span>
              <input
                className="settings-input"
                type="password"
                autoComplete="off"
                value={form.api_key}
                onChange={(event) => updateField('api_key', event.target.value)}
              />
            </label>

            <label className="settings-field">
              <span>API Secret</span>
              <input
                className="settings-input"
                type="password"
                autoComplete="off"
                value={form.api_secret}
                onChange={(event) => updateField('api_secret', event.target.value)}
              />
            </label>

            <h3>Transaction Limits</h3>

            <label className="settings-field">
              <span>Max Single Transaction (₹)</span>
              <input
                className="settings-input"
                value={amountText.single ? `₹${amountText.single}` : ''}
                onChange={(event) =>
                  setAmountText((prev) => ({
                    ...prev,
                    single: formatAmountInput(parseAmountInput(event.target.value)),
                  }))
                }
                placeholder="₹10,00,000"
              />
            </label>

            <label className="settings-field">
              <span>Daily Transfer Limit (₹)</span>
              <input
                className="settings-input"
                value={amountText.daily ? `₹${amountText.daily}` : ''}
                onChange={(event) =>
                  setAmountText((prev) => ({
                    ...prev,
                    daily: formatAmountInput(parseAmountInput(event.target.value)),
                  }))
                }
                placeholder="₹50,00,000"
              />
            </label>

            <div className="settings-actions">
              <button type="submit" className="primary-btn settings-save" disabled={portal.isSaving}>
                {portal.isSaving ? 'Saving…' : 'Save Changes'}
              </button>
              <button
                type="button"
                className="settings-reset"
                disabled={portal.isSaving}
                onClick={() => void onReset()}
              >
                Reset to Defaults
              </button>
            </div>
          </>
        )}
      </form>
    </>
  );
}
