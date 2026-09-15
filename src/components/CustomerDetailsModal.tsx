import { useEffect, useMemo, useState } from 'react';
import { ChevronLeft, ChevronRight, X } from 'lucide-react';
import { EmptyState, ErrorBanner } from './States';
import { useCustomerDetails } from '../hooks/useCustomerDetails';
import {
  addBankAccount,
  updateBankAccount,
  updateCustomerProfile,
  updateInvestmentBank,
} from '../services/customerService';
import type {
  CustomerBankAccount,
  CustomerDetailsTab,
  CustomerInvestmentRow,
  CustomerListRow,
  CustomerProfile,
} from '../types/admin';
import {
  displayCustomerId,
  formatDate,
  formatInr,
  formatLedgerType,
  formatMobile,
  formatSignedInr,
} from '../utils/format';

type Props = {
  userId: string;
  neighbors: CustomerListRow[];
  onClose: () => void;
  onNavigate: (userId: string) => void;
};

type ProfileForm = {
  fullName: string;
  email: string;
  mobile: string;
  dateOfBirth: string;
  address: string;
  city: string;
  state: string;
  pinCode: string;
  panNumber: string;
};

type BankForm = {
  bankName: string;
  accountNumber: string;
  ifscCode: string;
  accountType: 'Savings' | 'Current';
  accountHolderName: string;
  branchName: string;
  isPrimary: boolean;
};

function digitsOnly(value: string): string {
  return value.replace(/\D/g, '');
}

function toDobInput(value: string): string {
  if (!value) return '';
  if (/^\d{4}-\d{2}-\d{2}/.test(value)) return value.slice(0, 10);
  return value;
}

function profileToForm(profile: CustomerProfile): ProfileForm {
  return {
    fullName: profile.full_name || '',
    email: profile.email_address || '',
    mobile: digitsOnly(profile.mobile_number || '').slice(-10),
    dateOfBirth: toDobInput(profile.date_of_birth),
    address: profile.address || '',
    city: profile.city === '—' ? '' : profile.city || '',
    state: profile.state === '—' ? '' : profile.state || '',
    pinCode: profile.pin_code === '000000' ? '' : profile.pin_code || '',
    panNumber: profile.pan_number || '',
  };
}

function bankToForm(bank: CustomerBankAccount): BankForm {
  return {
    bankName: bank.bank_name || '',
    accountNumber: bank.account_number || '',
    ifscCode: bank.ifsc_code || '',
    accountType: bank.account_type === 'Current' ? 'Current' : 'Savings',
    accountHolderName: bank.account_holder_name || '',
    branchName: bank.branch_name || '',
    isPrimary: bank.is_primary,
  };
}

const EMPTY_BANK: BankForm = {
  bankName: '',
  accountNumber: '',
  ifscCode: '',
  accountType: 'Savings',
  accountHolderName: '',
  branchName: '',
  isPrimary: false,
};

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div className="detail-field">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function EditField({
  label,
  value,
  onChange,
  type = 'text',
  disabled,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  disabled?: boolean;
}) {
  return (
    <label className="detail-field edit-field">
      <span>{label}</span>
      <input type={type} value={value} disabled={disabled} onChange={(e) => onChange(e.target.value)} />
    </label>
  );
}

function bankLabel(bank: CustomerBankAccount): string {
  return `${bank.bank_name || 'Bank'} · ${bank.account_number}${bank.is_primary ? ' (Primary)' : ''}`;
}

export function CustomerDetailsModal({ userId, neighbors, onClose, onNavigate }: Props) {
  const { data, isLoading, error, reload } = useCustomerDetails(userId);
  const [tab, setTab] = useState<CustomerDetailsTab>('profile');
  const [editingProfile, setEditingProfile] = useState(false);
  const [profileForm, setProfileForm] = useState<ProfileForm | null>(null);
  const [editingBankId, setEditingBankId] = useState<string | null>(null);
  const [bankForm, setBankForm] = useState<BankForm>(EMPTY_BANK);
  const [addingBank, setAddingBank] = useState(false);
  const [investmentBanks, setInvestmentBanks] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    setTab('profile');
    setEditingProfile(false);
    setProfileForm(null);
    setEditingBankId(null);
    setAddingBank(false);
    setSaveError(null);
    setNotice(null);
  }, [userId]);

  useEffect(() => {
    if (!data) return;
    setProfileForm(profileToForm(data.profile));
    const map: Record<string, string> = {};
    for (const inv of data.investments) {
      map[inv.id] = inv.bank_account_id ?? '';
    }
    setInvestmentBanks(map);
  }, [data]);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const index = neighbors.findIndex((row) => row.user_id === userId);
  const previous = index > 0 ? neighbors[index - 1] : undefined;
  const next = index >= 0 && index < neighbors.length - 1 ? neighbors[index + 1] : undefined;

  const tabs = useMemo(
    () =>
      [
        { id: 'profile' as const, label: 'Profile' },
        { id: 'banks' as const, label: 'Banks' },
        { id: 'investments' as const, label: 'Investments' },
        { id: 'transactions' as const, label: 'Transactions' },
      ] as const,
    []
  );

  async function saveProfile() {
    if (!data || !profileForm) return;
    setSaving(true);
    setSaveError(null);
    try {
      await updateCustomerProfile({
        userId: data.profile.user_id,
        fullName: profileForm.fullName.trim(),
        email: profileForm.email.trim(),
        mobile: digitsOnly(profileForm.mobile),
        dateOfBirth: profileForm.dateOfBirth,
        address: profileForm.address.trim(),
        city: profileForm.city.trim() || '—',
        state: profileForm.state.trim() || '—',
        pinCode: profileForm.pinCode.trim() || '000000',
        panNumber: profileForm.panNumber.trim().toUpperCase(),
      });
      setEditingProfile(false);
      setNotice('Profile saved.');
      await reload();
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : 'Could not save profile.');
    } finally {
      setSaving(false);
    }
  }

  async function saveBank(bankId: string | null) {
    if (!data) return;
    setSaving(true);
    setSaveError(null);
    try {
      const payload = {
        userId: data.profile.user_id,
        bankName: bankForm.bankName.trim(),
        accountNumber: digitsOnly(bankForm.accountNumber),
        ifscCode: bankForm.ifscCode.replace(/\s/g, '').toUpperCase(),
        accountType: bankForm.accountType,
        accountHolderName: bankForm.accountHolderName.trim(),
        branchName: bankForm.branchName.trim(),
        isPrimary: bankForm.isPrimary,
      };
      if (bankId) {
        await updateBankAccount({ ...payload, bankId });
      } else {
        await addBankAccount(payload);
      }
      setEditingBankId(null);
      setAddingBank(false);
      setBankForm(EMPTY_BANK);
      setNotice(bankId ? 'Bank account updated.' : 'Bank account added.');
      await reload();
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : 'Could not save bank account.');
    } finally {
      setSaving(false);
    }
  }

  async function saveInvestmentBank(inv: CustomerInvestmentRow) {
    const bankId = investmentBanks[inv.id];
    if (!bankId || bankId === inv.bank_account_id) {
      setSaveError('Select a different bank account to save.');
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      await updateInvestmentBank(inv.id, bankId);
      setNotice(`Payout bank updated for ${inv.code || inv.plan_name}.`);
      await reload();
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : 'Could not update investment bank.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <section
        className="customer-modal"
        role="dialog"
        aria-labelledby="customer-details-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="customer-modal-head">
          <div>
            <h2 id="customer-details-title">Customer Details</h2>
            <p>Customer ID: {displayCustomerId(data?.profile.customer_id)}</p>
          </div>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">
            <X size={18} />
          </button>
        </header>

        <nav className="customer-tabs">
          {tabs.map((item) => (
            <button
              key={item.id}
              type="button"
              className={tab === item.id ? 'active' : ''}
              onClick={() => {
                setTab(item.id);
                setSaveError(null);
                setNotice(null);
              }}
            >
              {item.label}
            </button>
          ))}
        </nav>

        {error ? <ErrorBanner message={error} onRetry={() => void reload()} /> : null}
        {saveError ? <div className="error-box" style={{ margin: '0 20px 12px' }}>{saveError}</div> : null}
        {notice ? <div className="notice-box success" style={{ margin: '0 20px 12px' }}>{notice}</div> : null}

        {isLoading || !data || !profileForm ? (
          <div className="state-box">{isLoading ? 'Loading customer…' : 'Customer not found'}</div>
        ) : (
          <>
            {tab === 'profile' ? (
              <div className="detail-stack">
                <article className="detail-card">
                  <div className="detail-card-toolbar">
                    <h3>Profile</h3>
                    {editingProfile ? (
                      <div className="detail-card-actions">
                        <button
                          type="button"
                          className="ghost-btn"
                          disabled={saving}
                          onClick={() => {
                            setEditingProfile(false);
                            setProfileForm(profileToForm(data.profile));
                            setSaveError(null);
                          }}
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          className="primary-btn"
                          disabled={saving}
                          onClick={() => void saveProfile()}
                        >
                          {saving ? 'Saving…' : 'Save changes'}
                        </button>
                      </div>
                    ) : (
                      <button
                        type="button"
                        className="ghost-btn"
                        onClick={() => {
                          setEditingProfile(true);
                          setNotice(null);
                        }}
                      >
                        Edit
                      </button>
                    )}
                  </div>

                  {editingProfile ? (
                    <div className="detail-grid">
                      <EditField
                        label="FULL NAME"
                        value={profileForm.fullName}
                        onChange={(v) => setProfileForm({ ...profileForm, fullName: v })}
                        disabled={saving}
                      />
                      <EditField
                        label="EMAIL ADDRESS"
                        value={profileForm.email}
                        onChange={(v) => setProfileForm({ ...profileForm, email: v })}
                        disabled={saving}
                      />
                      <EditField
                        label="PHONE NUMBER"
                        value={profileForm.mobile}
                        onChange={(v) => setProfileForm({ ...profileForm, mobile: digitsOnly(v).slice(0, 10) })}
                        disabled={saving}
                      />
                      <EditField
                        label="DATE OF BIRTH"
                        type="date"
                        value={profileForm.dateOfBirth}
                        onChange={(v) => setProfileForm({ ...profileForm, dateOfBirth: v })}
                        disabled={saving}
                      />
                      <EditField
                        label="PAN NUMBER"
                        value={profileForm.panNumber}
                        onChange={(v) =>
                          setProfileForm({ ...profileForm, panNumber: v.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 10) })
                        }
                        disabled={saving}
                      />
                    </div>
                  ) : (
                    <div className="detail-grid">
                      <Field label="FULL NAME" value={data.profile.full_name || '—'} />
                      <Field label="EMAIL ADDRESS" value={data.profile.email_address || '—'} />
                      <Field label="PHONE NUMBER" value={formatMobile(data.profile.mobile_number)} />
                      <Field label="DATE OF BIRTH" value={formatDate(data.profile.date_of_birth)} />
                      <Field label="PAN NUMBER" value={data.profile.pan_number || '—'} />
                    </div>
                  )}
                </article>

                <article className="detail-card">
                  <h3>Address</h3>
                  {editingProfile ? (
                    <div className="detail-grid">
                      <EditField
                        label="FULL ADDRESS"
                        value={profileForm.address}
                        onChange={(v) => setProfileForm({ ...profileForm, address: v })}
                        disabled={saving}
                      />
                      <EditField
                        label="CITY"
                        value={profileForm.city}
                        onChange={(v) => setProfileForm({ ...profileForm, city: v })}
                        disabled={saving}
                      />
                      <EditField
                        label="STATE"
                        value={profileForm.state}
                        onChange={(v) => setProfileForm({ ...profileForm, state: v })}
                        disabled={saving}
                      />
                      <EditField
                        label="PIN CODE"
                        value={profileForm.pinCode}
                        onChange={(v) => setProfileForm({ ...profileForm, pinCode: digitsOnly(v).slice(0, 6) })}
                        disabled={saving}
                      />
                    </div>
                  ) : (
                    <p>
                      {[data.profile.address, data.profile.city, data.profile.state, data.profile.pin_code]
                        .filter((part) => part && part !== '—' && part !== '000000')
                        .join(', ') || '—'}
                    </p>
                  )}
                </article>

                <article className="summary-card">
                  <h3>Investment Summary</h3>
                  <div className="summary-grid">
                    <div>
                      <span>TOTAL INVESTED</span>
                      <strong>{formatInr(data.summary.total_invested)}</strong>
                    </div>
                    <div>
                      <span>ACTIVE PLANS</span>
                      <strong>{data.summary.active_plans}</strong>
                    </div>
                    <div>
                      <span>RETURNS EARNED</span>
                      <strong>{formatInr(data.summary.returns_earned)}</strong>
                    </div>
                  </div>
                </article>
              </div>
            ) : null}

            {tab === 'banks' ? (
              <div className="detail-stack">
                <div className="detail-card-toolbar" style={{ padding: '0 4px' }}>
                  <h3 style={{ margin: 0 }}>Bank accounts</h3>
                  {!addingBank ? (
                    <button
                      type="button"
                      className="primary-btn"
                      onClick={() => {
                        setAddingBank(true);
                        setEditingBankId(null);
                        setBankForm({
                          ...EMPTY_BANK,
                          accountHolderName: data.profile.full_name,
                          isPrimary: data.banks.length === 0,
                        });
                        setNotice(null);
                      }}
                    >
                      + Add bank
                    </button>
                  ) : null}
                </div>

                {addingBank ? (
                  <article className="detail-card bank-card">
                    <div className="detail-card-toolbar">
                      <h3>New bank account</h3>
                      <div className="detail-card-actions">
                        <button
                          type="button"
                          className="ghost-btn"
                          disabled={saving}
                          onClick={() => {
                            setAddingBank(false);
                            setBankForm(EMPTY_BANK);
                          }}
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          className="primary-btn"
                          disabled={saving}
                          onClick={() => void saveBank(null)}
                        >
                          {saving ? 'Saving…' : 'Save'}
                        </button>
                      </div>
                    </div>
                    <BankEditFields form={bankForm} setForm={setBankForm} disabled={saving} />
                  </article>
                ) : null}

                {data.banks.length === 0 && !addingBank ? (
                  <EmptyState
                    title="No bank accounts"
                    message="Add a bank account so payouts can be linked to investments."
                  />
                ) : (
                  data.banks.map((bank) => {
                    const editing = editingBankId === bank.id;
                    return (
                      <article key={bank.id} className="detail-card bank-card">
                        <div className="detail-card-toolbar">
                          <div>
                            {bank.is_primary ? <span className="primary-badge">Primary</span> : null}
                          </div>
                          {editing ? (
                            <div className="detail-card-actions">
                              <button
                                type="button"
                                className="ghost-btn"
                                disabled={saving}
                                onClick={() => {
                                  setEditingBankId(null);
                                  setBankForm(EMPTY_BANK);
                                }}
                              >
                                Cancel
                              </button>
                              <button
                                type="button"
                                className="primary-btn"
                                disabled={saving}
                                onClick={() => void saveBank(bank.id)}
                              >
                                {saving ? 'Saving…' : 'Save changes'}
                              </button>
                            </div>
                          ) : (
                            <button
                              type="button"
                              className="ghost-btn"
                              onClick={() => {
                                setAddingBank(false);
                                setEditingBankId(bank.id);
                                setBankForm(bankToForm(bank));
                                setNotice(null);
                              }}
                            >
                              Edit
                            </button>
                          )}
                        </div>

                        {editing ? (
                          <BankEditFields form={bankForm} setForm={setBankForm} disabled={saving} />
                        ) : (
                          <div className="detail-grid">
                            <Field label="ACCOUNT HOLDER" value={bank.account_holder_name || '—'} />
                            <Field label="BANK NAME" value={bank.bank_name || '—'} />
                            <Field label="ACCOUNT NUMBER" value={bank.account_number || '—'} />
                            <Field label="IFSC CODE" value={bank.ifsc_code || '—'} />
                            <Field label="BRANCH" value={bank.branch_name || '—'} />
                            <Field label="ACCOUNT TYPE" value={bank.account_type || '—'} />
                          </div>
                        )}
                      </article>
                    );
                  })
                )}
              </div>
            ) : null}

            {tab === 'investments' ? (
              <div className="detail-stack">
                {data.investments.length === 0 ? (
                  <EmptyState
                    title="No open investments"
                    message="Pending or active plans will appear here so you can change the payout bank."
                  />
                ) : (
                  data.investments.map((inv) => {
                    const selected = investmentBanks[inv.id] ?? inv.bank_account_id ?? '';
                    const dirty = selected && selected !== (inv.bank_account_id ?? '');
                    return (
                      <article key={inv.id} className="detail-card">
                        <div className="detail-card-toolbar">
                          <div>
                            <h3 style={{ margin: 0 }}>{inv.code || inv.plan_name}</h3>
                            <p style={{ margin: '4px 0 0', color: 'var(--text-secondary)', fontSize: 13 }}>
                              {inv.plan_name} · {formatInr(inv.fund_amount)} · {inv.status}
                            </p>
                          </div>
                          <button
                            type="button"
                            className="primary-btn"
                            disabled={saving || !dirty || data.banks.length === 0}
                            onClick={() => void saveInvestmentBank(inv)}
                          >
                            {saving ? 'Saving…' : 'Save bank'}
                          </button>
                        </div>
                        <label className="detail-field edit-field">
                          <span>PAYOUT BANK ACCOUNT</span>
                          <select
                            value={selected}
                            disabled={saving || data.banks.length === 0}
                            onChange={(event) =>
                              setInvestmentBanks((prev) => ({
                                ...prev,
                                [inv.id]: event.target.value,
                              }))
                            }
                          >
                            <option value="">Select bank account</option>
                            {data.banks.map((bank) => (
                              <option key={bank.id} value={bank.id}>
                                {bankLabel(bank)}
                              </option>
                            ))}
                          </select>
                        </label>
                        <p style={{ margin: '8px 0 0', fontSize: 12, color: 'var(--text-muted)' }}>
                          Changing this updates where interest payouts are sent for this plan.
                        </p>
                      </article>
                    );
                  })
                )}
              </div>
            ) : null}

            {tab === 'transactions' ? (
              <article className="detail-card">
                <h3>Recent Transactions</h3>
                {data.transactions.length === 0 ? (
                  <EmptyState
                    title="No transactions"
                    message="No ledger entries exist for this customer yet."
                  />
                ) : (
                  <div style={{ overflowX: 'auto' }}>
                    <table className="ledger-table">
                      <thead>
                        <tr>
                          <th>DATE</th>
                          <th>TYPE</th>
                          <th>AMOUNT</th>
                          <th>STATUS</th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.transactions.map((row) => {
                          const amount = formatSignedInr(row.transaction_type, row.amount);
                          return (
                            <tr key={row.id}>
                              <td>{formatDate(row.occurred_on)}</td>
                              <td>{formatLedgerType(row.transaction_type)}</td>
                              <td className={amount.tone}>{amount.display}</td>
                              <td>
                                <span
                                  className={`status-pill ${row.status === 'Pending' ? 'pending' : 'verified'}`}
                                >
                                  {row.status}
                                </span>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </article>
            ) : null}
          </>
        )}

        <footer className="customer-modal-nav">
          <button
            type="button"
            className="nav-pill"
            disabled={!previous}
            onClick={() => previous && onNavigate(previous.user_id)}
            aria-label="Previous customer"
          >
            <ChevronLeft size={16} />
          </button>
          <button
            type="button"
            className="nav-pill"
            disabled={!next}
            onClick={() => next && onNavigate(next.user_id)}
            aria-label="Next customer"
          >
            <ChevronRight size={16} />
          </button>
        </footer>
      </section>
    </div>
  );
}

function BankEditFields({
  form,
  setForm,
  disabled,
}: {
  form: BankForm;
  setForm: (next: BankForm) => void;
  disabled?: boolean;
}) {
  return (
    <div className="detail-grid">
      <EditField
        label="ACCOUNT HOLDER"
        value={form.accountHolderName}
        onChange={(v) => setForm({ ...form, accountHolderName: v })}
        disabled={disabled}
      />
      <EditField
        label="BANK NAME"
        value={form.bankName}
        onChange={(v) => setForm({ ...form, bankName: v })}
        disabled={disabled}
      />
      <EditField
        label="ACCOUNT NUMBER"
        value={form.accountNumber}
        onChange={(v) => setForm({ ...form, accountNumber: digitsOnly(v).slice(0, 18) })}
        disabled={disabled}
      />
      <EditField
        label="IFSC CODE"
        value={form.ifscCode}
        onChange={(v) => setForm({ ...form, ifscCode: v.toUpperCase().replace(/\s/g, '').slice(0, 11) })}
        disabled={disabled}
      />
      <EditField
        label="BRANCH"
        value={form.branchName}
        onChange={(v) => setForm({ ...form, branchName: v })}
        disabled={disabled}
      />
      <label className="detail-field edit-field">
        <span>ACCOUNT TYPE</span>
        <select
          value={form.accountType}
          disabled={disabled}
          onChange={(e) =>
            setForm({ ...form, accountType: e.target.value === 'Current' ? 'Current' : 'Savings' })
          }
        >
          <option value="Savings">Savings</option>
          <option value="Current">Current</option>
        </select>
      </label>
      <label className="detail-field edit-field" style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
        <input
          type="checkbox"
          checked={form.isPrimary}
          disabled={disabled}
          onChange={(e) => setForm({ ...form, isPrimary: e.target.checked })}
        />
        <span>Set as primary account</span>
      </label>
    </div>
  );
}
