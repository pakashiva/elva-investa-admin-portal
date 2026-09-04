import { supabase } from '../lib/supabase';
import type {
  BuiltReport,
  GeneratedReportRow,
  ReportFormat,
  ReportKind,
  ReportSheet,
} from '../types/admin';
import { parseRpcError } from '../utils/format';

function asFormat(value: unknown): ReportFormat {
  if (value === 'csv' || value === 'pdf') {
    return value;
  }
  return 'xlsx';
}

function mapSheet(row: Record<string, unknown>): ReportSheet {
  return {
    name: String(row.name ?? 'Sheet'),
    rows: Array.isArray(row.rows)
      ? row.rows.map((item) => (item && typeof item === 'object' ? (item as Record<string, unknown>) : {}))
      : [],
  };
}

function mapHistory(row: Record<string, unknown>): GeneratedReportRow {
  return {
    id: String(row.id ?? ''),
    report_name: String(row.report_name ?? 'Report'),
    report_type: String(row.report_type ?? 'Report'),
    date_range_label: String(row.date_range_label ?? '—'),
    generated_by: String(row.generated_by ?? 'Admin'),
    generated_date: String(row.generated_date ?? row.created_at ?? ''),
    format: asFormat(row.format),
    created_at: String(row.created_at ?? ''),
  };
}

export async function buildReport(
  kind: ReportKind,
  from: string,
  to: string
): Promise<BuiltReport> {
  const { data, error } = await supabase.rpc('admin_build_report', {
    p_kind: kind,
    p_from: from,
    p_to: to,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  return {
    name: String(payload.name ?? 'Report'),
    type: String(payload.type ?? 'Report'),
    sheets: Array.isArray(payload.sheets)
      ? payload.sheets.map((sheet) => mapSheet(sheet as Record<string, unknown>))
      : [],
  };
}

export async function saveGeneratedReport(input: {
  name: string;
  type: string;
  from: string;
  to: string;
  rangeLabel: string;
  generatedBy: string;
  format: ReportFormat;
  payload: BuiltReport;
}): Promise<GeneratedReportRow> {
  const { data, error } = await supabase.rpc('admin_save_generated_report', {
    p_name: input.name,
    p_type: input.type,
    p_from: input.from,
    p_to: input.to,
    p_range_label: input.rangeLabel,
    p_generated_by: input.generatedBy,
    p_format: input.format,
    p_payload: input.payload,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  return mapHistory((data ?? {}) as Record<string, unknown>);
}

export async function listGeneratedReports(): Promise<GeneratedReportRow[]> {
  const { data, error } = await supabase.rpc('admin_list_generated_reports');

  if (error) {
    throw new Error(parseRpcError(error));
  }

  return Array.isArray(data)
    ? data.map((row) => mapHistory(row as Record<string, unknown>))
    : [];
}

export async function getGeneratedReport(id: string): Promise<{
  meta: GeneratedReportRow;
  payload: BuiltReport;
}> {
  const { data, error } = await supabase.rpc('admin_get_generated_report', {
    p_id: id,
  });

  if (error) {
    throw new Error(parseRpcError(error));
  }

  const row = (data ?? {}) as Record<string, unknown>;
  const payload = (row.payload ?? {}) as Record<string, unknown>;
  return {
    meta: mapHistory(row),
    payload: {
      name: String(payload.name ?? row.report_name ?? 'Report'),
      type: String(payload.type ?? row.report_type ?? 'Report'),
      sheets: Array.isArray(payload.sheets)
        ? payload.sheets.map((sheet) => mapSheet(sheet as Record<string, unknown>))
        : [],
    },
  };
}
