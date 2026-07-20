// In-memory transfer records + a simple async settlement queue.
// The W3C trace context captured at enqueue time is replayed during settlement so
// the async settle span joins the same distributed trace as transfer.create.
import { context } from '@sea-bank/common';
import type { Context } from '@opentelemetry/api';

export type TransferStatus = 'PENDING' | 'COMPLETED' | 'FAILED';

export interface Transfer {
  id: string;
  customerId: string;
  fromAccountId: string;
  toAccountId: string;
  amount: number;
  currency: string;
  status: TransferStatus;
  createdAt: string;
  completedAt?: string;
  error?: string;
}

const transfers: Transfer[] = [];
let seq = 5000;

export function createTransfer(input: Omit<Transfer, 'id' | 'status' | 'createdAt'>): Transfer {
  const tr: Transfer = { ...input, id: `TRF-${++seq}`, status: 'PENDING', createdAt: new Date().toISOString() };
  transfers.push(tr);
  return tr;
}

export function listTransfers(customerId: string): Transfer[] {
  return transfers.filter((t) => t.customerId === customerId).slice().reverse();
}

export function getTransfer(id: string): Transfer | undefined {
  return transfers.find((t) => t.id === id);
}

// --- settlement queue ---
export interface QueueItem {
  transferId: string;
  ctx: Context;
}

const queue: QueueItem[] = [];

export function enqueue(transferId: string): void {
  queue.push({ transferId, ctx: context.active() });
}

export function dequeue(): QueueItem | undefined {
  return queue.shift();
}

export function queueDepth(): number {
  return queue.length;
}
