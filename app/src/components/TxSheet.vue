<script setup>
import { computed, ref } from 'vue'
import { deleteTx } from '../lib/store'
import { fmtMoney, fmtDate } from '../lib/fmt'
import { txSign, txColor, isRepay } from '../lib/txkit'

const props = defineProps({ item: Object, accMap: Object })
const emit = defineEmits(['close'])

const tx = computed(() => (props.item.pair ? props.item.out : props.item.t))
const busy = ref(false)
const err = ref('')

const kindLabel = computed(() => {
  if (props.item.pair) return isRepay(props.item.out) ? '还款转账' : '内部转账'
  const t = props.item.t
  return { income: '收入', expense: isRepay(t) ? '还款支出' : '支出', adjust: '余额校准', transfer_out: '转出', transfer_in: '转入' }[t.type] || t.type
})
const amountColor = computed(() => {
  if (props.item.pair) return isRepay(props.item.out) ? 'var(--gold)' : 'var(--ink-1)'
  return txColor(props.item.t)
})

async function del() {
  const label = `${tx.value.category} ${fmtMoney(tx.value.amount, props.accMap[tx.value.account_id]?.currency)}`
  if (!confirm(`删掉这笔?余额会同步回滚\n${label}`)) return
  busy.value = true
  err.value = ''
  try {
    await deleteTx(tx.value.id)
    emit('close')
  } catch (e) {
    err.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <teleport to="body">
    <div class="fixed inset-0 z-50 fab-backdrop" @click="emit('close')"></div>
    <div class="fixed inset-x-0 bottom-0 z-50 sheet-up rounded-t-3xl px-6 pt-5"
      style="background: var(--surface-1); border-top: 1px solid var(--hairline); padding-bottom: calc(env(safe-area-inset-bottom, 0px) + 1.5rem)">
      <div class="w-10 h-1 rounded-full mx-auto mb-5" style="background: var(--baseline)"></div>
      <div class="text-center mb-5">
        <div class="text-sm mb-1" style="color: var(--ink-3)">
          {{ kindLabel }} · {{ tx.category }}<span v-if="!item.pair && isRepay(tx) && tx.type === 'expense'" class="repay-badge">还款</span>
        </div>
        <div class="text-[32px] font-bold tabular" :style="{ color: amountColor }">
          {{ item.pair ? '' : txSign(tx) }}{{ fmtMoney(tx.amount, accMap[tx.account_id]?.currency) }}
        </div>
      </div>
      <div class="text-[14px]">
        <div v-if="item.pair" class="sheet-row">
          <span>资金流向</span><b class="text-right">{{ accMap[item.out.account_id]?.name }} → {{ accMap[item.tin.account_id]?.name }}</b>
        </div>
        <div v-else class="sheet-row">
          <span>账户</span><b>{{ accMap[tx.account_id]?.name }}</b>
        </div>
        <div class="sheet-row"><span>日期</span><b>{{ fmtDate(tx.occurred_at) }}</b></div>
        <div v-if="tx.note" class="sheet-row">
          <span>备注</span><b class="text-right" style="max-width: 70%">{{ tx.note }}</b>
        </div>
        <div v-if="tx.import_id" class="sheet-row">
          <span>凭证号</span><b class="text-xs" style="color: var(--ink-3)">{{ tx.import_id }}</b>
        </div>
        <div v-if="tx.verified === false" class="sheet-row">
          <span>AI 记账</span><b style="color: var(--gold)">今晚管家复核</b>
        </div>
      </div>
      <p v-if="err" class="text-sm mt-3" style="color: var(--danger)">{{ err }}</p>
      <button class="w-full mt-5 py-3 rounded-xl text-[15px] disabled:opacity-40"
        style="border: 1px solid rgba(224,86,77,.45); color: var(--danger)"
        :disabled="busy" @click="del">
        {{ busy ? '删除中…' : (item.pair ? '删除这笔转账(两腿一起删,余额回滚)' : '删除这笔(余额回滚)') }}
      </button>
    </div>
  </teleport>
</template>
