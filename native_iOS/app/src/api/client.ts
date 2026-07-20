// Thin API client for the gateway. Also holds the demo fault headers that the
// Demo Controls screen can toggle to inject per-request latency/errors from the app.
import {config} from '../config';

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = 'ApiError';
  }
}

let token: string | null = null;
export function setToken(t: string | null): void {
  token = t;
}

/** Mutable header bag applied to every request; Demo Controls writes into this. */
export const demoFaultHeaders: Record<string, string> = {};

async function request<T>(path: string, opts: {method?: string; body?: unknown} = {}): Promise<T> {
  const headers: Record<string, string> = {'content-type': 'application/json', ...demoFaultHeaders};
  if (token) headers.authorization = `Bearer ${token}`;

  const res = await fetch(`${config.apiBaseUrl}${path}`, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });

  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    throw new ApiError(res.status, (data && data.error) || `HTTP ${res.status}`);
  }
  return data as T;
}

export interface Account {
  id: string;
  type: string;
  name: string;
  currency: string;
  balance: number;
}

export interface Transfer {
  id: string;
  fromAccountId: string;
  toAccountId: string;
  amount: number;
  currency: string;
  status: string;
  createdAt: string;
}

export interface Dashboard {
  name: string;
  customerId: string;
  accounts: Account[];
  transfers: Transfer[];
}

export const api = {
  login: (username: string, password: string) =>
    request<{token: string; customerId: string; name: string}>('/api/login', {method: 'POST', body: {username, password}}),
  dashboard: () => request<Dashboard>('/api/dashboard'),
  transactions: (id: string) => request<{transactions: any[]}>(`/api/accounts/${id}/transactions`),
  createTransfer: (b: {fromAccountId: string; toAccountId: string; amount: number}) =>
    request<Transfer>('/api/transfers', {method: 'POST', body: b}),
  listTransfers: () => request<{transfers: Transfer[]}>('/api/transfers'),
  setFault: (b: {service?: string; latencyMs?: number; errorRate?: number}) =>
    request('/api/admin/fault', {method: 'POST', body: b}),
  clearFault: () => request('/api/admin/fault', {method: 'DELETE'}),
};
