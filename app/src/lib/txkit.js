// 流水展示共用工具:符号/颜色/类型名/还款识别/转账合并
export function txSign(t) {
  if (t.type === 'income' || t.type === 'transfer_in') return '+'
  if (t.type === 'adjust') return t.category === '-' ? '-' : '+'
  return '-'
}

export function isRepay(t) {
  return /还|贷|月供|利息/.test(t.category || '')
}

// 还贷口径:这些支出是"还债的钱",不算日常消费(本金是负债转移,利息是财务费用)
export const DEBT_CATS = ['房贷月供', '车贷', '提前还款', '利息', '还网商贷', '还款']
export function isDebtExpense(t) {
  return t.type === 'expense' && DEBT_CATS.includes(t.category)
}

export function txColor(t) {
  const s = txSign(t)
  if (t.type.startsWith('transfer')) return 'var(--ink-2)'
  if (t.type === 'expense' && isRepay(t)) return 'var(--gold)'
  return s === '+' ? 'var(--c-in)' : 'var(--ink-1)'
}

export function typeName(t) {
  return { income: '', expense: '', transfer_out: '转出', transfer_in: '转入', adjust: '校准' }[t.type] || ''
}

// 转账两条腿合并成一项(同 transfer_gid);缺腿保持单行
export function mergePairs(list) {
  const byGid = {}
  for (const t of list) if (t.transfer_gid) (byGid[t.transfer_gid] ||= []).push(t)
  const seen = new Set()
  const items = []
  for (const t of list) {
    if (t.transfer_gid && byGid[t.transfer_gid].length === 2) {
      if (seen.has(t.transfer_gid)) continue
      seen.add(t.transfer_gid)
      const pair = byGid[t.transfer_gid]
      const out = pair.find((x) => x.type === 'transfer_out') || pair[0]
      const tin = pair.find((x) => x.type === 'transfer_in') || pair[1]
      items.push({ pair: true, id: t.transfer_gid, out, tin, t: out, occurred_at: out.occurred_at })
    } else {
      items.push({ pair: false, id: t.id, t, occurred_at: t.occurred_at })
    }
  }
  return items
}
