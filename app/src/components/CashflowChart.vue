<script setup>
// 月度收支 · 双系列分组柱(收入绿/支出红,图例常驻,点按看数)
import { computed, ref, onMounted } from 'vue'
import { fmtCNY } from '../lib/fmt'

const props = defineProps({
  cashflow: { type: Array, default: () => [] },
  baseline: { type: Number, default: 0 },      // 全口径月支出基准(固定盘+生活预算),不传则用历史均值
})
const emit = defineEmits(['detail'])

const W = 340, H = 170, PAD = { l: 8, r: 8, t: 26, b: 22 }
const picked = ref(-1)
const on = ref(false)
onMounted(() => setTimeout(() => { on.value = true }, 250))

const scale = computed(() => {
  const max = Math.max(1, ...props.cashflow.flatMap((m) => [m.income, m.expense]), props.baseline)
  return (H - PAD.t - PAD.b) / (max * 1.08)
})

// 基准线:优先用传入的全口径基准,否则退回历史均值
const avgExpense = computed(() => {
  if (props.baseline > 0) return props.baseline
  const cur = new Date().toISOString().slice(0, 7)
  const done = props.cashflow.filter((m) => m.month < cur && m.expense > 0)
  const list = done.length ? done : props.cashflow
  if (!list.length) return 0
  return list.reduce((s, m) => s + m.expense, 0) / list.length
})
const avgY = computed(() => H - PAD.b - avgExpense.value * scale.value)

const groups = computed(() => {
  const n = props.cashflow.length
  if (!n) return []
  const iw = (W - PAD.l - PAD.r) / n
  const bw = Math.min(24, iw * 0.28)
  return props.cashflow.map((m, i) => {
    const cx = PAD.l + iw * i + iw / 2
    const hIn = m.income * scale.value, hOut = m.expense * scale.value
    return {
      m, cx,
      in: { x: cx - bw - 1, w: bw, y: H - PAD.b - hIn, h: hIn },       // 柱间 2px surface gap
      out: { x: cx + 1, w: bw, y: H - PAD.b - hOut, h: hOut },
      label: Number(m.month.slice(5)) + '月',
    }
  })
})

// 4px 圆角只给数据端(顶部),基线端方角
function barPath(b) {
  if (b.h <= 0.5) return ''
  const r = Math.min(4, b.h, b.w / 2)
  const x2 = b.x + b.w, yB = H - PAD.b
  return `M${b.x} ${yB}L${b.x} ${b.y + r}Q${b.x} ${b.y} ${b.x + r} ${b.y}L${x2 - r} ${b.y}Q${x2} ${b.y} ${x2} ${b.y + r}L${x2} ${yB}Z`
}
const pickedG = computed(() => (picked.value >= 0 ? groups.value[picked.value] : null))
</script>

<template>
  <div class="select-none">
    <div class="flex items-center gap-4 text-xs mb-1" style="color: var(--ink-2)">
      <span class="flex items-center gap-1.5"><i class="w-2.5 h-2.5 rounded-sm inline-block" style="background: var(--c-in)"></i>收入</span>
      <span class="flex items-center gap-1.5"><i class="w-2.5 h-2.5 rounded-sm inline-block" style="background: var(--c-out)"></i>支出</span>
      <span class="ml-auto" style="color: var(--ink-3)">折合人民币</span>
    </div>
    <div v-if="!groups.length" class="h-[150px] flex items-center justify-center text-sm" style="color: var(--ink-3)">
      本月开始记账,下月就能看对比
    </div>
    <svg v-else :viewBox="`0 0 ${W} ${H}`" class="w-full" :class="{ 'bars-on': on }">
      <line :x1="PAD.l" :x2="W - PAD.r" :y1="H - PAD.b" :y2="H - PAD.b" stroke="var(--baseline)" stroke-width="1" />
      <g v-for="(g, i) in groups" :key="g.m.month" @click="picked = picked === i ? -1 : i" class="cursor-pointer">
        <rect :x="g.cx - 30" y="0" width="60" :height="H" fill="transparent" />
        <path class="grow-bar" :style="{ transitionDelay: (i * 80) + 'ms' }" :d="barPath(g.in)" fill="var(--c-in)" />
        <path class="grow-bar" :style="{ transitionDelay: (i * 80 + 40) + 'ms' }" :d="barPath(g.out)" fill="var(--c-out)" />
        <text :x="g.cx" :y="H - 8" font-size="10" text-anchor="middle" fill="var(--ink-3)">{{ g.label }}</text>
        <!-- 末月直接标注(浅色绿柱对比不足的补救) -->
        <template v-if="i === groups.length - 1 && picked < 0">
          <text v-if="g.m.income > 0" :x="g.in.x + g.in.w / 2" :y="g.in.y - 4" font-size="9" text-anchor="middle" fill="var(--ink-2)">{{ fmtCNY(g.m.income, true) }}</text>
          <text v-if="g.m.expense > 0" :x="g.out.x + g.out.w / 2" :y="g.out.y - 4" font-size="9" text-anchor="middle" fill="var(--ink-2)">{{ fmtCNY(g.m.expense, true) }}</text>
        </template>
      </g>
      <!-- 月均支出基准线(画在柱子上层) -->
      <template v-if="avgExpense > 0 && avgY > PAD.t">
        <line :x1="PAD.l" :x2="W - PAD.r" :y1="avgY" :y2="avgY" stroke="var(--gold)" stroke-width="1" stroke-dasharray="5 4" opacity="0.85" />
        <text :x="W - PAD.r" :y="avgY - 4" font-size="9" text-anchor="end" fill="var(--gold)">月支出基准 {{ fmtCNY(avgExpense, true) }}</text>
      </template>
      <g v-if="pickedG" :transform="`translate(${Math.min(Math.max(pickedG.cx - 78, 2), W - 158)}, 0)`"
        class="cursor-pointer" @click.stop="emit('detail', pickedG.m.month)">
        <rect width="156" height="24" rx="6" fill="var(--surface-1)" stroke="var(--hairline)" />
        <text x="66" y="16" font-size="10" text-anchor="middle" fill="var(--ink-1)">
          收 {{ fmtCNY(pickedG.m.income, true) }} · 支 {{ fmtCNY(pickedG.m.expense, true) }}
        </text>
        <text x="148" y="16" font-size="10" text-anchor="end" fill="var(--gold)">详情›</text>
      </g>
    </svg>
  </div>
</template>
