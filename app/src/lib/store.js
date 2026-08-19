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
  saveGoals: [],      // 省钱作战目标
  secDaily: null,     // 最近一次证券行情快照
  holdings: [],       // 证券持仓明细
  advicePrefs: {},    // 被隐藏的建议 key
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

// 可动净资产:剔除房/车及其绑定贷款,只看每月能操作的盘子
export function liquidNetWorthCNY() {
  let t = 0
  for (const a of store.accounts) {
    if (a.archived || a.type === 'property' || a.type === 'vehicle') continue
    t += (a.type === 'loan' ? -1 : 1) * toCNY(a.balance, a.currency)
  }
  for (const l of store.loans) {
    if (l.archived || l.asset_backed) continue
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
    const uid = store.session?.user?.id
    const sixMonthsAgo = new Date(Date.now() - 200 * 864e5).toISOString().slice(0, 10)
    const txWindow = new Date(Date.now() - 400 * 864e5).toISOString().slice(0, 10)  // 流水拉13个月,支撑收支图回看
    const [accounts, members, batches, bexp, loans, recurring, fx, snaps, tx, savings, saveGoals, secDaily, holdings, advicePrefs] = await Promise.all([
      q(supabase.from('accounts').select('*').eq('owner', uid).order('sort').order('created_at'), '账户'),
      q(supabase.from('members').select('*').eq('owner', uid).order('sort').order('created_at'), '成员'),
      q(supabase.from('batches').select('*').eq('owner', uid).order('given_at', { ascending: false }), '批次'),
      q(supabase.from('batch_expenses').select('*').eq('owner', uid).order('spent_at', { ascending: false }).limit(2000), '批次花销'),
      q(supabase.from('loans').select('*').eq('owner', uid).order('created_at'), '贷款'),
      q(supabase.from('recurring').select('*').eq('owner', uid).order('created_at'), '固定支出'),
      q(supabase.from('fx_rates').select('*'), '汇率'),
      q(supabase.from('net_worth_snapshots').select('*').eq('owner', uid).gte('snap_date', sixMonthsAgo).order('snap_date'), '快照'),
      q(supabase.from('transactions').select('*').eq('owner', uid).gte('occurred_at', txWindow).order('occurred_at', { ascending: false }).order('created_at', { ascending: false }).limit(4000), '流水'),
      q(supabase.from('savings').select('*').eq('owner', uid).gte('saved_at', sixMonthsAgo).order('saved_at', { ascending: false }).limit(1000), '省钱'),
      q(supabase.from('save_goals').select('*').eq('owner', uid).eq('active', true).order('sort'), '省钱目标'),
      q(supabase.from('sec_daily').select('*').eq('owner', uid).order('snap_date', { ascending: false }).limit(1), '行情'),
      q(supabase.from('holdings').select('*').eq('owner', uid).order('value', { ascending: false }), '持仓'),
      q(supabase.from('advice_prefs').select('*').eq('owner', uid), '建议偏好'),
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
    store.saveGoals = saveGoals
    store.secDaily = secDaily[0] || null
    store.holdings = holdings
    store.advicePrefs = Object.fromEntries(advicePrefs.map((r) => [r.key, r]))
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
  store.cashflow = Object.values(byMonth).sort((a, b) => a.month.localeCompare(b.month)).slice(-13)
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

// 建议偏好:点✕隐藏,管家记住口味
export function isAdviceHidden(key) {
  return !!store.advicePrefs[key]?.muted
}
export async function hideAdvice(key) {
  const prev = store.advicePrefs[key]
  const row = { key, hides: (prev?.hides || 0) + 1, muted: true, updated_at: new Date().toISOString() }
  store.advicePrefs = { ...store.advicePrefs, [key]: row }
  await supabase.from('advice_prefs').upsert({ ...row, owner: store.session?.user?.id }, { onConflict: 'owner,key' })
}
