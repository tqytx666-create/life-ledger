<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { store, toCNY } from '../lib/store'
import { fmtMoney, fmtCNY, fmtDate } from '../lib/fmt'
import { txSign as sign, txColor as color, isRepay } from '../lib/txkit'
import TxSheet from '../components/TxSheet.vue'

const route = useRoute()
const router = useRouter()

const kind = computed(() => (route.params.kind === 'income' ? 'income' : 'expense'))
const title = computed(() => (kind.value === 'income' ? '本月收入' : '本月支出'))

const now = new Date()
const thisMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
const monthSel = ref(thisMonth)

// 近半年内出现过流水的月份
const monthOptions = computed(() => {
  const s = new Set([thisMonth])
  for (const t of store.recentTx) s.add(String(t.occurred_at).slice(0, 7))
  return [...s].sort().reverse()
})

const accMap = computed(() => Object.fromEntries(store.accounts.map((a) => [a.id, a])))

function monthList(month) {
  return store.recentTx.filter((t) => t.type === kind.value && t.occurred_at.startsWith(month))
}
const list = computed(() => monthList(monthSel.value))
const cny = (t) => toCNY(Number(t.amount), accMap.value[t.account_id]?.currency || 'CNY')

const total = computed(() => list.value.reduce((s, t) => s + cny(t), 0))

// 对比上月同口径
const prevMonth = computed(() => {
  const [y, m] = monthSel.value.split('-').map(Number)
  return `${m === 1 ? y - 1 : y}-${String(m === 1 ? 12 : m - 1).padStart(2, '0')}`
})
const prevTotal = computed(() => monthList(prevMonth.value).reduce((s, t) => s + cny(t), 0))

// 日均(当月按已过天数)
const dailyAvg = computed(() => {
  const d = monthSel.value === thisMonth
    ? now.getDate()
    : new Date(Number(monthSel.value.slice(0, 4)), Number(monthSel.value.slice(5, 7)), 0).getDate()
  return total.value / Math.max(1, d)
})

// 分类拆解(全量,不截断)
const CAT_COLORS = ['#d8b25c', '#9aa7c7', '#c98d76', '#8fb5a0', '#a89bf0', '#c7788a', '#8d9d6f', '#b8b3a6', '#7f96b8', '#b0876f']
const catRows = computed(() => {
  const m = {}
  for (const t of list.value) {
    const k = t.category || '其他'
    m[k] ||= { cat: k, v: 0, n: 0 }
    m[k].v += cny(t)
    m[k].n += 1
  }
  const arr = Object.values(m).sort((a, b) => b.v - a.v)
  const max = Math.max(1, ...arr.map((x) => x.v))
  return arr.map((x, i) => ({ ...x, w: x.v / max, pct: total.value ? (x.v / total.value) * 100 : 0, color: CAT_COLORS[i % CAT_COLORS.length] }))
})

// 点分类过滤下方明细
const catFilter = ref('')
function toggleCat(c) { catFilter.value = catFilter.value === c ? '' : c }

const groups = computed(() => {
  let l = list.value
  if (catFilter.value) l = l.filter((t) => (t.category || '其他') === catFilter.value)
  const g = {}
  for (const t of l) (g[t.occurred_at] ||= []).push({ pair: false, id: t.id, t })
  return Object.entries(g).sort((a, b) => b[0].localeCompare(a[0]))
})

const detail = ref(null)
const barsOn = ref(false)
onMounted(() => setTimeout(() => { barsOn.value = true }, 250))
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center gap-3 mb-4">
      <h1 class="text-xl font-bold flex-1"><button class="mr-1" @click="router.back()">‹</button> {{ title }}分析</h1>
      <select v-model="monthSel" class="card px-2.5 py-1.5 text-[13px] outline-none" @change="catFilter = ''">
        <option v-for="m in monthOptions" :key="m" :value="m">{{ m.replace('-', '年') }}月</option>
      </select>
    </div>

    <!-- 总额卡 -->
    <div class="hero-card p-5 mb-4 rise" style="--d:0">
      <div class="hero-inner"></div><div class="hero-sheen"></div>
      <div class="text-xs" style="color: var(--ink-3)">{{ monthSel.replace('-', '年') }}月{{ kind === 'income' ? '总收入' : '总支出' }} · {{ list.length }}笔</div>
      <div class="tabular font-bold text-[34px] mt-1 gold-text">{{ fmtCNY(total, true) }}</div>
      <div class="flex gap-5 mt-2 text-[12px]" style="color: var(--ink-2)">
        <span>日均 <b class="tabular">{{ fmtCNY(dailyAvg, true) }}</b></span>
        <span v-if="prevTotal > 0">
          比上月
          <b class="tabular" :style="{ color: (total - prevTotal) * (kind === 'expense' ? 1 : -1) > 0 ? 'var(--danger)' : 'var(--good-text)' }">
            {{ total >= prevTotal ? '+' : '' }}{{ fmtCNY(total - prevTotal, true) }}
          </b>
        </span>
      </div>
    </div>

    <!-- 分类拆解 -->
    <div class="card p-4 mb-4 rise" :class="{ 'bars-on': barsOn }" style="--d:1">
      <div class="text-sm font-semibold mb-3">{{ kind === 'income' ? '钱从哪来' : '钱花在哪' }}<span v-if="catFilter" class="text-xs font-normal ml-2" style="color: var(--gold)">已筛:{{ catFilter }} ✕</span></div>
      <div v-if="!catRows.length" class="text-sm text-center py-4" style="color: var(--ink-3)">这个月还没有{{ kind === 'income' ? '收入' : '支出' }}记录</div>
      <button v-for="r in catRows" :key="r.cat" class="w-full text-left mb-2.5 last:mb-0 active:opacity-70"
        :style="catFilter && catFilter !== r.cat ? 'opacity:.35' : ''" @click="toggleCat(r.cat)">
        <div class="flex items-baseline justify-between text-[13px] mb-1">
          <span>{{ r.cat }} <span class="text-[11px]" style="color: var(--ink-3)">{{ r.n }}笔 · {{ r.pct.toFixed(1) }}%</span></span>
          <span class="tabular font-medium">{{ fmtCNY(r.v, true) }}</span>
        </div>
        <div class="h-2 rounded-full overflow-hidden" style="background: var(--grid)">
          <div class="cat-bar h-full" :style="{ width: (r.w * 100) + '%', background: r.color }"></div>
        </div>
      </button>
    </div>

    <!-- 明细 -->
    <div v-for="[date, items] in groups" :key="date" class="mb-4">
      <div class="text-xs mb-1.5 px-1" style="color: var(--ink-3)">{{ fmtDate(date) }}</div>
      <div class="card px-4">
        <div v-for="it in items" :key="it.id"
          class="flex items-center justify-between py-3 border-b last:border-0 cursor-pointer active:opacity-70"
          style="border-color: var(--hairline)" @click="detail = it">
          <div class="min-w-0 flex-1">
            <div class="text-[15px] truncate">
              {{ it.t.category }}
              <span v-if="it.t.type === 'expense' && isRepay(it.t)" class="repay-badge">还款</span>
            </div>
            <div class="text-xs truncate" style="color: var(--ink-3)">
              {{ accMap[it.t.account_id]?.name }}<span v-if="it.t.note"> · {{ it.t.note }}</span>
            </div>
          </div>
          <span class="tabular font-medium pl-2" :style="{ color: color(it.t) }">
            {{ sign(it.t) }}{{ fmtMoney(it.t.amount, accMap[it.t.account_id]?.currency) }}
          </span>
        </div>
      </div>
    </div>

    <TxSheet v-if="detail" :item="detail" :accMap="accMap" @close="detail = null" />
  </div>
</template>
