// In-memory account + transaction store with a tiny balance cache.
// All values are synthetic demo data. A "db.query"/cache span in index.ts simulates
// the data tier so APM traces show a realistic multi-tier shape.

export interface Account {
  id: string;
  customerId: string;
  type: 'SAVINGS' | 'CURRENT';
  name: string;
  currency: string;
  balance: number;
}

export interface Txn {
  id: string;
  accountId: string;
  ts: string;
  amount: number;
  type: 'CREDIT' | 'DEBIT';
  description: string;
}

const accounts: Account[] = [
  { id: 'ACC-1001', customerId: 'CUST-0001', type: 'SAVINGS', name: 'Everyday Savings', currency: 'SGD', balance: 12500.5 },
  { id: 'ACC-1002', customerId: 'CUST-0001', type: 'CURRENT', name: 'Current Account', currency: 'SGD', balance: 3200.0 },
  { id: 'ACC-2001', customerId: 'CUST-0002', type: 'SAVINGS', name: 'Everyday Savings', currency: 'SGD', balance: 8800.75 },
  { id: 'ACC-3001', customerId: 'CUST-0003', type: 'SAVINGS', name: 'Everyday Savings', currency: 'SGD', balance: 15000.0 },
  { id: 'ACC-3002', customerId: 'CUST-0003', type: 'CURRENT', name: 'Current Account', currency: 'SGD', balance: 450.25 },
];

let txnSeq = 1000;
const txns: Txn[] = [
  { id: `TXN-${++txnSeq}`, accountId: 'ACC-1001', ts: new Date(Date.now() - 864e5 * 3).toISOString(), amount: 2500, type: 'CREDIT', description: 'Salary' },
  { id: `TXN-${++txnSeq}`, accountId: 'ACC-1001', ts: new Date(Date.now() - 864e5 * 2).toISOString(), amount: 89.9, type: 'DEBIT', description: 'Groceries' },
  { id: `TXN-${++txnSeq}`, accountId: 'ACC-1002', ts: new Date(Date.now() - 864e5).toISOString(), amount: 45.0, type: 'DEBIT', description: 'Transport' },
  { id: `TXN-${++txnSeq}`, accountId: 'ACC-2001', ts: new Date(Date.now() - 864e5 * 5).toISOString(), amount: 1200, type: 'CREDIT', description: 'Refund' },
];

export function listAccounts(customerId: string): Account[] {
  return accounts.filter((a) => a.customerId === customerId);
}

export function getAccount(id: string): Account | undefined {
  return accounts.find((a) => a.id === id);
}

export function getTransactions(id: string, limit = 20): Txn[] {
  return txns.filter((t) => t.accountId === id).slice(-limit).reverse();
}

/** Apply a signed delta and record a transaction. Throws on unknown account / insufficient funds. */
export function adjustBalance(id: string, delta: number, type: 'DEBIT' | 'CREDIT', description: string): number {
  const acc = getAccount(id);
  if (!acc) throw Object.assign(new Error('account_not_found'), { status: 404 });
  if (type === 'DEBIT' && acc.balance + delta < 0) {
    throw Object.assign(new Error('insufficient_funds'), { status: 409 });
  }
  acc.balance = Math.round((acc.balance + delta) * 100) / 100;
  txns.push({ id: `TXN-${++txnSeq}`, accountId: id, ts: new Date().toISOString(), amount: Math.abs(delta), type, description });
  return acc.balance;
}

// --- Tiny balance cache (simulates a Redis-style cache tier) ---
const cache = new Map<string, { balance: number; at: number }>();
const TTL_MS = 10_000;

export function cacheGetBalance(id: string): number | undefined {
  const c = cache.get(id);
  if (c && Date.now() - c.at < TTL_MS) return c.balance;
  return undefined;
}
export function cacheSetBalance(id: string, balance: number): void {
  cache.set(id, { balance, at: Date.now() });
}
export function cacheInvalidate(id: string): void {
  cache.delete(id);
}
