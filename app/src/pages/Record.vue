<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, recordTx, loadAll } from '../lib/store'
import { EXPENSE_CATS, INCOME_CATS, SAVE_WAYS, todayStr, fmtMoney } from '../lib/fmt'
import Icon from '../components/Icon.vue'

const router = useRouter()
const type = ref(new URLSearchParams(location.hash.split('?')[1] || '').get('t') === 'save' ? 'save' : 'expense')
const amount = ref('')
const category = ref('')
const note = ref('')
const date = ref(todayStr())
const accountId = ref('')
const peerId = ref('')
const batchId = ref('')
const busy = ref(false)
const err = ref('')
const ok = ref('')
const scanBusy = ref(false)
const scanMsg = ref('')
const ocrItemId = ref('')   // 本次识别对应的收件箱条目,入账后标记

async function cancelScan() {
  if (ocrItemId.value) {
    await supabase.from('inbox_items').update({ status: 'skipped', result: '用户放弃识别结果' }).eq('id', ocrItemId.value)
  }
  ocrItemId.value = ''; scanMsg.value = ''
  amount.value = ''; note.value = ''; category.value = ''; date.value = todayStr()
  type.value = 'expense'
}

async function onScanPick(e) {
  const f = (e.target.files || [])[0]
  if (!f) return
  scanBusy.value = true; scanMsg.value = '上传中…'; err.value = ''
  try {
    const ext = (f.name.split('.').pop() || 'jpg').toLowerCase()
    const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
    const { error: e1 } = await supabase.storage.from('inbox').upload(path, f)
    if (e1) throw e1
    const { data: row, error: e2 } = await supabase.from('inbox_items')
      .insert({ kind: 'image', path, note: '记账页拍单' }).select().single()
    if (e2) throw e2
    scanMsg.value = '🔍 识别中…'
    const { data, error: e3 } = await supabase.functions.invoke('ocr-inbox', { body: { id: row.id } })
    if (e3) throw e3
    const d = data?.draft
    if (!d || !d.is_bill) {
      scanMsg.value = ''
      err.value = '这张图不太像账单,你手动填一下吧'
      await supabase.from('inbox_items').update({ status: 'skipped', result: '识别:非账单' }).eq('id', row.id)
      return
    }
    // 回填表单
    ocrItemId.value = row.id
    type.value = d.direction === 'income' ? 'income' : 'expense'
    amount.value = d.amount || ''
    category.value = (type.value === 'income' ? INCOME_CATS : EXPENSE_CATS).includes(d.category) ? d.category : '其他'
    note.value = '拍单|' + (d.merchant || '')
    if (d.date) date.value = d.date
    const hint = (d.method || '')
    const hit = accounts.value.find((a) => {
      const base = a.name.replace(/\(.*?\)/g, '')
      const tail = (a.name.match(/\((\d{4})\)/) || [])[1]
      return (base && hint.includes(base)) || (tail && hint.includes(tail)) ||
        (hint.includes('美团月付') && a.name === '美团月付') || (hint.includes('零钱') && a.name.includes('微信零钱'))
    })
    if (hit) accountId.value = hit.id
    scanMsg.value = `✓ 识别好了${(d.confidence ?? 1) < 0.7 ? '(置信度低,核对一下)' : ',核对后点记入账本'}`
  } catch (ex) {
    scanMsg.value = ''
    err.value = '识别失败:' + (ex.message || ex)
  } finally {
    scanBusy.value = false
    e.target.value = ''
  }
}

// 账户排序:浦发第一,兴业第二,其余按近半年使用次数
const PIN = ['浦发银行卡(6197)', '兴业银行卡(1268)']
const accounts = computed(() => {
  const list = store.accounts.filter((a) => !a.archived && a.type !== 'loan' && a.type !== 'property' && a.type !== 'vehicle')
  const useCount = {}
  for (const t of store.recentTx) useCount[t.account_id] = (useCount[t.account_id] || 0) + 1
  return list.slice().sort((a, b) => {
    const pa = PIN.indexOf(a.name), pb = PIN.indexOf(b.name)
    if (pa !== -1 || pb !== -1) return (pa === -1 ? 99 : pa) - (pb === -1 ? 99 : pb)
    return (useCount[b.id] || 0) - (useCount[a.id] || 0)
  })
})
// 默认选中:上次用过的,否则排第一的
const lastAcc = localStorage.getItem('ll_last_acc')
if (accounts.value.length && !accountId.value) {
  accountId.value = accounts.value.some((a) => a.id === lastAcc) ? lastAcc : accounts.value[0].id
}

const cats = computed(() => (type.value === 'save' ? SAVE_WAYS : type.value === 'income' ? INCOME_CATS : EXPENSE_CATS))
const account = computed(() => accounts.value.find((a) => a.id === accountId.value))
const peers = computed(() => accounts.value.filter((a) => a.id !== accountId.value && a.currency === account.value?.currency))
const openBatches = computed(() => store.batches.filter((b) => !b.closed))
const memberName = (id) => store.members.find((m) => m.id === id)?.name || ''

async function submit() {
  err.value = ''; ok.value = ''
  const amt = Number(amount.value)
  if (!amt || amt <= 0) { err.value = '金额要大于 0'; return }
  if (type.value === 'save') {
    busy.value = true
    try {
      const { error } = await supabase.from('savings').insert({
        amount: amt, way: category.value || '其他', note: note.value, saved_at: date.value,
      })
      if (error) throw new Error(error.message)
      await loadAll()
      ok.value = '记下了,又省一笔 ✓'
      amount.value = ''; note.value = ''
      setTimeout(() => { ok.value = '' }, 1500)
    } catch (e) { err.value = e.message } finally { busy.value = false }
    return
  }
  if (!accountId.value) { err.value = '先选账户'; return }
  if (type.value === 'transfer' && !peerId.value) { err.value = '选一下转入账户'; return }
  busy.value = true
  try {
    const txId = await recordTx({
      p_account_id: accountId.value,
      p_type: type.value,
      p_amount: amt,
      p_category: category.value || (type.value === 'transfer' ? '转账' : '其他'),
      p_note: note.value,
      p_occurred_at: date.value,
      p_peer_account_id: type.value === 'transfer' ? peerId.value : null,
      p_batch_id: batchId.value || null,
      p_loan_id: null,
      p_recurring_id: null,
    })
    ok.value = '记好了 ✓'
    localStorage.setItem('ll_last_acc', accountId.value)
    if (ocrItemId.value) {
      await supabase.from('transactions').update({ verified: false }).eq('id', txId)
      await supabase.from('inbox_items').update({ status: 'done', result: '记账页拍单入账(待复核)' }).eq('id', ocrItemId.value)
      ocrItemId.value = ''
    }
    amount.value = ''; note.value = ''; batchId.value = ''
    setTimeout(() => { ok.value = '' }, 1500)
  } catch (e) {
    err.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center justify-between mb-3">
      <h1 class="text-xl font-bold">记一笔</h1>
      <button class="text-sm" style="color: var(--ink-3)" @click="router.push('/inbox')">收件箱 ›</button>
    </div>

    <!-- 拍单识别 -->
    <label class="scan-btn block p-4 mb-4 cursor-pointer">
      <div class="hero-sheen"></div>
      <input type="file" accept="image/*" class="hidden" @change="onScanPick" :disabled="scanBusy" />
      <div class="flex items-center gap-3">
        <span class="w-11 h-11 rounded-full flex items-center justify-center shrink-0" style="background: rgba(23,17,6,.18)">
          <Icon name="camera" :size="24" /></span>
        <div>
          <div class="font-bold text-[16px]">{{ scanBusy ? (scanMsg || '处理中…') : '拍小票 · 截图识别' }}</div>
          <div class="text-[12px]" style="opacity:.75">{{ scanBusy ? '几秒钟就好' : (scanMsg || '拍完自动填好账,你只管确认') }}</div>
        </div>
      </div>
    </label>
    <button v-if="ocrItemId" class="w-full -mt-2 mb-4 py-2 rounded-lg text-[13px] border"
      style="border-color: var(--hairline); color: var(--ink-3)" @click="cancelScan">
      ✕ 不要这次识别结果,清空重填</button>

    <!-- 类型 -->
    <div class="flex gap-2 mb-4">
      <button v-for="t in [['expense', '支出'], ['income', '收入'], ['transfer', '转账'], ['save', '省下']]" :key="t[0]"
        class="flex-1 py-2.5 rounded-xl text-sm font-medium border"
        :style="type === t[0]
          ? `background: ${t[0] === 'income' ? 'var(--c-in)' : t[0] === 'expense' ? 'var(--c-out)' : t[0] === 'save' ? 'var(--c-save)' : 'var(--c-net)'}; color:#fff; border-color: transparent`
          : 'border-color: var(--hairline); color: var(--ink-2); background: var(--surface-1)'"
        @click="type = t[0]; category = ''">{{ t[1] }}</button>
    </div>

    <div v-if="type !== 'save' && !accounts.length" class="card p-6 text-center">
      <p class="text-sm mb-3" style="color: var(--ink-2)">还没有可用账户</p>
      <button class="px-4 py-2 rounded-lg text-white text-sm" style="background: var(--c-net)"
        @click="router.push('/accounts')">先去建账户</button>
    </div>

    <template v-else>
      <!-- 金额 -->
      <div class="card p-4 mb-3">
        <input v-model="amount" type="number" inputmode="decimal" step="0.01" placeholder="0.00"
          class="w-full text-4xl font-semibold bg-transparent outline-none tabular" />
        <div class="text-xs mt-1" style="color: var(--ink-3)">{{ type === 'save' ? 'CNY · 没花出去的钱' : account?.currency || '' }}</div>
      </div>

      <!-- 账户 -->
      <div v-if="type !== 'save'" class="card p-4 mb-3 space-y-3">
        <div>
          <div class="text-xs mb-1.5" style="color: var(--ink-3)">{{ type === 'transfer' ? '转出账户' : '账户' }}</div>
          <select v-model="accountId" class="w-full bg-transparent outline-none py-1">
            <option v-for="a in accounts" :key="a.id" :value="a.id">{{ a.name }}({{ fmtMoney(a.balance, a.currency, true) }})</option>
          </select>
        </div>
        <div v-if="type === 'transfer'">
          <div class="text-xs mb-1.5" style="color: var(--ink-3)">转入账户(同币种)</div>
          <select v-model="peerId" class="w-full bg-transparent outline-none py-1">
            <option value="" disabled>选择</option>
            <option v-for="a in peers" :key="a.id" :value="a.id">{{ a.name }}</option>
          </select>
          <p v-if="!peers.length" class="text-xs mt-1" style="color: var(--c-out)">没有同币种账户;跨币种请分两笔记(支出+收入)</p>
        </div>
      </div>

      <!-- 分类 -->
      <div v-if="type !== 'transfer'" class="card p-4 mb-3">
        <div class="text-xs mb-2" style="color: var(--ink-3)">{{ type === 'save' ? '怎么省的' : '分类' }}</div>
        <div class="flex flex-wrap gap-2">
          <button v-for="c in cats" :key="c" class="px-3 py-1.5 rounded-full text-[13px] border"
            :style="category === c ? 'background: var(--c-net); color:#fff; border-color: transparent' : 'border-color: var(--hairline); color: var(--ink-2)'"
            @click="category = category === c ? '' : c">{{ c }}</button>
        </div>
      </div>

      <!-- 关联批次(给家人的钱) -->
      <div v-if="type === 'expense' && openBatches.length" class="card p-4 mb-3">
        <div class="text-xs mb-1.5" style="color: var(--ink-3)">关联家人批次(可选)</div>
        <select v-model="batchId" class="w-full bg-transparent outline-none py-1">
          <option value="">不关联</option>
          <option v-for="b in openBatches" :key="b.id" :value="b.id">{{ memberName(b.member_id) }} · {{ b.title || b.given_at }}</option>
        </select>
      </div>

      <!-- 备注 + 日期 -->
      <div class="card p-4 mb-4 space-y-3">
        <input v-model="note" :placeholder="type === 'save' ? '省在哪了(如:忍住没买音箱)' : '备注(可选)'" class="w-full bg-transparent outline-none" />
        <input v-model="date" type="date" class="w-full bg-transparent outline-none" />
      </div>

      <button :disabled="busy" class="w-full py-3.5 rounded-xl font-semibold text-white disabled:opacity-50"
        :style="{ background: type === 'save' ? 'var(--c-save)' : 'var(--c-net)' }" @click="submit">
        {{ busy ? '正在入账…' : type === 'save' ? '记一笔省下的' : '记入账本' }}
      </button>
      <p v-if="err" class="text-sm text-center mt-3" style="color: var(--danger)">{{ err }}</p>
      <p v-if="ok" class="text-sm text-center mt-3" style="color: var(--good-text)">{{ ok }}</p>
    </template>
  </div>
</template>
