<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, loadAll, recordTx } from '../lib/store'
import { fmtMoney, ACCOUNT_TYPES, CURRENCIES } from '../lib/fmt'

const router = useRouter()
const err = ref('')
const busy = ref(false)
const showAdd = ref(false)

const nName = ref('')
const nType = ref('bank')
const nCurrency = ref('CNY')
const nBalance = ref('')

// 校准
const adjId = ref('')
const adjTarget = ref('')

const active = computed(() => store.accounts.filter((a) => !a.archived))
const typeLabel = Object.fromEntries(ACCOUNT_TYPES.map((t) => [t.key, t]))

async function run(fn) {
  err.value = ''; busy.value = true
  try { await fn(); await loadAll() } catch (e) { err.value = e.message } finally { busy.value = false }
}

const addAccount = () => run(async () => {
  if (!nName.value.trim()) throw new Error('账户名不能空')
  const { data, error } = await supabase.from('accounts')
    .insert({ name: nName.value.trim(), type: nType.value, currency: nCurrency.value })
    .select().single()
  if (error) throw error
  const init = Number(nBalance.value)
  if (init && init !== 0) {
    // 期初余额走校准流水,可追溯
    await recordTx({
      p_account_id: data.id, p_type: 'adjust', p_amount: Math.abs(init),
      p_category: init > 0 ? '+' : '-', p_note: '期初余额', p_occurred_at: null,
      p_peer_account_id: null, p_batch_id: null, p_loan_id: null, p_recurring_id: null,
    })
  }
  nName.value = ''; nBalance.value = ''; showAdd.value = false
})

const adjust = (a) => run(async () => {
  const target = Number(adjTarget.value)
  if (Number.isNaN(target)) throw new Error('填一个目标余额')
  const diff = +(target - Number(a.balance)).toFixed(2)
  if (diff === 0) { adjId.value = ''; return }
  await recordTx({
    p_account_id: a.id, p_type: 'adjust', p_amount: Math.abs(diff),
    p_category: diff > 0 ? '+' : '-', p_note: '手动校准到 ' + target, p_occurred_at: null,
    p_peer_account_id: null, p_batch_id: null, p_loan_id: null, p_recurring_id: null,
  })
  adjId.value = ''; adjTarget.value = ''
})

const archive = (a) => {
  if (!confirm(`归档「${a.name}」?流水保留,账户从列表隐藏`)) return
  run(async () => {
    const { error } = await supabase.from('accounts').update({ archived: true }).eq('id', a.id)
    if (error) throw error
  })
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-bold"><button class="mr-1" @click="router.back()">‹</button> 账户管理</h1>
      <button class="text-sm" style="color: var(--c-net)" @click="showAdd = !showAdd">+ 新账户</button>
    </div>
    <p v-if="err" class="text-sm mb-3" style="color: var(--c-out)">{{ err }}</p>

    <div v-if="showAdd" class="card p-4 mb-4 space-y-3">
      <input v-model="nName" placeholder="账户名(如:招行卡/富途/余额宝)" class="w-full bg-transparent outline-none py-1" />
      <div class="flex gap-2">
        <select v-model="nType" class="flex-1 bg-transparent outline-none py-1">
          <option v-for="t in ACCOUNT_TYPES" :key="t.key" :value="t.key">{{ t.icon }} {{ t.label }}</option>
        </select>
        <select v-model="nCurrency" class="bg-transparent outline-none py-1">
          <option v-for="c in CURRENCIES" :key="c" :value="c">{{ c }}</option>
        </select>
      </div>
      <input v-model="nBalance" type="number" inputmode="decimal" placeholder="期初余额(现在有多少)" class="w-full bg-transparent outline-none py-1 tabular" />
      <button :disabled="busy" class="px-4 py-2 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="addAccount">建账户</button>
    </div>

    <div v-for="a in active" :key="a.id" class="card p-4 mb-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2.5">
          <span class="text-xl">{{ typeLabel[a.type]?.icon || '💼' }}</span>
          <div>
            <div>{{ a.name }}</div>
            <div class="text-xs" style="color: var(--ink-3)">{{ typeLabel[a.type]?.label }} · {{ a.currency }}</div>
          </div>
        </div>
        <div class="tabular font-semibold text-lg">{{ fmtMoney(a.balance, a.currency) }}</div>
      </div>
      <div class="flex gap-4 mt-2.5 text-xs">
        <button style="color: var(--c-net)" @click="adjId = adjId === a.id ? '' : a.id; adjTarget = a.balance">校准余额</button>
        <button style="color: var(--ink-3)" @click="archive(a)">归档</button>
      </div>
      <div v-if="adjId === a.id" class="flex gap-2 mt-2">
        <input v-model="adjTarget" type="number" inputmode="decimal" placeholder="实际余额" class="flex-1 card px-3 py-2 outline-none tabular text-sm" />
        <button :disabled="busy" class="px-4 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="adjust(a)">对平</button>
      </div>
    </div>

    <div v-if="!active.length && !showAdd" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      把现金、银行卡、券商、基金账户都建进来<br />随口报个余额就能开始
    </div>
  </div>
</template>
