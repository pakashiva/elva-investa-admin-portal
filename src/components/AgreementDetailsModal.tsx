import { FileText, X } from 'lucide-react';
import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { listChequePresets } from '../services/agreementService';
import type { AgreementBranch, AgreementInputs, ChequeFieldPresets } from '../types/admin';

const BRANCHES: { id: AgreementBranch; label: string; notice: string }[] = [
  { id: 'ballari', label: 'Ballari branch', notice: '30 days withdrawal notice' },
  { id: 'raichur', label: 'Raichur branch', notice: '60 days withdrawal notice' },
];

const NEW_VALUE = '__new__';

const EMPTY_PRESETS: ChequeFieldPresets = {
  cheque_nos: [],
  bank_names: [],
  bank_addresses: [],
};

type Props = {
  open: boolean;
  title: string;
  confirmLabel: string;
  busy?: boolean;
  error?: string | null;
  onClose: () => void;
  onConfirm: (inputs: AgreementInputs) => void;
};

type SavedFieldProps = {
  label: string;
  savedLabel: string;
  addLabel: string;
  placeholder: string;
  options: string[];
  value: string;
  onChange: (value: string) => void;
};

function SavedValueField({
  label,
  savedLabel,
  addLabel,
  placeholder,
  options,
  value,
  onChange,
}: SavedFieldProps) {
  const matched = options.find((item) => item === value);
  const selectValue = matched ?? NEW_VALUE;

  return (
    <>
      <label className="create-field">
        <span>{savedLabel}</span>
        <select
          value={selectValue}
          onChange={(event) => {
            const next = event.target.value;
            onChange(next === NEW_VALUE ? '' : next);
          }}
        >
          {options.map((item) => (
            <option key={item} value={item}>
              {item}
            </option>
          ))}
          <option value={NEW_VALUE}>{addLabel}</option>
        </select>
      </label>

      <label className="create-field">
        <span>{label}</span>
        <input
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
        />
      </label>
    </>
  );
}

export function AgreementDetailsModal({
  open,
  title,
  confirmLabel,
  busy = false,
  error: externalError = null,
  onClose,
  onConfirm,
}: Props) {
  const [branch, setBranch] = useState<AgreementBranch>('ballari');
  const [presets, setPresets] = useState<ChequeFieldPresets>(EMPTY_PRESETS);
  const [chequeNo, setChequeNo] = useState('');
  const [bankName, setBankName] = useState('');
  const [bankAddress, setBankAddress] = useState('');
  const [localError, setLocalError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }
    setLocalError(null);
    listChequePresets()
      .then((rows) => {
        setPresets(rows);
        setChequeNo(rows.cheque_nos[0] ?? '');
        setBankName(rows.bank_names[0] ?? '');
        setBankAddress(rows.bank_addresses[0] ?? '');
      })
      .catch(() => {
        setPresets(EMPTY_PRESETS);
        setChequeNo('');
        setBankName('');
        setBankAddress('');
      });
  }, [open]);

  const selectedNotice = useMemo(
    () => BRANCHES.find((item) => item.id === branch)?.notice ?? '',
    [branch]
  );

  if (!open) {
    return null;
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    if (!chequeNo.trim()) {
      setLocalError('Enter the cheque number.');
      return;
    }
    if (!bankName.trim()) {
      setLocalError('Enter the cheque bank name.');
      return;
    }
    if (!bankAddress.trim()) {
      setLocalError('Enter the cheque bank address / branch.');
      return;
    }
    setLocalError(null);
    onConfirm({
      branch,
      chequeNo: chequeNo.trim(),
      chequeBankName: bankName.trim(),
      chequeBankAddress: bankAddress.trim(),
    });
  }

  const error = localError || externalError;

  return (
    <div className="modal-backdrop" onClick={busy ? undefined : onClose}>
      <form
        className="create-customer-modal agreement-modal"
        role="dialog"
        aria-labelledby="agreement-modal-title"
        onClick={(event) => event.stopPropagation()}
        onSubmit={submit}
      >
        <header className="create-customer-head">
          <h2 id="agreement-modal-title">
            <FileText size={18} /> {title}
          </h2>
          <button
            type="button"
            className="modal-close"
            onClick={onClose}
            aria-label="Close"
            disabled={busy}
          >
            <X size={18} />
          </button>
        </header>

        <div className="create-customer-body">
          {error ? <div className="error-box">{error}</div> : null}

          <section className="create-section">
            <h3>Agreement Branch</h3>
            <div className="create-grid">
              <label className="create-field">
                <span>Branch</span>
                <select
                  value={branch}
                  onChange={(event) => setBranch(event.target.value as AgreementBranch)}
                >
                  {BRANCHES.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.label}
                    </option>
                  ))}
                </select>
                <em className="field-hint">{selectedNotice}</em>
              </label>
            </div>
          </section>

          <section className="create-section">
            <h3>Surety Cheque</h3>
            <div className="create-grid">
              <SavedValueField
                savedLabel="Saved Cheque Numbers"
                label="Cheque Number"
                addLabel="+ Add new cheque number"
                placeholder="e.g. 143538"
                options={presets.cheque_nos}
                value={chequeNo}
                onChange={setChequeNo}
              />

              <SavedValueField
                savedLabel="Saved Bank Names"
                label="Bank Name"
                addLabel="+ Add new bank name"
                placeholder="e.g. SBI Bank"
                options={presets.bank_names}
                value={bankName}
                onChange={setBankName}
              />

              <SavedValueField
                savedLabel="Saved Bank Addresses"
                label="Bank Address / Branch"
                addLabel="+ Add new bank address"
                placeholder="e.g. Gunj Circle, Raichur Branch"
                options={presets.bank_addresses}
                value={bankAddress}
                onChange={setBankAddress}
              />
            </div>
            <p className="field-hint">
              New values are saved automatically and appear in the matching dropdown next time.
            </p>
          </section>
        </div>

        <footer className="create-customer-footer">
          <button type="button" className="ghost-btn" onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button type="submit" className="gold-btn create-submit-btn" disabled={busy}>
            {busy ? 'Working…' : confirmLabel}
          </button>
        </footer>
      </form>
    </div>
  );
}
