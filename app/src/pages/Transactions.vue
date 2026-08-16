<script setup>
import { ref, computed } from 'vue'
import { store, deleteTx } from '../lib/store'
import { fmtMoney, fmtDate } from '../lib/fmt'

const filter = ref('all')
const busyId = ref('')
const err = ref('')

const accMap = computed(() => Object.fromEntries(store.accounts.map((a) => [a.id, a])))

const filtered = computed(() => {
  let list = store.recentTx
  if (filter.value === 'income') list = list.filter((t) => t.type === 'income')
  else if (filter.value === 'expense') list = list.filter((t) => t.type === 'expense')
  else if (filter.value === 'transfer') list = list.filter((t) => t.type.startsWith('transfer'))
  return list
})

// 按日分组
const groups = computed(() => {
  const g = {}
  for (const t of filtered.value) {
    ;(g[t.occurred_at] ||= []).push(t)
  }
  return Object.entries(g).sort((a, b) => b[0].localeCompare(a[0]))
})

function sign(t) {
  if (t.type === 'income' || t.type === 'transfer_in') return '+'
  if (t.type === 'adjust') return t.category === '-' ? '-' : '+'
  return '-'
}
function color(t) {
  const s = sign(t)
  if (t.type.startsWith('transfer')) return 'var(--ink-2)'
  return s === '+' ? 'var(--good-text)' : 'var(--ink-1)'
}
function typeName(t) {
  return { income: '', expense: '', transfer_out: '转出', transfer_in: '转入', adjust: '校准' }[t.type] || ''
}

async function del(t) {
  const label = `${t.category} ${fmtMoney(t.amount, accMap.value[t.account_id]?.currency)}`
  if (!confirm(`删掉这笔?余额会同步回滚\n${label}`)) return
  busyId.value = t.id
  err.value = ''
  try {
    await deleteTx(t.id)
  } catch (e) {
    err.value = e.message
  } finally {
    busyId.value = ''
  }
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <h1 class="text-xl font-bold mb-4">流水</h1>

    <div class="flex gap-2 mb-4">
      <button v-for="f in [['all', '全部'], ['expense', '支出'], ['income', '收入'], ['transfer', '转账']]" :key="f[0]"
        class="px-3.5 py-1.5 rounded-full text-[13px] border"
        :style="filter === f[0] ? 'background: var(--c-net); color:#fff; border-color:transparent' : 'border-color: var(--hairline); color: var(--ink-2)'"
        @click="filter = f[0]">{{ f[1] }}</button>
    </div>

    <p v-if="err" class="text-sm mb-3" style="color: var(--c-out)">{{ err }}</p>

    <div v-if="!groups.length" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      近半年还没有这类流水
    </div>

    <div v-for="[date, list] in groups" :key="date" class="mb-4">
      <div class="text-xs mb-1.5 px-1" style="color: var(--ink-3)">{{ fmtDate(date) }}</div>
      <div class="card px-4">
        <div v-for="t in list" :key="t.id"
          class="flex items-center justify-between py-3 border-b last:border-0" style="border-color: var(--hairline)">
          <div class="min-w-0 flex-1">
            <div class="text-[15px] truncate">
              {{ t.category }}<span v-if="typeName(t)" class="text-xs ml-1" style="color: var(--ink-3)">{{ typeName(t) }}</span>
            </div>
            <div class="text-xs truncate" style="color: var(--ink-3)">
              {{ accMap[t.account_id]?.name }}<span v-if="t.note"> · {{ t.note }}</span>
            </div>
          </div>
          <div class="flex items-center gap-3 pl-2">
            <span class="tabular font-medium" :style="{ color: color(t) }">
              {{ sign(t) }}{{ fmtMoney(t.amount, accMap[t.account_id]?.currency) }}
            </span>
            <button class="text-xs px-1.5 py-1 disabled:opacity-40" style="color: var(--ink-3)"
              :disabled="busyId === t.id" @click="del(t)">{{ busyId === t.id ? '…' : '✕' }}</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
