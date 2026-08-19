<script setup>
import { ref, computed, watch } from 'vue'
import { supabase } from '../lib/supabase'
import { store, loadAll } from '../lib/store'
import { fmtMoney, fmtCNY, fmtDate } from '../lib/fmt'
import { txSign as sign, txColor as color, typeName, isRepay, mergePairs } from '../lib/txkit'
import TxSheet from '../components/TxSheet.vue'

const filter = ref('all')
const busyId = ref('')
const err = ref('')

// 筛选:月份(可查任意久远月份)/分类/关键词
const monthSel = ref('all')
const catSel = ref('all')
const kw = ref('')
const extTx = ref([])       // 选中窗口外月份时按月单独拉取
const extLoading = ref(false)

const monthOptions = computed(() => {
  const opts = []
  const d = new Date()
  for (let i = 0; i < 18; i++) {
    const m = new Date(d.getFullYear(), d.getMonth() - i, 1)
    opts.push(`${m.getFullYear()}-${String(m.getMonth() + 1).padStart(2, '0')}`)
  }
  return opts
})

watch(monthSel, async (m) => {
  catSel.value = 'all'
  if (m === 'all') { extTx.value = []; return }
  extLoading.value = true
  try {
    const from = m + '-01'
    const [y, mo] = m.split('-').map(Number)
    const to = `${mo === 12 ? y + 1 : y}-${String(mo === 12 ? 1 : mo + 1).padStart(2, '0')}-01`
    const { data, error } = await supabase.from('transactions').select('*')
      .gte('occurred_at', from).lt('occurred_at', to)
      .order('occurred_at', { ascending: false }).order('created_at', { ascending: false }).limit(2000)
    if (error) throw error
    extTx.value = data || []
  } catch (e) { err.value = e.message } finally { extLoading.value = false }
})

const accMap = computed(() => Object.fromEntries(store.accounts.map((a) => [a.id, a])))

const baseList = computed(() => (monthSel.value === 'all' ? store.recentTx : extTx.value))

const filtered = computed(() => {
  let list = baseList.value
  if (filter.value === 'income') list = list.filter((t) => t.type === 'income')
  else if (filter.value === 'expense') list = list.filter((t) => t.type === 'expense')
  else if (filter.value === 'transfer') list = list.filter((t) => t.type.startsWith('transfer'))
  if (catSel.value !== 'all') list = list.filter((t) => t.category === catSel.value)
  const k = kw.value.trim()
  if (k) list = list.filter((t) => (t.note || '').includes(k) || (t.category || '').includes(k))
  return list
})

// 当前类型下出现过的分类(动态,含金额小计)
const catOptions = computed(() => {
  let list = baseList.value
  if (filter.value === 'income') list = list.filter((t) => t.type === 'income')
  else if (filter.value === 'expense') list = list.filter((t) => t.type === 'expense')
  else if (filter.value === 'transfer') list = list.filter((t) => t.type.startsWith('transfer'))
  const s = {}
  for (const t of list) { if (t.type === 'transfer_in') continue; s[t.category] = (s[t.category] || 0) + 1 }
  return Object.entries(s).sort((a, b) => b[1] - a[1]).map(([c, n]) => ({ c, n }))
})

// 当前筛选结果小计(折CNY)
const sumShown = computed(() => {
  let t = 0
  for (const x of filtered.value) {
    if (x.type !== 'income' && x.type !== 'expense') continue
    t += (x.type === 'income' ? 1 : -1) * Number(x.amount) * (store.fx[accMap.value[x.account_id]?.currency] ?? 1)
  }
  return t
})

// 转账两条腿合并 + 按日分组
const groups = computed(() => {
  const g = {}
  for (const it of mergePairs(filtered.value)) {
    ;(g[it.occurred_at] ||= []).push(it)
  }
  return Object.entries(g).sort((a, b) => b[0].localeCompare(a[0]))
})

// 详情抽屉
const detail = ref(null)
function openDetail(it) { detail.value = it }

// 省钱记录:按日分组 + 删除(不涉及余额)
const saveGroups = computed(() => {
  const g = {}
  for (const s of store.savings) (g[s.saved_at] ||= []).push(s)
  return Object.entries(g).sort((a, b) => b[0].localeCompare(a[0]))
})
async function delSave(s) {
  if (!confirm(`删掉这笔省钱记录?\n${s.way} ${fmtCNY(s.amount)}`)) return
  busyId.value = s.id
  err.value = ''
  try {
    const { error } = await supabase.from('savings').delete().eq('id', s.id)
    if (error) throw new Error(error.message)
    await loadAll()
  } catch (e) {
    err.value = e.message
  } finally {
    busyId.value = ''
  }
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-bold">流水</h1>
      <button class="text-sm" style="color: var(--gold)" @click="$router.push('/import')">📑 导账单 ›</button>
    </div>

    <div class="flex gap-2 mb-3">
      <button v-for="f in [['all', '全部'], ['expense', '支出'], ['income', '收入'], ['transfer', '转账'], ['save', '省下']]" :key="f[0]"
        class="px-3.5 py-1.5 rounded-full text-[13px] border"
        :style="filter === f[0] ? 'background: var(--c-net); color:#fff; border-color:transparent' : 'border-color: var(--hairline); color: var(--ink-2)'"
        @click="filter = f[0]; catSel = 'all'">{{ f[1] }}</button>
    </div>

    <!-- 月份 / 分类 / 搜索 -->
    <div v-if="filter !== 'save'" class="flex gap-2 mb-3">
      <select v-model="monthSel" class="card px-2.5 py-2 text-[13px] outline-none">
        <option value="all">近半年</option>
        <option v-for="m in monthOptions" :key="m" :value="m">{{ m.replace('-', '年') }}月</option>
      </select>
      <select v-model="catSel" class="card px-2.5 py-2 text-[13px] outline-none flex-1 min-w-0">
        <option value="all">全部分类</option>
        <option v-for="o in catOptions" :key="o.c" :value="o.c">{{ o.c }}({{ o.n }})</option>
      </select>
    </div>
    <input v-if="filter !== 'save'" v-model="kw" placeholder="🔍 搜商家/备注/分类,如:美团、房租、Apple"
      class="w-full card px-3.5 py-2.5 mb-3 text-[14px] outline-none" />
    <div v-if="filter !== 'save' && (monthSel !== 'all' || catSel !== 'all' || kw)" class="text-xs mb-3 px-1" style="color: var(--ink-3)">
      {{ extLoading ? '正在拉取…' : `筛出 ${filtered.length} 笔,收支净额 ${sumShown >= 0 ? '+' : ''}${fmtCNY(sumShown)}` }}
    </div>

    <p v-if="err" class="text-sm mb-3" style="color: var(--danger)">{{ err }}</p>

    <!-- 省钱记录视图 -->
    <template v-if="filter === 'save'">
      <div v-if="!saveGroups.length" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
        还没记过省下的钱<br />忍住没买、用了优惠券,都值得记一笔
      </div>
      <div v-for="[date, list] in saveGroups" :key="date" class="mb-4">
        <div class="text-xs mb-1.5 px-1" style="color: var(--ink-3)">{{ fmtDate(date) }}</div>
        <div class="card px-4">
          <div v-for="s in list" :key="s.id"
            class="flex items-center justify-between py-3 border-b last:border-0" style="border-color: var(--hairline)">
            <div class="min-w-0 flex-1">
              <div class="text-[15px] truncate">{{ s.way }}</div>
              <div v-if="s.note" class="text-xs truncate" style="color: var(--ink-3)">{{ s.note }}</div>
            </div>
            <div class="flex items-center gap-3 pl-2">
              <span class="tabular font-medium" style="color: var(--c-save)">省{{ fmtCNY(s.amount) }}</span>
              <button class="text-xs px-1.5 py-1 disabled:opacity-40" style="color: var(--ink-3)"
                :disabled="busyId === s.id" @click="delSave(s)">{{ busyId === s.id ? '…' : '✕' }}</button>
            </div>
          </div>
        </div>
      </div>
    </template>

    <div v-else-if="!groups.length" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      近半年还没有这类流水
    </div>

    <div v-if="filter !== 'save'" v-for="[date, list] in groups" :key="date" class="mb-4">
      <div class="text-xs mb-1.5 px-1" style="color: var(--ink-3)">{{ fmtDate(date) }}</div>
      <div class="card px-4">
        <div v-for="it in list" :key="it.id"
          class="flex items-center justify-between py-3 border-b last:border-0 cursor-pointer active:opacity-70"
          style="border-color: var(--hairline)" @click="openDetail(it)">
          <!-- 合并的转账行:A → B 一行 -->
          <template v-if="it.pair">
            <div class="min-w-0 flex-1">
              <div class="text-[15px] truncate">
                {{ it.out.category }}
                <span v-if="isRepay(it.out)" class="repay-badge">还款</span>
              </div>
              <div class="text-xs truncate" style="color: var(--ink-3)">
                {{ accMap[it.out.account_id]?.name }} → {{ accMap[it.tin.account_id]?.name }}
              </div>
            </div>
            <span class="tabular font-medium pl-2" :style="{ color: isRepay(it.out) ? 'var(--gold)' : 'var(--ink-2)' }">
              {{ fmtMoney(it.out.amount, accMap[it.out.account_id]?.currency) }}
            </span>
          </template>
          <!-- 普通行 -->
          <template v-else>
            <div class="min-w-0 flex-1">
              <div class="text-[15px] truncate">
                {{ it.t.category }}<span v-if="typeName(it.t)" class="text-xs ml-1" style="color: var(--ink-3)">{{ typeName(it.t) }}</span>
                <span v-if="it.t.type === 'expense' && isRepay(it.t)" class="repay-badge">还款</span>
              </div>
              <div class="text-xs truncate" style="color: var(--ink-3)">
                {{ accMap[it.t.account_id]?.name }}<span v-if="it.t.note"> · {{ it.t.note }}</span>
              </div>
            </div>
            <span class="tabular font-medium pl-2" :style="{ color: color(it.t) }">
              {{ sign(it.t) }}{{ fmtMoney(it.t.amount, accMap[it.t.account_id]?.currency) }}
            </span>
          </template>
        </div>
      </div>
    </div>

    <!-- 流水详情抽屉 -->
    <TxSheet v-if="detail" :item="detail" :accMap="accMap" @close="detail = null" />
  </div>
</template>
