<script setup>
// 净资产走势 · 单系列面积线图(单系列不设图例,标题即说明)
import { computed, ref } from 'vue'
import { fmtCNY, fmtDate } from '../lib/fmt'

const props = defineProps({ snapshots: { type: Array, default: () => [] } })

const W = 340, H = 150, PAD = { l: 8, r: 52, t: 14, b: 22 }
const hover = ref(-1)

const pts = computed(() => {
  const s = props.snapshots
  if (!s.length) return []
  const vals = s.map((x) => Number(x.total_cny))
  let min = Math.min(...vals), max = Math.max(...vals)
  if (min === max) { min -= 1; max += 1 }
  const span = max - min
  min -= span * 0.12; max += span * 0.12
  const iw = W - PAD.l - PAD.r, ih = H - PAD.t - PAD.b
  return s.map((x, i) => ({
    x: PAD.l + (s.length === 1 ? iw / 2 : (i / (s.length - 1)) * iw),
    y: PAD.t + ih - ((Number(x.total_cny) - min) / (max - min)) * ih,
    v: Number(x.total_cny),
    d: x.snap_date,
  }))
})

const linePath = computed(() => pts.value.map((p, i) => (i ? 'L' : 'M') + p.x.toFixed(1) + ' ' + p.y.toFixed(1)).join(''))
const areaPath = computed(() => {
  if (!pts.value.length) return ''
  const first = pts.value[0], last = pts.value[pts.value.length - 1]
  return linePath.value + `L${last.x.toFixed(1)} ${H - PAD.b}L${first.x.toFixed(1)} ${H - PAD.b}Z`
})
const gridYs = [0.25, 0.62].map((f) => PAD.t + (H - PAD.t - PAD.b) * f)
const last = computed(() => pts.value[pts.value.length - 1])
const hoverPt = computed(() => (hover.value >= 0 ? pts.value[hover.value] : null))

function onMove(e) {
  if (!pts.value.length) return
  const rect = e.currentTarget.getBoundingClientRect()
  const x = ((e.touches ? e.touches[0].clientX : e.clientX) - rect.left) / rect.width * W
  let best = 0, bd = 1e9
  pts.value.forEach((p, i) => { const d = Math.abs(p.x - x); if (d < bd) { bd = d; best = i } })
  hover.value = best
}
</script>

<template>
  <div class="select-none">
    <div v-if="!pts.length" class="h-[150px] flex items-center justify-center text-sm" style="color: var(--ink-3)">
      记上账,走势就长出来了
    </div>
    <svg v-else :viewBox="`0 0 ${W} ${H}`" class="w-full touch-none"
      @mousemove="onMove" @mouseleave="hover = -1" @touchstart.passive="onMove" @touchmove.passive="onMove" @touchend="hover = -1">
      <line v-for="y in gridYs" :key="y" :x1="PAD.l" :x2="W - PAD.r" :y1="y" :y2="y" stroke="var(--grid)" stroke-width="1" />
      <line :x1="PAD.l" :x2="W - PAD.r" :y1="H - PAD.b" :y2="H - PAD.b" stroke="var(--baseline)" stroke-width="1" />
      <path :d="areaPath" fill="var(--c-net)" opacity="0.1" />
      <path :d="linePath" fill="none" stroke="var(--c-net)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
      <!-- 端点:≥8px 标记 + 2px surface 环 + 直接标注 -->
      <circle :cx="last.x" :cy="last.y" r="6" fill="var(--surface-1)" />
      <circle :cx="last.x" :cy="last.y" r="4" fill="var(--c-net)" />
      <text :x="last.x + 8" :y="last.y + 4" font-size="11" font-weight="600" fill="var(--ink-1)">{{ fmtCNY(last.v, true) }}</text>
      <!-- 首末日期刻度 -->
      <text v-if="pts.length > 1" :x="pts[0].x" :y="H - 8" font-size="10" fill="var(--ink-3)">{{ fmtDate(pts[0].d) }}</text>
      <text :x="last.x" :y="H - 8" font-size="10" :text-anchor="pts.length > 1 ? 'end' : 'middle'" fill="var(--ink-3)">{{ fmtDate(last.d) }}</text>
      <!-- 悬停十字线 + tooltip -->
      <template v-if="hoverPt">
        <line :x1="hoverPt.x" :x2="hoverPt.x" :y1="PAD.t" :y2="H - PAD.b" stroke="var(--baseline)" stroke-width="1" />
        <circle :cx="hoverPt.x" :cy="hoverPt.y" r="6" fill="var(--surface-1)" />
        <circle :cx="hoverPt.x" :cy="hoverPt.y" r="4" fill="var(--c-net)" />
        <g :transform="`translate(${Math.min(Math.max(hoverPt.x - 55, 2), W - 112)}, 0)`">
          <rect width="110" height="30" rx="6" fill="var(--surface-1)" stroke="var(--hairline)" />
          <text x="55" y="12" font-size="9" text-anchor="middle" fill="var(--ink-3)">{{ fmtDate(hoverPt.d) }}</text>
          <text x="55" y="25" font-size="11" font-weight="600" text-anchor="middle" fill="var(--ink-1)">{{ fmtCNY(hoverPt.v) }}</text>
        </g>
      </template>
    </svg>
  </div>
</template>
