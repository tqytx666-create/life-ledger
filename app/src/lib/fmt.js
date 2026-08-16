export const CURRENCIES = ['CNY', 'HKD', 'USD']
export const SYMBOL = { CNY: '¥', HKD: 'HK$', USD: '$' }

export const ACCOUNT_TYPES = [
  { key: 'cash', label: '现金', icon: '💵' },
  { key: 'bank', label: '银行卡', icon: '🏦' },
  { key: 'stock', label: '股票', icon: '📈' },
  { key: 'fund', label: '基金', icon: '🧺' },
]

export const EXPENSE_CATS = ['餐饮', '买菜', '日用', '交通', '购物', '娱乐', '医疗', '教育', '人情', '给家人', '房贷月供', '提前还款', '房租', '保险', '订阅', '其他']
export const INCOME_CATS = ['工资', '奖金', '投资收益', '报销', '红包', '利息', '其他']

export function fmtMoney(n, currency = 'CNY', compact = false) {
  const v = Number(n) || 0
  const sym = SYMBOL[currency] || ''
  if (compact && Math.abs(v) >= 10000) {
    return sym + (v / 10000).toFixed(v % 10000 === 0 ? 0 : 1) + '万'
  }
  return sym + v.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export function fmtCNY(n, compact = false) {
  return fmtMoney(n, 'CNY', compact)
}

export function todayStr() {
  const d = new Date()
  const p = (x) => String(x).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

export function monthKey(dateStr) {
  return String(dateStr).slice(0, 7)
}

// '2026-08-17' → '8月17日'
export function fmtDate(s) {
  if (!s) return ''
  const [y, m, d] = String(s).slice(0, 10).split('-').map(Number)
  const now = new Date()
  const cur = now.getFullYear()
  return (y === cur ? '' : y + '年') + m + '月' + d + '日'
}
