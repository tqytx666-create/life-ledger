<script setup>
import { computed, ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { store, netWorthCNY, liquidNetWorthCNY, toCNY } from '../lib/store'
import { fmtCNY, fmtMoney, ACCOUNT_TYPES } from '../lib/fmt'
import { useCountUp } from '../lib/anim'
import NetWorthChart from '../components/NetWorthChart.vue'
import CashflowChart from '../components/CashflowChart.vue'

const router = useRouter()
const thisMonth = new Date().toISOString().slice(0, 7)

const isSunkAcc = (a) => a.type === 'property' || a.type === 'vehicle'

// ===== 英雄区:可动净资产(不含房车) =====
const liquid = computed(() => liquidNetWorthCNY())
const fullNet = computed(() => netWorthCNY())
const liquidAssets = computed(() => {
  let t = 0
  for (const a of store.accounts) if (!a.archived && !isSunkAcc(a) && Number(a.balance) > 0) t += toCNY(a.balance, a.currency)
  return t
})
const liquidDebts = computed(() => {
  let t = 0
  for (const a of store.accounts) if (!a.archived && !isSunkAcc(a) && Number(a.balance) < 0) t += -toCNY(a.balance, a.currency)
  for (const l of store.loans) if (!l.archived && !l.asset_backed) t += toCNY(l.principal_remaining, l.currency)
  return t
})
const liquidAnim = useCountUp(liquid)

// ===== 本月四格:收入/支出/净结余/省下 =====
function monthSum(type, month) {
  const acc = Object.fromEntries(store.accounts.map((a) => [a.id, a]))
  return store.recentTx
    .filter((t) => t.type === type && t.occurred_at.startsWith(month))
    .reduce((s, t) => s + toCNY(t.amount, acc[t.account_id]?.currency || 'CNY'), 0)
}
const mIncome = computed(() => monthSum('income', thisMonth))
const mExpense = computed(() => monthSum('expense', thisMonth))
const mNet = computed(() => mIncome.value - mExpense.value)
const mSaved = computed(() => store.savings.filter((s) => s.saved_at.startsWith(thisMonth)).reduce((t, s) => t + Number(s.amount), 0))
const incomeAnim = useCountUp(mIncome)
const expenseAnim = useCountUp(mExpense)
const netMAnim = useCountUp(mNet)
const savedAnim = useCountUp(mSaved)

// ===== 高息歼灭战:网商贷 =====
const WSD_BASE = 793540.08          // 2026-08-17 启动基线
const WSD_CHEAP = 125000.06         // 其中 4.5% 低息部分
const wsd = computed(() => {
  const a = store.accounts.find((x) => x.name === '网商贷')
  const owed = a ? -Number(a.balance) : 0
  const expensive = Math.max(owed - WSD_CHEAP, 0)
  const monthlyInterest = expensive * 0.12 / 12 + Math.min(owed, WSD_CHEAP) * 0.045 / 12
  return { owed, expensive, monthlyInterest, progress: Math.max(0, 1 - owed / WSD_BASE) }
})

// ===== 未来7天 =====
const upcoming = computed(() => {
  const d0 = new Date().getDate()
  const events = []
  for (const r of store.recurring) {
    if (!r.active || r.period !== 'monthly') continue
    events.push({ day: r.run_day, label: r.name.replace(/\(.*?\)/g, ''), amount: Number(r.amount),
      kind: r.peer_account_id ? 'transfer' : r.flow === 'income' ? 'income' : 'expense' })
  }
  for (const l of store.loans) {
    if (l.archived || !(Number(l.principal_remaining) > 0)) continue
    events.push({ day: l.payment_day, label: l.name.replace(/\(.*?\)/g, ''), amount: Number(l.monthly_payment), kind: 'loan' })
  }
  return events
    .map((e) => ({ ...e, delta: (e.day - d0 + 31) % 31 }))
    .filter((e) => e.delta <= 7)
    .sort((a, b) => a.delta - b.delta)
})

// ===== 本月去向 =====
const CAT_COLORS = ['#2a78d6', '#1baf7a', '#eda100', '#008300', '#4a3aa7', '#e34948', '#e87ba4', '#eb6834']
const catBars = computed(() => {
  const acc = Object.fromEntries(store.accounts.map((a) => [a.id, a]))
  const m = {}
  for (const t of store.recentTx) {
    if (t.type !== 'expense' || !t.occurred_at.startsWith(thisMonth)) continue
    m[t.category] = (m[t.category] || 0) + toCNY(t.amount, acc[t.account_id]?.currency || 'CNY')
  }
  const arr = Object.entries(m).sort((a, b) => b[1] - a[1])
  const top = arr.slice(0, 6)
  const rest = arr.slice(6).reduce((s, x) => s + x[1], 0)
  if (rest > 0) top.push(['更多…', rest])
  const max = Math.max(1, ...top.map((x) => x[1]))
  return top.map(([cat, v], i) => ({ cat, v, w: v / max, color: CAT_COLORS[i % CAT_COLORS.length] }))
})
const barsOn = ref(false)
onMounted(() => setTimeout(() => { barsOn.value = true }, 350))

// ===== 资产分组(不含房车) =====
const GROUPS = [
  { key: 'liquid', name: '现金与银行卡', icon: '🏦', match: (a) => (a.type === 'cash' || a.type === 'bank') && Number(a.balance) >= 0 },
  { key: 'invest', name: '理财与基金', icon: '🧺', match: (a) => a.type === 'fund' },
  { key: 'stock', name: '证券', icon: '📈', match: (a) => a.type === 'stock' },
  { key: 'credit', name: '信用与欠款', icon: '💳', match: (a) => a.type === 'bank' && Number(a.balance) < 0 },
]
const grouped = computed(() => {
  const act = store.accounts.filter((a) => !a.archived && !isSunkAcc(a))
  return GROUPS.map((g) => {
    const list = act.filter(g.match)
    const total = list.reduce((s, a) => s + toCNY(a.balance, a.currency), 0)
    return { ...g, list, total }
  }).filter((g) => g.list.length)
})
const openGroup = ref('')

// ===== 负债(可动口径,不含房车贷) =====
const debtRows = computed(() => {
  const rows = []
  for (const l of store.loans) if (!l.archived && !l.asset_backed && Number(l.principal_remaining) > 0)
    rows.push({ name: l.name.replace(/\(.*?\)/g, ''), v: toCNY(l.principal_remaining, l.currency), sub: `月供 ${fmtMoney(l.monthly_payment, l.currency, true)} · ${l.payment_day}号` })
  for (const a of store.accounts) if (!a.archived && Number(a.balance) < 0)
    rows.push({ name: a.name.replace(/\(.*?\)/g, ''), v: -toCNY(a.balance, a.currency), sub: '' })
  rows.sort((a, b) => b.v - a.v)
  const max = Math.max(1, ...rows.map((r) => r.v))
  return rows.map((r) => ({ ...r, w: r.v / max }))
})

// ===== 沉淀资产(房车,折叠不计入) =====
const sunk = computed(() => {
  const assets = store.accounts.filter((a) => !a.archived && isSunkAcc(a))
  const loans = store.loans.filter((l) => !l.archived && l.asset_backed)
  const av = assets.reduce((s, a) => s + toCNY(a.balance, a.currency), 0)
  const lv = loans.reduce((s, l) => s + toCNY(l.principal_remaining, l.currency), 0)
  return { assets, loans, av, lv, net: av - lv }
})
const sunkOpen = ref(false)

// 走势用可动口径(旧快照无 liquid 时回落总口径)
const liquidSnapshots = computed(() =>
  store.snapshots.map((s) => ({ ...s, total_cny: s.liquid_cny ?? s.total_cny })))

const kindStyle = { income: 'color: var(--c-in)', loan: 'color: var(--c-out)', expense: 'color: var(--c-out)', transfer: 'color: var(--ink-2)' }
const kindSign = { income: '+', loan: '-', expense: '-', transfer: '⇄' }
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5" :class="{ 'bars-on': barsOn }">
    <!-- 英雄:可动净资产 -->
    <div class="hero-card p-5 mb-4 rise" style="--d:0">
      <div class="text-[13px] opacity-80">可动净资产 · 不含房车 · 目标:转正↗</div>
      <div class="text-[40px] leading-tight font-bold tracking-tight tabular">
        {{ fmtCNY(liquidAnim) }}
      </div>
      <div class="mt-3">
        <div class="flex justify-between text-xs opacity-85 mb-1.5">
          <span>可动资产 {{ fmtCNY(liquidAssets, true) }}</span>
          <span>要还的债 {{ fmtCNY(liquidDebts, true) }}</span>
        </div>
        <div class="h-2 rounded-full overflow-hidden" style="background: rgba(255,255,255,.25)">
          <div class="h-full rounded-full cat-bar" style="background: rgba(255,255,255,.9)"
            :style="{ transform: barsOn ? `scaleX(${Math.min(Math.max(liquidAssets / Math.max(liquidDebts, 1), 0.02), 1)})` : 'scaleX(0)' }"></div>
        </div>
        <div class="flex justify-between text-[11px] opacity-70 mt-1">
          <span>白条铺满 = 资产追平欠债</span>
          <span>含房车全口径 {{ fmtCNY(fullNet, true) }}</span>
        </div>
      </div>
    </div>

    <!-- 本月四格 -->
    <div class="grid grid-cols-2 gap-2.5 mb-4 rise" style="--d:1">
      <div class="card p-3">
        <div class="text-[11px] flex items-center gap-1.5" style="color: var(--ink-3)"><i class="w-1.5 h-1.5 rounded-full" style="background: var(--c-in)"></i>本月收入</div>
        <div class="tabular font-semibold mt-1 text-[17px]">{{ fmtCNY(incomeAnim, true) }}</div>
      </div>
      <div class="card p-3">
        <div class="text-[11px] flex items-center gap-1.5" style="color: var(--ink-3)"><i class="w-1.5 h-1.5 rounded-full" style="background: var(--c-out)"></i>本月支出</div>
        <div class="tabular font-semibold mt-1 text-[17px]">{{ fmtCNY(expenseAnim, true) }}</div>
      </div>
      <div class="card p-3" style="border-color: var(--c-net)">
        <div class="text-[11px] flex items-center gap-1.5" style="color: var(--ink-3)"><i class="w-1.5 h-1.5 rounded-full" style="background: var(--c-net)"></i>本月净结余 · 要越来越大</div>
        <div class="tabular font-bold mt-1 text-[17px]" :style="mNet >= 0 ? 'color: var(--c-in)' : 'color: var(--c-out)'">
          {{ mNet >= 0 ? '+' : '' }}{{ fmtCNY(netMAnim, true) }}</div>
      </div>
      <div class="card p-3">
        <div class="text-[11px] flex items-center gap-1.5" style="color: var(--ink-3)"><i class="w-1.5 h-1.5 rounded-full" style="background: var(--c-save)"></i>本月省下</div>
        <div class="tabular font-semibold mt-1 text-[17px]" style="color: var(--c-save)">{{ fmtCNY(savedAnim, true) }}</div>
      </div>
    </div>

    <!-- 高息歼灭战 -->
    <div class="card p-4 mb-4 rise" style="--d:2">
      <div class="flex items-center justify-between mb-1">
        <div class="text-sm font-medium" style="color: var(--ink-2)">🎯 高息歼灭战 · 网商贷12%</div>
        <div class="text-xs" style="color: var(--ink-3)">已消灭 {{ (wsd.progress * 100).toFixed(1) }}%</div>
      </div>
      <div class="flex items-baseline gap-2 mb-2">
        <span class="tabular font-bold text-[22px]" style="color: var(--danger)">{{ fmtCNY(wsd.owed, true) }}</span>
        <span class="text-xs" style="color: var(--ink-3)">每月白烧利息 {{ fmtCNY(wsd.monthlyInterest) }}</span>
      </div>
      <div class="h-2.5 rounded-full overflow-hidden" style="background: var(--plane)">
        <div class="h-full rounded-full cat-bar" style="background: linear-gradient(90deg, #1baf7a, #0ca30c)"
          :style="{ transform: barsOn ? `scaleX(${Math.max(wsd.progress, 0.015)})` : 'scaleX(0)' }"></div>
      </div>
      <div class="text-[11px] mt-1.5" style="color: var(--ink-3)">清零后每月多出 {{ fmtCNY(wsd.monthlyInterest, true) }} 现金流;先歼 12% 的 {{ fmtCNY(wsd.expensive, true) }},4.5% 那 12.5万 不急</div>
    </div>

    <!-- 未来7天 -->
    <div v-if="upcoming.length" class="card p-4 mb-4 rise" style="--d:3">
      <div class="text-sm font-medium mb-2.5" style="color: var(--ink-2)">⏰ 接下来 7 天</div>
      <div class="space-y-2">
        <div v-for="(e, i) in upcoming" :key="i" class="flex items-center justify-between text-sm">
          <span class="flex items-center gap-2">
            <span class="w-11 text-[12px] px-1.5 py-0.5 rounded-md text-center"
              :style="e.delta === 0 ? 'background: var(--danger); color:#fff' : 'background: var(--plane); color: var(--ink-3)'">
              {{ e.delta === 0 ? '今天' : e.day + '号' }}</span>
            <span style="color: var(--ink-2)">{{ e.label }}</span>
          </span>
          <span class="tabular font-medium" :style="kindStyle[e.kind]">{{ kindSign[e.kind] }}{{ fmtCNY(e.amount, true) }}</span>
        </div>
      </div>
    </div>

    <!-- 本月去向 -->
    <div v-if="catBars.length" class="card p-4 mb-4 rise" style="--d:4">
      <div class="text-sm font-medium mb-3" style="color: var(--ink-2)">本月花在哪</div>
      <div class="space-y-2.5">
        <div v-for="(b, i) in catBars" :key="b.cat">
          <div class="flex justify-between text-[13px] mb-1">
            <span style="color: var(--ink-2)">{{ b.cat }}</span>
            <span class="tabular" style="color: var(--ink-1)">{{ fmtCNY(b.v) }}</span>
          </div>
          <div class="cat-bar" :style="{ background: b.color, transform: barsOn ? `scaleX(${Math.max(b.w, 0.03)})` : 'scaleX(0)', transitionDelay: (i * 70) + 'ms' }"></div>
        </div>
      </div>
    </div>

    <!-- 可动净资产走势 -->
    <div class="card p-4 mb-4 rise" style="--d:5">
      <div class="text-sm font-medium mb-2" style="color: var(--ink-2)">可动净资产走势</div>
      <NetWorthChart :snapshots="liquidSnapshots" />
    </div>

    <!-- 月度收支 -->
    <div class="card p-4 mb-4 rise" style="--d:6">
      <div class="text-sm font-medium mb-2" style="color: var(--ink-2)">月度收支</div>
      <CashflowChart :cashflow="store.cashflow" />
    </div>

    <!-- 资产分组 -->
    <div class="card p-4 mb-4 rise" style="--d:7">
      <div class="flex items-center justify-between mb-1">
        <div class="text-sm font-medium" style="color: var(--ink-2)">可动资产</div>
        <button class="text-sm" style="color: var(--c-net)" @click="router.push('/accounts')">管理 ›</button>
      </div>
      <div v-for="g in grouped" :key="g.key" class="border-b last:border-0" style="border-color: var(--hairline)">
        <button class="w-full flex items-center justify-between py-3" @click="openGroup = openGroup === g.key ? '' : g.key">
          <span class="flex items-center gap-2 text-[15px]">{{ g.icon }} {{ g.name }}
            <span class="text-xs" style="color: var(--ink-3)">{{ g.list.length }}个</span></span>
          <span class="flex items-center gap-1.5 tabular font-medium" :style="g.total < 0 ? 'color: var(--danger)' : ''">
            {{ fmtCNY(g.total, true) }}<span class="text-xs" style="color: var(--ink-3)">{{ openGroup === g.key ? '▾' : '▸' }}</span></span>
        </button>
        <div v-if="openGroup === g.key" class="pb-2">
          <div v-for="a in g.list" :key="a.id" class="flex items-center justify-between py-1.5 pl-7 pr-1 text-sm">
            <span style="color: var(--ink-2)">{{ a.name }}</span>
            <span class="tabular" :style="Number(a.balance) < 0 ? 'color: var(--danger)' : ''">{{ fmtMoney(a.balance, a.currency) }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- 要还的债 -->
    <div v-if="debtRows.length" class="card p-4 mb-4 rise" style="--d:8">
      <div class="flex items-center justify-between mb-3">
        <div class="text-sm font-medium" style="color: var(--ink-2)">要还的债(不含房车贷)</div>
        <button class="text-sm" style="color: var(--c-net)" @click="router.push('/loans')">贷款 ›</button>
      </div>
      <div class="space-y-3">
        <div v-for="(r, i) in debtRows" :key="r.name">
          <div class="flex justify-between text-[13px] mb-1">
            <span style="color: var(--ink-2)">{{ r.name }}<span v-if="r.sub" class="text-[11px] ml-1.5" style="color: var(--ink-3)">{{ r.sub }}</span></span>
            <span class="tabular" style="color: var(--danger)">{{ fmtCNY(r.v, true) }}</span>
          </div>
          <div class="cat-bar" style="background: var(--danger); opacity: .8"
            :style="{ transform: barsOn ? `scaleX(${Math.max(r.w, 0.03)})` : 'scaleX(0)', transitionDelay: (i * 60) + 'ms' }"></div>
        </div>
      </div>
    </div>

    <!-- 沉淀资产(房车,不计入) -->
    <div v-if="sunk.assets.length" class="card p-4 mb-4 rise" style="--d:9; opacity: .92">
      <button class="w-full flex items-center justify-between" @click="sunkOpen = !sunkOpen">
        <span class="text-sm font-medium" style="color: var(--ink-3)">🧊 沉淀资产 · 房车(不计入上方)</span>
        <span class="tabular text-sm" style="color: var(--ink-3)">净值约 {{ fmtCNY(sunk.net, true) }} {{ sunkOpen ? '▾' : '▸' }}</span>
      </button>
      <div v-if="sunkOpen" class="mt-3 pt-3 border-t space-y-1.5 text-sm" style="border-color: var(--hairline)">
        <div v-for="a in sunk.assets" :key="a.id" class="flex justify-between">
          <span style="color: var(--ink-2)">{{ a.name }}</span>
          <span class="tabular">{{ fmtCNY(Number(a.balance), true) }}</span>
        </div>
        <div v-for="l in sunk.loans" :key="l.id" class="flex justify-between">
          <span style="color: var(--ink-2)">{{ l.name.replace(/\(.*?\)/g, '') }}</span>
          <span class="tabular" style="color: var(--danger)">-{{ fmtCNY(Number(l.principal_remaining), true) }}</span>
        </div>
        <div class="text-[11px] pt-1" style="color: var(--ink-3)">估值仅供参考,等可动盘子转正后再回头调理它们</div>
      </div>
    </div>
  </div>
</template>
