<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, toCNY } from '../lib/store'
import { fmtMoney, fmtCNY, fmtDate } from '../lib/fmt'
import { txSign as sign, txColor as color, isRepay, isDebtExpense } from '../lib/txkit'
import TxSheet from '../components/TxSheet.vue'

const route = useRoute()
const router = useRouter()

const kind = ref(route.params.kind === 'income' ? 'income' : 'expense')
const title = computed(() => (kind.value === 'income' ? '收入' : '支出'))

const now = new Date()
const thisMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
const monthSel = ref(/^\d{4}-\d{2}$/.test(route.query.m || '') ? route.query.m : thisMonth)

// 可选月份:近18个月(老月份按需单独拉取)
const monthOptions = computed(() => {
  const opts = []
  for (let i = 0; i < 18; i++) {
    const m = new Date(now.getFullYear(), now.getMonth() - i, 1)
    opts.push(`${m.getFullYear()}-${String(m.getMonth() + 1).padStart(2, '0')}`)
  }
  return opts
})

// recentTx 覆盖近13个月,更早的月份(含上月对比)按需拉
const coveredFrom = computed(() => {
  const d = new Date(now.getFullYear(), now.getMonth() - 12, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
})
const catFilter = ref('')
const prevMonth = computed(() => {
  const [y, m] = monthSel.value.split('-').map(Number)
  return `${m === 1 ? y - 1 : y}-${String(m === 1 ? 12 : m - 1).padStart(2, '0')}`
})

const extTx = ref([])
const extLoading = ref(false)
watch([monthSel, kind], async () => {
  catFilter.value = ''
  if (prevMonth.value > coveredFrom.value) { extTx.value = []; return }
  extLoading.value = true
  try {
    const [y, mo] = prevMonth.value.split('-').map(Number)
    const [y2, mo2] = monthSel.value.split('-').map(Number)
    const to = `${mo2 === 12 ? y2 + 1 : y2}-${String(mo2 === 12 ? 1 : mo2 + 1).padStart(2, '0')}-01`
    const { data, error } = await supabase.from('transactions').select('*')
      .gte('occurred_at', `${y}-${String(mo).padStart(2, '0')}-01`).lt('occurred_at', to)
      .order('occurred_at', { ascending: false }).limit(2000)
    if (error) throw error
    extTx.value = data || []
  } catch (e) { console.warn(e.message) } finally { extLoading.value = false }
}, { immediate: true })

const accMap = computed(() => Object.fromEntries(store.accounts.map((a) => [a.id, a])))

const scope = ref('daily')  // daily=日常 | debt=还贷 | all=全部(仅支出侧有意义)
function monthList(month) {
  const src = month > coveredFrom.value ? store.recentTx : extTx.value
  let l = src.filter((t) => t.type === kind.value && t.occurred_at.startsWith(month))
  if (kind.value === 'expense' && scope.value === 'daily') l = l.filter((t) => !isDebtExpense(t))
  else if (kind.value === 'expense' && scope.value === 'debt') l = l.filter((t) => isDebtExpense(t))
  return l
}
const list = computed(() => monthList(monthSel.value))
const cny = (t) => toCNY(Number(t.amount), accMap.value[t.account_id]?.currency || 'CNY')

const total = computed(() => list.value.reduce((s, t) => s + cny(t), 0))

// 对比上月同口径
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
      <select v-model="monthSel" class="card px-2.5 py-1.5 text-[13px] outline-none">
        <option v-for="m in monthOptions" :key="m" :value="m">{{ m.replace('-', '年') }}月</option>
      </select>
    </div>

    <!-- 支出/收入切换 + 还贷口径 -->
    <div class="flex gap-2 mb-3 flex-wrap">
      <button v-for="k in [['expense', '支出'], ['income', '收入']]" :key="k[0]"
        class="px-3.5 py-1.5 rounded-full text-[13px] border"
        :style="kind === k[0] ? 'background: var(--c-net); color:#fff; border-color:transparent' : 'border-color: var(--hairline); color: var(--ink-2)'"
        @click="kind = k[0]">{{ k[1] }}</button>
      <template v-if="kind === 'expense'">
        <span class="w-px self-stretch my-1" style="background: var(--hairline)"></span>
        <button v-for="s in [['daily', '日常'], ['debt', '还贷'], ['all', '全部']]" :key="s[0]"
          class="px-3 py-1.5 rounded-full text-[12px] border"
          :style="scope === s[0] ? 'border-color: var(--gold); color: var(--gold)' : 'border-color: var(--hairline); color: var(--ink-3)'"
          @click="scope = s[0]; catFilter = ''">{{ s[1] }}</button>
      </template>
      <span v-if="extLoading" class="text-xs self-center" style="color: var(--ink-3)">拉取历史月份…</span>
    </div>

    <!-- 总额卡 -->
    <div class="hero-card p-5 mb-4 rise" style="--d:0">
      <div class="hero-inner"></div><div class="hero-sheen"></div>
      <div class="text-xs" style="color: var(--ink-3)">{{ monthSel.replace('-', '年') }}月{{ kind === 'income' ? '总收入' : { daily: '日常开支', debt: '还贷支出', all: '总支出(含还贷)' }[scope] }} · {{ list.length }}笔</div>
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
