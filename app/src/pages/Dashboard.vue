<script setup>
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { store, netWorthCNY, toCNY } from '../lib/store'
import { fmtCNY, fmtMoney, SYMBOL, ACCOUNT_TYPES } from '../lib/fmt'
import NetWorthChart from '../components/NetWorthChart.vue'
import CashflowChart from '../components/CashflowChart.vue'

const router = useRouter()
const net = computed(() => netWorthCNY())

// 各币种资产小计(不含负债)
const byCurrency = computed(() => {
  const m = {}
  for (const a of store.accounts) {
    if (a.archived || a.type === 'loan') continue
    m[a.currency] = (m[a.currency] || 0) + Number(a.balance)
  }
  return Object.entries(m).map(([c, v]) => ({ c, v }))
})

const totalDebt = computed(() => {
  let d = 0
  for (const a of store.accounts) if (!a.archived && a.type === 'loan') d += toCNY(a.balance, a.currency)
  for (const l of store.loans) if (!l.archived) d += toCNY(l.principal_remaining, l.currency)
  return d
})

const typeLabel = Object.fromEntries(ACCOUNT_TYPES.map((t) => [t.key, t]))
const activeAccounts = computed(() => store.accounts.filter((a) => !a.archived))

// 省钱账:本月/上月总额 + 本月按方式细分
const thisMonth = new Date().toISOString().slice(0, 7)
const lastMonth = new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().slice(0, 7)
const savedThisMonth = computed(() => store.savings.filter((s) => s.saved_at.startsWith(thisMonth)).reduce((t, s) => t + Number(s.amount), 0))
const savedLastMonth = computed(() => store.savings.filter((s) => s.saved_at.startsWith(lastMonth)).reduce((t, s) => t + Number(s.amount), 0))
const savedByWay = computed(() => {
  const m = {}
  for (const s of store.savings.filter((x) => x.saved_at.startsWith(thisMonth))) {
    m[s.way] = (m[s.way] || 0) + Number(s.amount)
  }
  return Object.entries(m).sort((a, b) => b[1] - a[1])
})
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <!-- 英雄数字:净资产 -->
    <div class="mb-5">
      <div class="text-sm" style="color: var(--ink-3)">净资产(折人民币)</div>
      <div class="text-5xl font-semibold mt-1 tracking-tight">{{ fmtCNY(net) }}</div>
      <div class="flex gap-3 mt-2 text-sm flex-wrap" style="color: var(--ink-2)">
        <span v-for="x in byCurrency" :key="x.c" class="tabular">{{ SYMBOL[x.c] }}{{ x.v.toLocaleString('zh-CN', { maximumFractionDigits: 0 }) }}</span>
        <span v-if="totalDebt > 0" class="tabular" style="color: var(--c-out)">负债 {{ fmtCNY(totalDebt, true) }}</span>
      </div>
    </div>

    <div class="card p-4 mb-4">
      <div class="text-sm font-medium mb-2" style="color: var(--ink-2)">净资产走势</div>
      <NetWorthChart :snapshots="store.snapshots" />
    </div>

    <div class="card p-4 mb-4">
      <div class="text-sm font-medium mb-2" style="color: var(--ink-2)">月度收支</div>
      <CashflowChart :cashflow="store.cashflow" />
    </div>

    <!-- 省钱账 -->
    <div v-if="savedThisMonth > 0 || savedLastMonth > 0" class="card p-4 mb-4">
      <div class="flex items-baseline justify-between mb-1">
        <div class="text-sm font-medium" style="color: var(--ink-2)">本月省下</div>
        <div v-if="savedLastMonth > 0" class="text-xs" style="color: var(--ink-3)">上月 {{ fmtCNY(savedLastMonth, true) }}</div>
      </div>
      <div class="text-3xl font-semibold mb-2" style="color: var(--c-save)">
        <span style="color: var(--ink-1)">{{ fmtCNY(savedThisMonth) }}</span>
      </div>
      <div v-for="[way, amt] in savedByWay" :key="way" class="flex items-center justify-between py-1 text-sm">
        <span class="flex items-center gap-2" style="color: var(--ink-2)">
          <i class="w-2 h-2 rounded-full inline-block" style="background: var(--c-save)"></i>{{ way }}</span>
        <span class="tabular">{{ fmtCNY(amt) }}</span>
      </div>
    </div>

    <!-- 账户列表 -->
    <div class="card p-4 mb-4">
      <div class="flex items-center justify-between mb-2">
        <div class="text-sm font-medium" style="color: var(--ink-2)">账户</div>
        <button class="text-sm" style="color: var(--c-net)" @click="router.push('/accounts')">管理 ›</button>
      </div>
      <div v-if="!activeAccounts.length" class="py-6 text-center text-sm" style="color: var(--ink-3)">
        还没有账户,先去「管理」加一个
      </div>
      <div v-for="a in activeAccounts" :key="a.id"
        class="flex items-center justify-between py-2.5 border-b last:border-0" style="border-color: var(--hairline)">
        <div class="flex items-center gap-2.5">
          <span>{{ typeLabel[a.type]?.icon || '💼' }}</span>
          <div>
            <div class="text-[15px]">{{ a.name }}</div>
            <div class="text-xs" style="color: var(--ink-3)">{{ typeLabel[a.type]?.label }} · {{ a.currency }}</div>
          </div>
        </div>
        <div class="tabular font-medium" :style="a.type === 'loan' ? 'color: var(--c-out)' : ''">
          {{ a.type === 'loan' ? '-' : '' }}{{ fmtMoney(a.balance, a.currency) }}
        </div>
      </div>
    </div>

    <!-- 贷款速览 -->
    <div v-if="store.loans.filter((l) => !l.archived).length" class="card p-4 mb-4">
      <div class="flex items-center justify-between mb-2">
        <div class="text-sm font-medium" style="color: var(--ink-2)">按揭贷款</div>
        <button class="text-sm" style="color: var(--c-net)" @click="router.push('/loans')">详情 ›</button>
      </div>
      <div v-for="l in store.loans.filter((x) => !x.archived)" :key="l.id"
        class="flex items-center justify-between py-2">
        <div>
          <div class="text-[15px]">{{ l.name }}</div>
          <div class="text-xs" style="color: var(--ink-3)">每月{{ l.payment_day }}号 · 月供 {{ fmtMoney(l.monthly_payment, l.currency) }}</div>
        </div>
        <div class="tabular font-medium" style="color: var(--c-out)">剩 {{ fmtMoney(l.principal_remaining, l.currency, true) }}</div>
      </div>
    </div>
  </div>
</template>
