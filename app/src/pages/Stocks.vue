<script setup>
// 股票详情:每只持仓的现价/成本/盈亏,按账户分组
import { computed, ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { store } from '../lib/store'
import Icon from '../components/Icon.vue'
import { fmtCNY } from '../lib/fmt'

const router = useRouter()
const barsOn = ref(false)
onMounted(() => setTimeout(() => { barsOn.value = true }, 200))

const sec = computed(() => store.secDaily)
const accName = (id) => store.accounts.find((a) => a.id === id)?.name || ''

const byAccount = computed(() => {
  const m = {}
  for (const h of store.holdings) {
    const key = h.account_id
    ;(m[key] ||= { name: accName(key), rows: [], total: 0 }).rows.push(h)
    m[key].total += Number(h.value)
  }
  // 排序:持仓在前,现金次之,负债最后
  const order = { stock: 0, fund: 1, cash: 2, debt: 3 }
  for (const k in m) m[k].rows.sort((a, b) => (order[a.kind] - order[b.kind]) || (Number(b.value) - Number(a.value)))
  return Object.values(m).sort((a, b) => b.total - a.total)
})
const total = computed(() => byAccount.value.reduce((s, g) => s + g.total, 0))

function pnl(h) {
  if (h.kind !== 'stock' || !Number(h.cost)) return null
  const diff = (Number(h.price) - Number(h.cost)) * Number(h.qty)
  const pct = (Number(h.price) / Number(h.cost) - 1) * 100
  return { diff, pct }
}
const totalPnl = computed(() => {
  let t = 0
  for (const h of store.holdings) { const p = pnl(h); if (p) t += p.diff }
  return t
})
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5" :class="{ 'bars-on': barsOn }">
    <h1 class="text-xl font-bold mb-4 rise" style="--d:0"><button class="mr-1" @click="router.back()">‹</button> 📈 股票持仓</h1>

    <div class="hero-card p-5 mb-4 rise" style="--d:0">
      <div class="hero-inner"></div>
      <div class="hero-sheen"></div>
      <span class="hero-mark"><Icon name="spark" :size="110" /></span>
      <div class="text-[13px] opacity-80">证券总值(两户合计,含现金与融资)</div>
      <div class="text-[36px] leading-tight font-bold tracking-tight tabular">{{ fmtCNY(total) }}</div>
      <div class="flex gap-4 mt-1.5 text-[13px]">
        <span v-if="sec" class="tabular">当日 {{ Number(sec.day_pnl) >= 0 ? '+' : '' }}{{ fmtCNY(Number(sec.day_pnl), true) }} ({{ Number(sec.day_pct) >= 0 ? '+' : '' }}{{ Number(sec.day_pct).toFixed(2) }}%)</span>
        <span class="tabular opacity-85">持仓浮动 {{ totalPnl >= 0 ? '+' : '' }}{{ fmtCNY(totalPnl, true) }}</span>
      </div>
      <div v-if="sec" class="text-[11px] opacity-70 mt-1">{{ String(sec.snap_date).slice(5).replace('-', '/') }} 收盘 · 每个交易日16:35自动刷新</div>
    </div>

    <div v-for="(g, gi) in byAccount" :key="g.name" class="card p-4 mb-4 rise" :style="`--d:${gi + 1}`">
      <div class="flex items-center justify-between mb-2">
        <div class="text-sm font-medium" style="color: var(--ink-2)">{{ g.name.replace('东方财富-', '') }}</div>
        <div class="tabular text-sm font-medium">净值 {{ fmtCNY(g.total, true) }}</div>
      </div>
      <div v-for="h in g.rows" :key="h.id" class="py-2.5 border-b last:border-0" style="border-color: var(--hairline)">
        <template v-if="h.kind === 'stock' || h.kind === 'fund'">
          <div class="flex justify-between items-baseline">
            <span class="text-[15px]">{{ h.name }} <span class="text-[11px]" style="color: var(--ink-3)">{{ h.code }}</span></span>
            <span class="tabular font-semibold">{{ fmtCNY(Number(h.value), true) }}</span>
          </div>
          <div class="flex justify-between text-[12px] mt-0.5" style="color: var(--ink-3)">
            <span class="tabular">{{ Number(h.qty).toLocaleString() }}股 · 现价{{ Number(h.price).toFixed(2) }}<template v-if="Number(h.cost)"> · 成本{{ Number(h.cost).toFixed(2) }}</template></span>
            <span v-if="pnl(h)" class="tabular font-medium"
              :style="pnl(h).diff >= 0 ? 'color: var(--c-in)' : 'color: var(--c-out)'">
              {{ pnl(h).diff >= 0 ? '+' : '' }}{{ fmtCNY(pnl(h).diff, true) }} ({{ pnl(h).pct >= 0 ? '+' : '' }}{{ pnl(h).pct.toFixed(1) }}%)</span>
          </div>
        </template>
        <template v-else>
          <div class="flex justify-between text-[13px]">
            <span style="color: var(--ink-3)">{{ h.kind === 'debt' ? '⚠️ ' : '' }}{{ h.name }}</span>
            <span class="tabular" :style="Number(h.value) < 0 ? 'color: var(--danger)' : 'color: var(--ink-2)'">{{ fmtCNY(Number(h.value), true) }}</span>
          </div>
        </template>
      </div>
    </div>

    <p class="text-center text-[11px] mb-4" style="color: var(--ink-3)">有买卖跟我说一声,我更新持仓,当天行情照常算</p>
  </div>
</template>
