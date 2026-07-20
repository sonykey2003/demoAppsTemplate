// Downstream HTTP helper. Injects W3C trace context so a distributed trace spans
// gateway -> auth/account/transfer (and transfer -> account). With no SDK attached
// the propagation.inject call is a no-op; when Splunk/AppD/OTel is injected it
// stitches the services into one trace.
import { propagation, context } from '@opentelemetry/api';

export interface CallOptions {
  method?: string;
  body?: unknown;
  headers?: Record<string, string>;
  /** Forwarded fault headers, if the caller wants to propagate demo faults downstream. */
  faultHeaders?: Record<string, string>;
}

export async function callJson<T>(url: string, opts: CallOptions = {}): Promise<T> {
  const headers: Record<string, string> = {
    'content-type': 'application/json',
    ...(opts.headers ?? {}),
    ...(opts.faultHeaders ?? {}),
  };
  propagation.inject(context.active(), headers);

  const res = await fetch(url, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    const err = new Error(`downstream ${res.status} ${url}: ${text}`) as Error & { status?: number };
    err.status = res.status;
    throw err;
  }
  return (await res.json()) as T;
}

/** Extract fault headers from an inbound request-like header bag to forward downstream. */
export function extractFaultHeaders(get: (name: string) => string | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  const latency = get('x-fault-latency-ms');
  const errorRate = get('x-fault-error-rate');
  if (latency) out['x-fault-latency-ms'] = latency;
  if (errorRate) out['x-fault-error-rate'] = errorRate;
  return out;
}
