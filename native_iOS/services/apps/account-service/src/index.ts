import {
  createBaseApp,
  startServer,
  port,
  withSpan,
  meter,
  faultMiddleware,
  sleep,
  log,
} from '@sea-bank/common';
import {
  listAccounts,
  getAccount,
  getTransactions,
  adjustBalance,
  cacheGetBalance,
  cacheSetBalance,
  cacheInvalidate,
} from './data';

const app = createBaseApp();

const balanceCounter = meter.createCounter('account_balance_requests_total', {
  description: 'Balance lookups by cache result',
});

app.use(faultMiddleware());

app.get('/accounts', async (req, res, next) => {
  const customerId = String(req.query.customerId ?? '');
  if (!customerId) {
    res.status(400).json({ error: 'customerId_required' });
    return;
  }
  try {
    const accounts = await withSpan('account.list', { customer_id: customerId }, async () => {
      await withSpan('db.query', { 'db.operation': 'SELECT', 'db.table': 'accounts' }, () => sleep(20));
      return listAccounts(customerId);
    });
    res.json({ accounts });
  } catch (err) {
    next(err);
  }
});

app.get('/accounts/:id/balance', async (req, res, next) => {
  const id = req.params.id;
  try {
    const result = await withSpan('account.balance_fetch', { account_id: id }, async (span) => {
      const acc = getAccount(id);
      if (!acc) return null;
      const cached = cacheGetBalance(id);
      if (cached !== undefined) {
        span.setAttribute('cache.hit', true);
        balanceCounter.add(1, { cache: 'hit' });
        return { accountId: id, balance: cached, currency: acc.currency };
      }
      span.setAttribute('cache.hit', false);
      balanceCounter.add(1, { cache: 'miss' });
      const balance = await withSpan('db.query', { 'db.operation': 'SELECT', 'db.table': 'accounts' }, async () => {
        await sleep(25);
        return acc.balance;
      });
      cacheSetBalance(id, balance);
      return { accountId: id, balance, currency: acc.currency };
    });
    if (!result) {
      res.status(404).json({ error: 'account_not_found' });
      return;
    }
    res.json(result);
  } catch (err) {
    next(err);
  }
});

app.get('/accounts/:id/transactions', async (req, res, next) => {
  const id = req.params.id;
  try {
    const transactions = await withSpan('account.transactions', { account_id: id }, async () => {
      await withSpan('db.query', { 'db.operation': 'SELECT', 'db.table': 'transactions' }, () => sleep(25));
      return getTransactions(id, Number(req.query.limit ?? 20));
    });
    res.json({ transactions });
  } catch (err) {
    next(err);
  }
});

app.post('/accounts/:id/debit', async (req, res, next) => {
  const id = req.params.id;
  const { amount, description } = (req.body ?? {}) as { amount?: number; description?: string };
  try {
    const balance = await withSpan('account.debit', { account_id: id, amount: Number(amount) }, async () => {
      await withSpan('db.query', { 'db.operation': 'UPDATE', 'db.table': 'accounts' }, () => sleep(20));
      const b = adjustBalance(id, -Math.abs(Number(amount)), 'DEBIT', String(description ?? 'Transfer out'));
      cacheInvalidate(id);
      return b;
    });
    log.info('account debited', { account_id: id, amount });
    res.json({ accountId: id, balance });
  } catch (err) {
    next(err);
  }
});

app.post('/accounts/:id/credit', async (req, res, next) => {
  const id = req.params.id;
  const { amount, description } = (req.body ?? {}) as { amount?: number; description?: string };
  try {
    const balance = await withSpan('account.credit', { account_id: id, amount: Number(amount) }, async () => {
      await withSpan('db.query', { 'db.operation': 'UPDATE', 'db.table': 'accounts' }, () => sleep(20));
      const b = adjustBalance(id, Math.abs(Number(amount)), 'CREDIT', String(description ?? 'Transfer in'));
      cacheInvalidate(id);
      return b;
    });
    log.info('account credited', { account_id: id, amount });
    res.json({ accountId: id, balance });
  } catch (err) {
    next(err);
  }
});

startServer(app, port(8082));
