<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, loadAll } from '../lib/store'
import { fmtMoney } from '../lib/fmt'

const router = useRouter()
const err = ref('')
const busy = ref(false)
const showAdd = ref(false)

const f = ref({ name: '', amount: '', category: '订阅', account_id: '', period: 'monthly', run_day: 1, run_month: 1 })

const accounts = computed(() => store.accounts.filter((a) => !a.archived && a.type !== 'loan'))
const accName = (id) => store.accounts.find((a) => a.id === id)?.name || ''
const accCur = (id) => store.accounts.find((a) => a.id === id)?.currency || 'CNY'

async function run(fn) {
  err.value = ''; busy.value = true
  try { await fn(); await loadAll() } catch (e) { err.value = e.message } finally { busy.value = false }
}

const add = () => run(async () => {
  const v = f.value
  if (!v.name.trim() || !Number(v.amount)) throw new Error('名称和金额都要填')
  if (!v.account_id) throw new Error('选一个扣款账户')
  const payload = {
    name: v.name.trim(), amount: Number(v.amount), category: v.category,
    account_id: v.account_id, currency: accCur(v.account_id),
    period: v.period, run_day: Number(v.run_day) || 1,
    run_month: v.period === 'yearly' ? Number(v.run_month) || 1 : null,
    // 游标置当前周期:从下个周期开始自动记,不补历史
    settled_through: v.period === 'monthly' ? new Date().toISOString().slice(0, 7) : String(new Date().getFullYear()),
  }
  const { error } = await supabase.from('recurring').insert(payload)
  if (error) throw error
  showAdd.value = false
  f.value = { name: '', amount: '', category: '订阅', account_id: '', period: 'monthly', run_day: 1, run_month: 1 }
})

const toggle = (r) => run(async () => {
  const { error } = await supabase.from('recurring').update({ active: !r.active }).eq('id', r.id)
  if (error) throw error
})

const del = (r) => {
  if (!confirm(`删掉「${r.name}」?已记的流水保留`)) return
  run(async () => {
    const { error } = await supabase.from('recurring').delete().eq('id', r.id)
    if (error) throw error
  })
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-bold"><button class="mr-1" @click="router.back()">‹</button> 固定支出</h1>
      <button class="text-sm" style="color: var(--c-net)" @click="showAdd = !showAdd">+ 添加</button>
    </div>
    <p v-if="err" class="text-sm mb-3" style="color: var(--danger)">{{ err }}</p>

    <div v-if="showAdd" class="card p-4 mb-4 space-y-3">
      <input v-model="f.name" placeholder="名称(如:爱奇艺/车险/房租)" class="w-full bg-transparent outline-none py-1" />
      <div class="flex gap-2">
        <input v-model="f.amount" type="number" inputmode="decimal" placeholder="金额" class="flex-1 bg-transparent outline-none py-1 tabular" />
        <select v-model="f.category" class="bg-transparent outline-none">
          <option v-for="c in ['订阅', '保险', '房租', '物业', '话费', '其他']" :key="c" :value="c">{{ c }}</option>
        </select>
      </div>
      <select v-model="f.account_id" class="w-full bg-transparent outline-none py-1">
        <option value="" disabled>扣款账户</option>
        <option v-for="a in accounts" :key="a.id" :value="a.id">{{ a.name }}({{ a.currency }})</option>
      </select>
      <div class="flex items-center gap-2 text-sm">
        <select v-model="f.period" class="bg-transparent outline-none py-1">
          <option value="monthly">每月</option>
          <option value="yearly">每年</option>
        </select>
        <template v-if="f.period === 'yearly'">
          <input v-model="f.run_month" type="number" min="1" max="12" class="w-14 card rounded-lg py-1 text-center tabular outline-none" />
          <span style="color: var(--ink-3)">月</span>
        </template>
        <input v-model="f.run_day" type="number" min="1" max="28" class="w-14 card rounded-lg py-1 text-center tabular outline-none" />
        <span style="color: var(--ink-3)">号自动记账</span>
      </div>
      <button :disabled="busy" class="px-4 py-2 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="add">保存</button>
    </div>

    <div v-for="r in store.recurring" :key="r.id" class="card p-4 mb-3" :class="r.active ? '' : 'opacity-60'">
      <div class="flex items-center justify-between">
        <div>
          <div>{{ r.name }} <span v-if="!r.active" class="text-xs" style="color: var(--ink-3)">已暂停</span></div>
          <div class="text-xs mt-0.5" style="color: var(--ink-3)">
            {{ r.period === 'monthly' ? `每月${r.run_day}号` : `每年${r.run_month}月${r.run_day}号` }}
            · {{ accName(r.account_id) }} · {{ r.category }}
          </div>
        </div>
        <div class="tabular font-medium">{{ fmtMoney(r.amount, r.currency) }}</div>
      </div>
      <div class="flex gap-4 mt-2 text-xs">
        <button style="color: var(--c-net)" @click="toggle(r)">{{ r.active ? '暂停' : '恢复' }}</button>
        <button style="color: var(--ink-3)" @click="del(r)">删除</button>
      </div>
    </div>

    <div v-if="!store.recurring.length && !showAdd" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      订阅、保险、房租设一次<br />以后每期自动入账
    </div>
  </div>
</template>
