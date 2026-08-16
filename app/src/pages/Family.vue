<script setup>
import { ref, computed } from 'vue'
import { supabase } from '../lib/supabase'
import { store, loadAll, batchSpent } from '../lib/store'
import { fmtMoney, todayStr, fmtDate, CURRENCIES } from '../lib/fmt'

const err = ref('')
const busy = ref(false)

// 新成员
const showAddMember = ref(false)
const mName = ref('')
const mRel = ref('')

// 新批次
const showAddBatch = ref('')  // member_id
const bAmount = ref('')
const bTitle = ref('')
const bCurrency = ref('CNY')

// 报花销
const showSpend = ref('')     // batch_id
const sAmount = ref('')
const sNote = ref('')

// 展开的成员
const open = ref('')

const activeMembers = computed(() => store.members.filter((m) => !m.archived))
const memberBatches = (mid) => store.batches.filter((b) => b.member_id === mid)

function batchRemain(b) {
  return Number(b.amount) - batchSpent(b.id)
}
function memberRemain(mid) {
  return memberBatches(mid).filter((b) => !b.closed).reduce((s, b) => s + batchRemain(b), 0)
}

async function run(fn) {
  err.value = ''; busy.value = true
  try { await fn(); await loadAll() } catch (e) { err.value = e.message } finally { busy.value = false }
}

const addMember = () => run(async () => {
  if (!mName.value.trim()) throw new Error('名字不能空')
  const { error } = await supabase.from('members').insert({ name: mName.value.trim(), relation: mRel.value.trim() })
  if (error) throw error
  mName.value = ''; mRel.value = ''; showAddMember.value = false
})

const addBatch = (mid) => run(async () => {
  const amt = Number(bAmount.value)
  if (!amt || amt <= 0) throw new Error('金额要大于 0')
  const { error } = await supabase.from('batches').insert({
    member_id: mid, amount: amt, currency: bCurrency.value,
    title: bTitle.value.trim() || todayStr().slice(0, 7).replace('-', '年') + '月',
    given_at: todayStr(),
  })
  if (error) throw error
  bAmount.value = ''; bTitle.value = ''; showAddBatch.value = ''
})

const addSpend = (bid) => run(async () => {
  const amt = Number(sAmount.value)
  if (!amt || amt <= 0) throw new Error('金额要大于 0')
  const { error } = await supabase.from('batch_expenses').insert({
    batch_id: bid, amount: amt, note: sNote.value.trim(), spent_at: todayStr(),
  })
  if (error) throw error
  sAmount.value = ''; sNote.value = ''; showSpend.value = ''
})

const delSpend = (e) => {
  if (!confirm(`删掉这笔花销 ${e.amount}?`)) return
  run(async () => {
    const { error } = await supabase.from('batch_expenses').delete().eq('id', e.id)
    if (error) throw error
  })
}

const toggleClose = (b) => run(async () => {
  const { error } = await supabase.from('batches').update({ closed: !b.closed }).eq('id', b.id)
  if (error) throw error
})

const batchExpenses = (bid) => store.batchExpenses.filter((e) => e.batch_id === bid)
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-bold">家人的钱</h1>
      <button class="text-sm" style="color: var(--c-net)" @click="showAddMember = !showAddMember">+ 添加成员</button>
    </div>
    <p v-if="err" class="text-sm mb-3" style="color: var(--c-out)">{{ err }}</p>

    <div v-if="showAddMember" class="card p-4 mb-4 space-y-2">
      <input v-model="mName" placeholder="称呼(如:媳妇/爸/妈)" class="w-full bg-transparent outline-none py-1" />
      <input v-model="mRel" placeholder="关系(可选)" class="w-full bg-transparent outline-none py-1" />
      <button :disabled="busy" class="px-4 py-2 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="addMember">保存</button>
    </div>

    <div v-if="!activeMembers.length && !showAddMember" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      给家人的每一笔钱,开一个批次单独跟<br />先添加一位成员
    </div>

    <div v-for="m in activeMembers" :key="m.id" class="card p-4 mb-4">
      <div class="flex items-center justify-between" @click="open = open === m.id ? '' : m.id">
        <div>
          <span class="font-medium">{{ m.name }}</span>
          <span v-if="m.relation" class="text-xs ml-1.5" style="color: var(--ink-3)">{{ m.relation }}</span>
        </div>
        <div class="text-sm tabular" :style="memberRemain(m.id) < 0 ? 'color: var(--c-out)' : 'color: var(--ink-2)'">
          在手约 {{ fmtMoney(memberRemain(m.id), 'CNY', true) }} <span style="color: var(--ink-3)">{{ open === m.id ? '▾' : '▸' }}</span>
        </div>
      </div>

      <template v-if="open === m.id">
        <div class="mt-3 pt-3 border-t" style="border-color: var(--hairline)">
          <button class="text-sm mb-2" style="color: var(--c-net)" @click="showAddBatch = showAddBatch === m.id ? '' : m.id">+ 给一笔钱(开批次)</button>
          <div v-if="showAddBatch === m.id" class="rounded-xl p-3 mb-3 space-y-2" style="background: var(--plane)">
            <input v-model="bAmount" type="number" inputmode="decimal" placeholder="金额" class="w-full bg-transparent outline-none py-1 tabular" />
            <div class="flex gap-2">
              <input v-model="bTitle" placeholder="用途(如:8月生活费)" class="flex-1 bg-transparent outline-none py-1" />
              <select v-model="bCurrency" class="bg-transparent outline-none">
                <option v-for="c in CURRENCIES" :key="c" :value="c">{{ c }}</option>
              </select>
            </div>
            <p class="text-xs" style="color: var(--ink-3)">提醒:这里只开跟踪批次;钱从哪个账户出,去「记账」记一笔支出并关联本批次</p>
            <button :disabled="busy" class="px-4 py-2 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="addBatch(m.id)">开批次</button>
          </div>

          <div v-for="b in memberBatches(m.id)" :key="b.id" class="mb-3 rounded-xl p-3" style="background: var(--plane)"
            :class="b.closed ? 'opacity-60' : ''">
            <div class="flex items-center justify-between">
              <div>
                <div class="text-[15px]">{{ b.title }}</div>
                <div class="text-xs" style="color: var(--ink-3)">{{ fmtDate(b.given_at) }} 给了 {{ fmtMoney(b.amount, b.currency) }}</div>
              </div>
              <div class="text-right">
                <div class="tabular font-medium" :style="batchRemain(b) < 0 ? 'color: var(--c-out)' : ''">
                  剩 {{ fmtMoney(batchRemain(b), b.currency) }}</div>
                <div class="text-xs" style="color: var(--ink-3)">已花 {{ fmtMoney(batchSpent(b.id), b.currency, true) }}</div>
              </div>
            </div>

            <div v-for="e in batchExpenses(b.id)" :key="e.id" class="flex items-center justify-between mt-2 text-sm">
              <span class="truncate" style="color: var(--ink-2)">{{ fmtDate(e.spent_at) }} {{ e.note || '花销' }}</span>
              <span class="flex items-center gap-2 pl-2">
                <span class="tabular">-{{ fmtMoney(e.amount, b.currency) }}</span>
                <button class="text-xs" style="color: var(--ink-3)" @click="delSpend(e)">✕</button>
              </span>
            </div>

            <div class="flex gap-3 mt-2.5">
              <button v-if="!b.closed" class="text-xs" style="color: var(--c-net)"
                @click="showSpend = showSpend === b.id ? '' : b.id">+ 报一笔花销</button>
              <button class="text-xs" style="color: var(--ink-3)" @click="toggleClose(b)">{{ b.closed ? '重新打开' : '结清关闭' }}</button>
            </div>
            <div v-if="showSpend === b.id" class="flex gap-2 mt-2">
              <input v-model="sAmount" type="number" inputmode="decimal" placeholder="金额" class="w-24 card px-2 py-1.5 outline-none tabular text-sm" />
              <input v-model="sNote" placeholder="干什么花的" class="flex-1 card px-2 py-1.5 outline-none text-sm" />
              <button :disabled="busy" class="px-3 rounded-lg text-white text-sm" style="background: var(--c-net)" @click="addSpend(b.id)">记</button>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
