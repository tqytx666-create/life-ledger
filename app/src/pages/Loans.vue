<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, loadAll } from '../lib/store'
import { fmtMoney, CURRENCIES } from '../lib/fmt'

const router = useRouter()
const err = ref('')
const busy = ref(false)
const showAdd = ref(false)

const f = ref({ name: '', currency: 'CNY', principal_remaining: '', rate_annual: '', monthly_payment: '', payment_day: 1, pay_account_id: '' })
const prepayId = ref('')
const prepayAmt = ref('')

const activeLoans = computed(() => store.loans.filter((l) => !l.archived))
const payAccounts = computed(() => store.accounts.filter((a) => !a.archived && a.type !== 'loan'))
const accName = (id) => store.accounts.find((a) => a.id === id)?.name || '未设置'

async function run(fn) {
  err.value = ''; busy.value = true
  try { await fn(); await loadAll() } catch (e) { err.value = e.message } finally { busy.value = false }
}

const addLoan = () => run(async () => {
  const v = f.value
  if (!v.name.trim()) throw new Error('贷款名不能空')
  if (!Number(v.principal_remaining) || !Number(v.monthly_payment)) throw new Error('剩余本金和月供都要填')
  if (!v.pay_account_id) throw new Error('选一个扣月供的账户')
  const payAcc = payAccounts.value.find((a) => a.id === v.pay_account_id)
  if (payAcc.currency !== v.currency) throw new Error('扣款账户币种要和贷款一致')
  const { error } = await supabase.from('loans').insert({
    name: v.name.trim(), currency: v.currency,
    principal_remaining: Number(v.principal_remaining),
    rate_annual: Number(v.rate_annual) || 0,
    monthly_payment: Number(v.monthly_payment),
    payment_day: Number(v.payment_day) || 1,
    pay_account_id: v.pay_account_id,
    // 游标置为当前月:过去的月供不补记,从下个还款日开始自动记
    settled_through: new Date().toISOString().slice(0, 7),
  })
  if (error) throw error
  showAdd.value = false
  f.value = { name: '', currency: 'CNY', principal_remaining: '', rate_annual: '', monthly_payment: '', payment_day: 1, pay_account_id: '' }
})

const prepay = (l) => run(async () => {
  const amt = Number(prepayAmt.value)
  if (!amt || amt <= 0) throw new Error('金额要大于 0')
  if (!confirm(`确认提前还「${l.name}」 ${fmtMoney(amt, l.currency)}?会从「${accName(l.pay_account_id)}」扣钱`)) return
  const { error } = await supabase.rpc('prepay_loan', { p_loan_id: l.id, p_amount: amt, p_note: '' })
  if (error) throw error
  prepayId.value = ''; prepayAmt.value = ''
})

const archive = (l) => {
  if (!confirm(`归档「${l.name}」?不再自动记月供`)) return
  run(async () => {
    const { error } = await supabase.from('loans').update({ archived: true }).eq('id', l.id)
    if (error) throw error
  })
}

function monthlyInterest(l) {
  return +(Number(l.principal_remaining) * Number(l.rate_annual) / 100 / 12).toFixed(2)
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-bold"><button class="mr-1" @click="router.back()">‹</button> 按揭贷款</h1>
      <button class="text-sm" style="color: var(--c-net)" @click="showAdd = !showAdd">+ 添加贷款</button>
    </div>
    <p v-if="err" class="text-sm mb-3" style="color: var(--c-out)">{{ err }}</p>

    <div v-if="showAdd" class="card p-4 mb-4 space-y-3">
      <input v-model="f.name" placeholder="名称(如:XX花园房贷)" class="w-full bg-transparent outline-none py-1" />
      <div class="flex gap-2">
        <input v-model="f.principal_remaining" type="number" inputmode="decimal" placeholder="当前剩余本金" class="flex-1 bg-transparent outline-none py-1 tabular" />
        <select v-model="f.currency" class="bg-transparent outline-none">
          <option v-for="c in CURRENCIES" :key="c" :value="c">{{ c }}</option>
        </select>
      </div>
      <div class="flex gap-2">
        <input v-model="f.monthly_payment" type="number" inputmode="decimal" placeholder="月供" class="flex-1 bg-transparent outline-none py-1 tabular" />
        <input v-model="f.rate_annual" type="number" inputmode="decimal" placeholder="年利率%" class="w-24 bg-transparent outline-none py-1 tabular" />
      </div>
      <div class="flex items-center gap-2 text-sm">
        <span style="color: var(--ink-3)">每月</span>
        <input v-model="f.payment_day" type="number" min="1" max="28" class="w-14 bg-transparent outline-none py-1 tabular text-center card rounded-lg" />
        <span style="color: var(--ink-3)">号,从</span>
        <select v-model="f.pay_account_id" class="flex-1 bg-transparent outline-none py-1">
          <option value="" disabled>选账户</option>
          <option v-for="a in payAccounts" :key="a.id" :value="a.id">{{ a.name }}({{ a.currency }})</option>
        </select>
        <span style="color: var(--ink-3)">扣</span>
      </div>
      <p class="text-xs" style="color: var(--ink-3)">保存后从下个还款日起自动记月供并递减本金;历史月供不补记</p>
      <button :disabled="busy" class="px-4 py-2 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="addLoan">保存</button>
    </div>

    <div v-for="l in activeLoans" :key="l.id" class="card p-4 mb-3">
      <div class="flex items-center justify-between">
        <div class="font-medium">{{ l.name }}</div>
        <div class="tabular font-semibold" style="color: var(--c-out)">剩 {{ fmtMoney(l.principal_remaining, l.currency) }}</div>
      </div>
      <div class="text-xs mt-1.5 space-y-0.5" style="color: var(--ink-3)">
        <div>月供 {{ fmtMoney(l.monthly_payment, l.currency) }} · 每月{{ l.payment_day }}号从「{{ accName(l.pay_account_id) }}」自动扣</div>
        <div>年利率 {{ l.rate_annual }}% · 本月利息约 {{ fmtMoney(monthlyInterest(l), l.currency) }} · 已结算到 {{ l.settled_through || '—' }}</div>
      </div>
      <div class="flex gap-4 mt-2.5 text-xs">
        <button style="color: var(--c-net)" @click="prepayId = prepayId === l.id ? '' : l.id">提前还款</button>
        <button style="color: var(--ink-3)" @click="archive(l)">归档</button>
      </div>
      <div v-if="prepayId === l.id" class="flex gap-2 mt-2">
        <input v-model="prepayAmt" type="number" inputmode="decimal" placeholder="还多少本金" class="flex-1 card px-3 py-2 outline-none tabular text-sm" />
        <button :disabled="busy" class="px-4 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="prepay(l)">还</button>
      </div>
    </div>

    <div v-if="!activeLoans.length && !showAdd" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      把房贷加进来,每月自动记月供、本金自动递减
    </div>
  </div>
</template>
