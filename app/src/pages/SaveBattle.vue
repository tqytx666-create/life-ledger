<script setup>
// 省钱作战:分领域上限目标 + 省下账,让"该省哪些钱"一眼可见
import { computed, ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { store, toCNY } from '../lib/store'
import { fmtCNY, fmtDate } from '../lib/fmt'

const router = useRouter()
const thisMonth = new Date().toISOString().slice(0, 7)
const lastMonth = new Date(new Date().setMonth(new Date().getMonth() - 1)).toISOString().slice(0, 7)
const dayOfMonth = new Date().getDate()
const daysInMonth = new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).getDate()

const accMap = computed(() => Object.fromEntries(store.accounts.map((a) => [a.id, a])))

function goalSpent(g, month) {
  const cats = Array.isArray(g.cats) ? g.cats : JSON.parse(g.cats || '[]')
  let t = 0
  for (const x of store.recentTx) {
    if (x.type !== 'expense' || !x.occurred_at.startsWith(month)) continue
    const hitCat = cats.includes(x.category)
    const hitKw = g.kw && (x.note || '').includes(g.kw)
    if (hitCat || hitKw) t += toCNY(x.amount, accMap.value[x.account_id]?.currency || 'CNY')
  }
  return t
}

const goals = computed(() => store.saveGoals.map((g) => {
  const spent = goalSpent(g, thisMonth)
  const prev = goalSpent(g, lastMonth)
  const cap = Number(g.cap)
  const pct = cap > 0 ? spent / cap : 0
  // 时间进度参考:月过半但只花三成 = 优秀
  return { ...g, spent, prev, cap, pct,
    left: Math.max(cap - spent, 0),
    over: spent > cap,
    pace: dayOfMonth / daysInMonth }
}))

const totalCap = computed(() => goals.value.reduce((s, g) => s + g.cap, 0))
const totalSpent = computed(() => goals.value.reduce((s, g) => s + g.spent, 0))

// 省下账
const savedThisMonth = computed(() => store.savings.filter((s) => s.saved_at.startsWith(thisMonth)).reduce((t, s) => t + Number(s.amount), 0))
const savedByWay = computed(() => {
  const m = {}
  for (const s of store.savings.filter((x) => x.saved_at.startsWith(thisMonth))) m[s.way] = (m[s.way] || 0) + Number(s.amount)
  return Object.entries(m).sort((a, b) => b[1] - a[1])
})
const recentSavings = computed(() => store.savings.slice(0, 8))

const barsOn = ref(false)
onMounted(() => setTimeout(() => { barsOn.value = true }, 250))

function barColor(g) {
  if (g.over) return 'var(--danger)'
  if (g.pct > g.pace + 0.15) return '#eda100'   // 花钱速度超过时间进度 → 黄色预警
  return '#1baf7a'
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5" :class="{ 'bars-on': barsOn }">
    <div class="flex items-center justify-between mb-4 rise" style="--d:0">
      <h1 class="text-xl font-bold"><button class="mr-1" @click="router.back()">‹</button> 省钱作战</h1>
      <button class="text-sm px-3 py-1.5 rounded-full text-white" style="background: var(--c-save)"
        @click="router.push('/record?t=save')">+ 记省下</button>
    </div>

    <!-- 总盘 -->
    <div class="card p-4 mb-4 rise" style="--d:1">
      <div class="flex items-baseline justify-between">
        <div>
          <div class="text-[12px]" style="color: var(--ink-3)">受控支出 · 本月已花 / 总上限</div>
          <div class="tabular font-bold text-[24px] mt-0.5">
            {{ fmtCNY(totalSpent, true) }}<span class="text-[14px] font-normal" style="color: var(--ink-3)"> / {{ fmtCNY(totalCap, true) }}</span>
          </div>
        </div>
        <div class="text-right">
          <div class="text-[12px]" style="color: var(--ink-3)">本月已抠出</div>
          <div class="tabular font-bold text-[24px]" style="color: var(--c-save)">{{ fmtCNY(savedThisMonth, true) }}</div>
        </div>
      </div>
      <div class="text-[11px] mt-1.5" style="color: var(--ink-3)">本月时间已过 {{ Math.round(dayOfMonth / daysInMonth * 100) }}%——柱子颜色:绿=稳,黄=花得比日子快,红=爆了</div>
    </div>

    <!-- 分域目标 -->
    <div v-for="(g, i) in goals" :key="g.id" class="card p-4 mb-3 rise" :style="`--d:${i + 2}`">
      <div class="flex items-center justify-between mb-1">
        <div class="text-[15px] font-medium">{{ g.icon }} {{ g.name }}</div>
        <div class="tabular text-sm" :style="g.over ? 'color: var(--danger); font-weight: 700' : ''">
          {{ fmtCNY(g.spent) }} <span style="color: var(--ink-3)">/ {{ fmtCNY(g.cap, true) }}</span>
        </div>
      </div>
      <div class="h-2.5 rounded-full overflow-hidden relative" style="background: var(--plane)">
        <div class="h-full rounded-full cat-bar" :style="{ background: barColor(g), transform: barsOn ? `scaleX(${Math.min(Math.max(g.pct, 0.02), 1)})` : 'scaleX(0)', transitionDelay: (i * 80) + 'ms' }"></div>
        <!-- 时间进度刻度线 -->
        <div class="absolute top-0 bottom-0 w-px" style="background: var(--ink-3); opacity: .6" :style="{ left: (g.pace * 100) + '%' }"></div>
      </div>
      <div class="flex justify-between text-[11px] mt-1.5">
        <span :style="g.over ? 'color: var(--danger)' : 'color: var(--ink-3)'">
          {{ g.over ? `超了 ${fmtCNY(g.spent - g.cap)}!` : `还能花 ${fmtCNY(g.left)}` }}
          <template v-if="g.prev > 0"> · 上月 {{ fmtCNY(g.prev, true) }}</template>
        </span>
      </div>
      <div class="text-[12px] mt-2 px-2.5 py-1.5 rounded-lg" style="background: var(--plane); color: var(--ink-2)">💡 {{ g.strategy }}</div>
    </div>

    <!-- 省下账 -->
    <div class="card p-4 mb-4 rise" :style="`--d:${goals.length + 2}`">
      <div class="text-sm font-medium mb-2" style="color: var(--ink-2)">本月省下 · 按方式</div>
      <div v-if="!savedByWay.length" class="text-sm py-3 text-center" style="color: var(--ink-3)">
        忍住没买、退订、用券…每一笔都记进来,月底看战果
      </div>
      <div v-for="[way, amt] in savedByWay" :key="way" class="flex items-center justify-between py-1.5 text-sm">
        <span class="flex items-center gap-2" style="color: var(--ink-2)">
          <i class="w-2 h-2 rounded-full inline-block" style="background: var(--c-save)"></i>{{ way }}</span>
        <span class="tabular font-medium" style="color: var(--c-save)">{{ fmtCNY(amt) }}</span>
      </div>
      <div v-if="recentSavings.length" class="mt-3 pt-3 border-t" style="border-color: var(--hairline)">
        <div class="text-[12px] mb-1.5" style="color: var(--ink-3)">最近记录</div>
        <div v-for="s in recentSavings" :key="s.id" class="flex justify-between py-1 text-[13px]">
          <span class="truncate pr-2" style="color: var(--ink-2)">{{ fmtDate(s.saved_at) }} {{ s.note || s.way }}</span>
          <span class="tabular" style="color: var(--c-save)">省{{ fmtCNY(s.amount, true) }}</span>
        </div>
      </div>
    </div>

    <p class="text-center text-[11px] mb-4" style="color: var(--ink-3)">想调整某个领域的上限或加新领域,直接跟我说</p>
  </div>
</template>
