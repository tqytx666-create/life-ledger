<script setup>
// 省钱作战:三大战区 —— 省利息 / 省日常 / 省家人开支
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
const barsOn = ref(false)
onMounted(() => setTimeout(() => { barsOn.value = true }, 250))

// ========== 战区一:省利息 ==========
const WSD_BASE = 793540.08
const WSD_CHEAP = 125000.06
const WSD_BASE_INTEREST = (WSD_BASE - WSD_CHEAP) * 0.12 / 12 + WSD_CHEAP * 0.045 / 12  // 启动时月息 7154.15
const wsd = computed(() => {
  const a = store.accounts.find((x) => x.name === '网商贷')
  const owed = a ? -Number(a.balance) : 0
  const monthlyInterest = Math.max(owed - WSD_CHEAP, 0) * 0.12 / 12 + Math.min(owed, WSD_CHEAP) * 0.045 / 12
  return { owed, monthlyInterest, progress: Math.max(0, 1 - owed / WSD_BASE),
    savedMonthly: WSD_BASE_INTEREST - monthlyInterest }
})
const lixiang = computed(() => {
  const a = store.accounts.find((x) => x.name?.startsWith('理想车贷'))
  return a ? -Number(a.balance) : 0
})

// ========== 战区二:省日常(save_goals 上限目标) ==========
function goalSpent(g, month) {
  const cats = Array.isArray(g.cats) ? g.cats : JSON.parse(g.cats || '[]')
  let t = 0
  for (const x of store.recentTx) {
    if (x.type !== 'expense' || !x.occurred_at.startsWith(month)) continue
    if (cats.includes(x.category) || (g.kw && (x.note || '').includes(g.kw)))
      t += toCNY(x.amount, accMap.value[x.account_id]?.currency || 'CNY')
  }
  return t
}
const goals = computed(() => store.saveGoals.map((g) => {
  const spent = goalSpent(g, thisMonth)
  const cap = Number(g.cap)
  return { ...g, spent, cap, prev: goalSpent(g, lastMonth),
    pct: cap > 0 ? spent / cap : 0, left: Math.max(cap - spent, 0),
    over: spent > cap, pace: dayOfMonth / daysInMonth }
}))
const totalCap = computed(() => goals.value.reduce((s, g) => s + g.cap, 0))
const totalSpent = computed(() => goals.value.reduce((s, g) => s + g.spent, 0))
function barColor(g) {
  if (g.over) return 'var(--danger)'
  if (g.pct > g.pace + 0.15) return '#eda100'
  return '#1baf7a'
}

// ========== 战区三:省家人开支 ==========
const FAM_BASE = 40000  // 2026-08 基线:妈妈1万+丈母娘1万+老婆2万
const fam = computed(() => {
  let now = 0
  const rows = []
  for (const r of store.recurring) {
    if (r.active && r.period === 'monthly' && r.category === '给家人') {
      now += Number(r.amount)
      rows.push({ name: r.name.replace(/生活费|\(.*?\)/g, ''), amount: Number(r.amount) })
    }
  }
  return { now, rows, savedMonthly: FAM_BASE - now }
})

// ========== 省下账 ==========
const savedThisMonth = computed(() => store.savings.filter((s) => s.saved_at.startsWith(thisMonth)).reduce((t, s) => t + Number(s.amount), 0))
const savedByWay = computed(() => {
  const m = {}
  for (const s of store.savings.filter((x) => x.saved_at.startsWith(thisMonth))) m[s.way] = (m[s.way] || 0) + Number(s.amount)
  return Object.entries(m).sort((a, b) => b[1] - a[1])
})
const recentSavings = computed(() => store.savings.slice(0, 8))
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5" :class="{ 'bars-on': barsOn }">
    <div class="flex items-center justify-between mb-4 rise" style="--d:0">
      <h1 class="text-xl font-bold"><button class="mr-1" @click="router.back()">‹</button> 省钱作战</h1>
      <div class="flex gap-2">
        <button class="text-sm px-3 py-1.5 rounded-full" style="background: var(--c-net)"
          @click="router.push('/askbuy')">🤔 能买吗</button>
        <button class="text-sm px-3 py-1.5 rounded-full" style="background: var(--c-save)"
          @click="router.push('/record?t=save')">+ 记省下</button>
      </div>
    </div>

    <!-- ===== 战区一:省利息 ===== -->
    <div class="text-[13px] font-semibold mb-2 px-1 rise" style="--d:1; color: var(--ink-2)">🔥 战区一 · 省利息(最大的头)</div>
    <div class="card p-4 mb-3 rise" style="--d:1">
      <div class="flex items-center justify-between mb-1">
        <div class="text-[15px] font-medium">网商贷 12%</div>
        <div class="text-xs" style="color: var(--ink-3)">已消灭 {{ (wsd.progress * 100).toFixed(1) }}%</div>
      </div>
      <div class="flex items-baseline gap-2 mb-2">
        <span class="tabular font-bold text-[20px]" style="color: var(--danger)">{{ fmtCNY(wsd.owed, true) }}</span>
        <span class="text-xs" style="color: var(--ink-3)">每月白烧 {{ fmtCNY(wsd.monthlyInterest) }}</span>
        <span v-if="wsd.savedMonthly > 1" class="text-xs font-medium" style="color: var(--c-save)">已月省 {{ fmtCNY(wsd.savedMonthly, true) }}</span>
      </div>
      <div class="h-2.5 rounded-full overflow-hidden" style="background: var(--plane)">
        <div class="h-full rounded-full cat-bar" style="background: linear-gradient(90deg, #1baf7a, #0ca30c)"
          :style="{ transform: barsOn ? `scaleX(${Math.max(wsd.progress, 0.015)})` : 'scaleX(0)' }"></div>
      </div>
      <div class="text-[12px] mt-2 px-2.5 py-1.5 rounded-lg" style="background: var(--plane); color: var(--ink-2)">
        💡 卖股票的钱、每月结余、卖闲置的钱全往这砸;每还1万,每月利息少100,一年省1200。先歼12%部分,4.5%那12.5万不急</div>
    </div>
    <div class="card p-4 mb-3 rise" style="--d:2">
      <div class="flex items-center justify-between">
        <div class="text-[15px] font-medium">理想车贷尾款</div>
        <div class="tabular text-sm" style="color: var(--danger)">{{ fmtCNY(lixiang, true) }}</div>
      </div>
      <div class="text-[12px] mt-2 px-2.5 py-1.5 rounded-lg" style="background: var(--plane); color: var(--ink-2)">
        💡 车已卖贷还在。打理想金融客服问「提前结清价」,通常免剩余利息,可能省几千</div>
    </div>
    <div class="card p-4 mb-4 rise" style="--d:2">
      <div class="flex items-center justify-between">
        <div class="text-[15px] font-medium">券商融资 ~6%</div>
        <div class="tabular text-sm" style="color: var(--danger)">约 ¥22万</div>
      </div>
      <div class="text-[12px] mt-2 px-2.5 py-1.5 rounded-lg" style="background: var(--plane); color: var(--ink-2)">
        💡 信用户降杠杆时优先了结,月息约1,100;你说过尽量卖股还债,卖了报我更新持仓</div>
    </div>

    <!-- ===== 战区二:省日常 ===== -->
    <div class="flex items-center justify-between mb-2 px-1 rise" style="--d:3">
      <div class="text-[13px] font-semibold shrink-0" style="color: var(--ink-2)">🛍 战区二 · 省日常</div>
      <div class="text-[11px] tabular text-right" style="color: var(--ink-3)">{{ fmtCNY(totalSpent, true) }}/{{ fmtCNY(totalCap, true) }} · 时间过{{ Math.round(dayOfMonth / daysInMonth * 100) }}%</div>
    </div>
    <div v-for="(g, i) in goals" :key="g.id" class="card p-4 mb-3 rise" :style="`--d:${i + 3}`">
      <div class="flex items-center justify-between mb-1">
        <div class="text-[15px] font-medium">{{ g.icon }} {{ g.name }}</div>
        <div class="tabular text-sm" :style="g.over ? 'color: var(--danger); font-weight: 700' : ''">
          {{ fmtCNY(g.spent) }} <span style="color: var(--ink-3)">/ {{ fmtCNY(g.cap, true) }}</span>
        </div>
      </div>
      <div class="h-2.5 rounded-full overflow-hidden relative" style="background: var(--plane)">
        <div class="h-full rounded-full cat-bar" :style="{ background: barColor(g), transform: barsOn ? `scaleX(${Math.min(Math.max(g.pct, 0.02), 1)})` : 'scaleX(0)', transitionDelay: (i * 80) + 'ms' }"></div>
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

    <!-- ===== 战区三:省家人开支 ===== -->
    <div class="text-[13px] font-semibold mb-2 px-1 rise" :style="`--d:${goals.length + 3}`" style="color: var(--ink-2)">👨‍👩‍👧 战区三 · 家人开支</div>
    <div class="card p-4 mb-4 rise" :style="`--d:${goals.length + 3}`">
      <div class="flex items-center justify-between mb-2">
        <div class="text-[15px] font-medium">每月固定给家人</div>
        <div class="tabular font-semibold">{{ fmtCNY(fam.now, true) }}<span class="text-xs font-normal" style="color: var(--ink-3)">/月 · 年 {{ fmtCNY(fam.now * 12, true) }}</span></div>
      </div>
      <div v-for="r in fam.rows" :key="r.name" class="flex justify-between py-1 text-sm">
        <span style="color: var(--ink-2)">{{ r.name }}</span>
        <span class="tabular">{{ fmtCNY(r.amount, true) }}/月</span>
      </div>
      <div v-if="fam.savedMonthly > 0" class="text-[12px] mt-1 font-medium" style="color: var(--c-save)">
        已比基线(4万/月)降了 {{ fmtCNY(fam.savedMonthly, true) }}/月 = 一年 {{ fmtCNY(fam.savedMonthly * 12, true) }}</div>
      <div class="text-[12px] mt-2 px-2.5 py-1.5 rounded-lg" style="background: var(--plane); color: var(--ink-2)">
        💡 这块不是抠,是坦诚:跟家里说清现在的压力和还债计划,商量一个阶段性的数。哪怕各调2000,一年就是7.2万,等翻身了再补回来。谈好新数告诉我,我改自动转账,这里立刻显示每月省多少</div>
    </div>

    <!-- 省下账 -->
    <div class="card p-4 mb-4 rise" :style="`--d:${goals.length + 4}`">
      <div class="flex items-center justify-between mb-2">
        <div class="text-sm font-medium" style="color: var(--ink-2)">本月抠出总账</div>
        <div class="tabular font-bold" style="color: var(--c-save)">{{ fmtCNY(savedThisMonth) }}</div>
      </div>
      <div v-if="!savedByWay.length" class="text-sm py-2 text-center" style="color: var(--ink-3)">
        忍住没买、退订、用券…每一笔都记进来</div>
      <div v-for="[way, amt] in savedByWay" :key="way" class="flex items-center justify-between py-1.5 text-sm">
        <span class="flex items-center gap-2" style="color: var(--ink-2)">
          <i class="w-2 h-2 rounded-full inline-block" style="background: var(--c-save)"></i>{{ way }}</span>
        <span class="tabular font-medium" style="color: var(--c-save)">{{ fmtCNY(amt) }}</span>
      </div>
      <div v-if="recentSavings.length" class="mt-3 pt-3 border-t" style="border-color: var(--hairline)">
        <div class="text-[12px] mb-1.5" style="color: var(--ink-3)">最近记录</div>
        <div v-for="s in recentSavings" :key="s.id" class="flex justify-between py-1 text-[13px]">
          <span class="truncate pr-2" style="color: var(--ink-2)">{{ fmtDate(s.saved_at) }} {{ s.note || s.way }}</span>
          <span class="tabular shrink-0 whitespace-nowrap" style="color: var(--c-save)">省{{ fmtCNY(s.amount, true) }}</span>
        </div>
      </div>
    </div>

    <p class="text-center text-[11px] mb-4" style="color: var(--ink-3)">调上限、加战区、改基线,跟我说一句就行</p>
  </div>
</template>
