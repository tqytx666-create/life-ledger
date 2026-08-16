<script setup>
// 现金钱包详情:每张卡/钱包/理财的实时余额
import { computed, ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { store, toCNY } from '../lib/store'
import { fmtCNY, fmtMoney } from '../lib/fmt'

const router = useRouter()
const barsOn = ref(false)
onMounted(() => setTimeout(() => { barsOn.value = true }, 200))

const GROUPS = [
  { key: 'bank', name: '银行卡', icon: '🏦', match: (a) => a.type === 'bank' && Number(a.balance) > 0 },
  { key: 'wallet', name: '零钱与钱包', icon: '👛', match: (a) => a.type === 'cash' },
  { key: 'fund', name: '理财与基金', icon: '🧺', match: (a) => a.type === 'fund' },
]
const grouped = computed(() => {
  const act = store.accounts.filter((a) => !a.archived)
  return GROUPS.map((g) => {
    const list = act.filter(g.match).slice().sort((a, b) => toCNY(b.balance, b.currency) - toCNY(a.balance, a.currency))
    return { ...g, list, total: list.reduce((s, a) => s + Math.max(toCNY(a.balance, a.currency), 0), 0) }
  }).filter((g) => g.list.length)
})
const total = computed(() => grouped.value.reduce((s, g) => s + g.total, 0))
const maxBal = computed(() => Math.max(1, ...grouped.value.flatMap((g) => g.list.map((a) => toCNY(a.balance, a.currency)))))
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5" :class="{ 'bars-on': barsOn }">
    <h1 class="text-xl font-bold mb-4 rise" style="--d:0"><button class="mr-1" @click="router.back()">‹</button> 💰 现金钱包</h1>

    <div class="hero-card p-5 mb-4 rise" style="--d:0">
      <div class="text-[13px] opacity-80">随时能动用的钱</div>
      <div class="text-[36px] leading-tight font-bold tracking-tight tabular">{{ fmtCNY(total) }}</div>
    </div>

    <div v-for="(g, gi) in grouped" :key="g.key" class="card p-4 mb-4 rise" :style="`--d:${gi + 1}`">
      <div class="flex items-center justify-between mb-2">
        <div class="text-sm font-medium" style="color: var(--ink-2)">{{ g.icon }} {{ g.name }}</div>
        <div class="tabular text-sm font-medium">{{ fmtCNY(g.total, true) }}</div>
      </div>
      <div v-for="(a, i) in g.list" :key="a.id" class="py-2 border-b last:border-0" style="border-color: var(--hairline)">
        <div class="flex justify-between text-[14px] mb-1">
          <span style="color: var(--ink-2)">{{ a.name }}</span>
          <span class="tabular font-medium">{{ fmtMoney(a.balance, a.currency) }}</span>
        </div>
        <div class="cat-bar" style="background: var(--c-net); height: 5px"
          :style="{ transform: barsOn ? `scaleX(${Math.max(toCNY(a.balance, a.currency) / maxBal, 0.015)})` : 'scaleX(0)', transitionDelay: (i * 50) + 'ms' }"></div>
      </div>
    </div>

    <button class="w-full py-3 mb-4 rounded-xl text-sm border rise" :style="`--d:${grouped.length + 1}`"
      style="border-color: var(--hairline); color: var(--c-net)" @click="router.push('/accounts')">管理账户 / 校准余额 ›</button>
  </div>
</template>
