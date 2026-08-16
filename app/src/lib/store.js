import { reactive } from 'vue'
import { supabase } from './supabase'

// 全局状态:登录后 loadAll 一次拉齐,写操作走 RPC 后局部刷新
export const store = reactive({
  session: null,
  ready: false,       // 首次数据加载完成
  loading: false,
  error: '',

  accounts: [],
  members: [],
  batches: [],
  batchExpenses: [],
  loans: [],
  recurring: [],
  fx: { CNY: 1, HKD: 0.92, USD: 7.12 },
  snapshots: [],      // 净资产走势
  recentTx: [],       // 最近流水(展示)
  cashflow: [],       // [{month, income, expense}] 折CNY
  savings: [],        // 省钱记录
})

export function toCNY(amount, currency) {
  return (Number(amount) || 0) * (store.fx[currency] ?? 1)
}

// 净资产(折CNY): 资产账户 - loan 型账户 - 贷款剩余本金
export function netWorthCNY() {
  let t = 0
  for (const a of store.accounts) {
    if (a.archived) continue
    t += (a.type === 'loan' ? -1 : 1) * toCNY(a.balance, a.currency)
  }
  for (const l of store.loans) {
    if (l.archived) continue
    t -= toCNY(l.principal_remaining, l.currency)
  }
  return t
}

export function batchSpent(batchId) {
  return store.batchExpenses
    .filter((e) => e.batch_id === batchId)
    .reduce((s, e) => s + Number(e.amount), 0)
}

async function q(promise, label) {
  const { data, error } = await promise
  if (error) throw new Error(label + ': ' + error.message)
  return data || []
}

export async function loadAll() {
  store.loading = true
  store.error = ''
  try {
    const sixMonthsAgo = new Date(Date.now() - 200 * 864e5).toISOString().slice(0, 10)
    const [accounts, members, batches, bexp, loans, recurring, fx, snaps, tx, savings] = await Promise.all([
      q(supabase.from('accounts').select('*').order('sort').order('created_at'), '账户'),
      q(supabase.from('members').select('*').order('sort').order('created_at'), '成员'),
      q(supabase.from('batches').select('*').order('given_at', { ascending: false }), '批次'),
      q(supabase.from('batch_expenses').select('*').order('spent_at', { ascending: false }).limit(2000), '批次花销'),
      q(supabase.from('loans').select('*').order('created_at'), '贷款'),
      q(supabase.from('recurring').select('*').order('created_at'), '固定支出'),
      q(supabase.from('fx_rates').select('*'), '汇率'),
      q(supabase.from('net_worth_snapshots').select('*').gte('snap_date', sixMonthsAgo).order('snap_date'), '快照'),
      q(supabase.from('transactions').select('*').gte('occurred_at', sixMonthsAgo).order('occurred_at', { ascending: false }).order('created_at', { ascending: false }).limit(1000), '流水'),
      q(supabase.from('savings').select('*').gte('saved_at', sixMonthsAgo).order('saved_at', { ascending: false }).limit(1000), '省钱'),
    ])
    store.accounts = accounts
    store.members = members
    store.batches = batches
    store.batchExpenses = bexp
    store.loans = loans
    store.recurring = recurring
    for (const r of fx) store.fx[r.currency] = Number(r.to_cny)
    store.snapshots = snaps
    store.recentTx = tx
    store.savings = savings
    rebuildCashflow()
    store.ready = true
  } catch (e) {
    store.error = e.message
  } finally {
    store.loading = false
  }
}

function rebuildCashflow() {
  const byMonth = {}
  const acc = Object.fromEntries(store.accounts.map((a) => [a.id, a]))
  for (const t of store.recentTx) {
    if (t.type !== 'income' && t.type !== 'expense') continue // 转账/校准不算收支
    const m = String(t.occurred_at).slice(0, 7)
    byMonth[m] ||= { month: m, income: 0, expense: 0 }
    const cur = acc[t.account_id]?.currency || 'CNY'
    byMonth[m][t.type === 'income' ? 'income' : 'expense'] += toCNY(t.amount, cur)
  }
  store.cashflow = Object.values(byMonth).sort((a, b) => a.month.localeCompare(b.month)).slice(-6)
}

// 登录后开机例程:结算到期月供/固定支出 → 若有入账则整体重拉
export async function bootSettle() {
  try {
    const { data, error } = await supabase.rpc('settle_due')
    if (error) throw error
    if (data && (data.loan_payments > 0 || data.recurring_charged > 0)) {
      await loadAll()
      return data
    }
  } catch (e) {
    // 结算失败不阻塞使用,下次打开重试(游标幂等)
    console.warn('settle_due:', e.message)
  }
  return null
}

export async function recordTx(payload) {
  const { data, error } = await supabase.rpc('record_tx', payload)
  if (error) throw new Error(error.message)
  await loadAll()
  try { await supabase.rpc('snapshot_net_worth') } catch { /* 快照失败不影响记账 */ }
  return data
}

export async function deleteTx(id) {
  const { data, error } = await supabase.rpc('delete_tx', { p_tx_id: id })
  if (error) throw new Error(error.message)
  await loadAll()
  return data
}
