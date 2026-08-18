<script setup>
// 账单导入:微信/支付宝/美团 → 解析 → 账户映射 → 预览 → 幂等入账
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, loadAll } from '../lib/store'
import { fmtCNY } from '../lib/fmt'
import { parseBill } from '../lib/billParse'

const router = useRouter()
const step = ref('pick')        // pick → map → importing → done
const err = ref('')
const parsed = ref(null)        // {platform, rows, skipped}
const mapping = ref({})         // methodRaw -> account_id
const progress = ref({ done: 0, total: 0, dup: 0, fail: 0 })

const accounts = computed(() => store.accounts.filter((a) => !a.archived && !['property', 'vehicle'].includes(a.type)))

const methods = computed(() => {
  if (!parsed.value) return []
  const m = {}
  for (const r of parsed.value.rows) m[r.methodRaw] = (m[r.methodRaw] || 0) + 1
  return Object.entries(m).sort((a, b) => b[1] - a[1]).map(([k, n]) => ({ k, n }))
})

function autoMap() {
  const map = {}
  for (const { k } of methods.value) {
    const tail = (k.match(/[(（](\d{4})[)）]/) || [])[1]
    const hit = accounts.value.find((a) => {
      const aTail = (a.name.match(/\((\d{4})\)/) || [])[1]
      if (tail && aTail && tail === aTail) return true
      if (k.includes('零钱') && a.name.includes('微信零钱')) return true
      if ((k === '账户余额' || k === '余额') && a.name.includes('支付宝余额')) return true
      if (k.startsWith('余额宝') && a.name === '余额宝') return true
      if (k.startsWith('花呗') && a.name === '花呗') return true
      if (k.includes('美团月付') && a.name === '美团月付') return true
      if (k.includes('抖音月付') && a.name === '抖音月付') return true
      return false
    })
    if (hit) map[k] = hit.id
  }
  mapping.value = map
}

const stats = computed(() => {
  if (!parsed.value) return null
  let inc = 0, exp = 0
  const dates = []
  for (const r of parsed.value.rows) {
    if (r.type === 'income') inc += r.amount; else exp += r.amount
    dates.push(r.date)
  }
  dates.sort()
  return { n: parsed.value.rows.length, inc, exp, from: dates[0], to: dates[dates.length - 1] }
})
const unmapped = computed(() => methods.value.filter((m) => !mapping.value[m.k]))

async function onPick(e) {
  const f = (e.target.files || [])[0]
  if (!f) return
  err.value = ''
  try {
    parsed.value = await parseBill(f)
    if (!parsed.value.rows.length) throw new Error('没解析到可入账的记录')
    autoMap()
    step.value = 'map'
  } catch (ex) { err.value = ex.message } finally { e.target.value = '' }
}

async function doImport() {
  if (unmapped.value.length) { err.value = '还有支付方式没选账户'; return }
  step.value = 'importing'
  err.value = ''
  const rows = parsed.value.rows
  progress.value = { done: 0, total: rows.length, dup: 0, fail: 0 }
  // 先查已存在的 import_id(去重预检,减少往返)
  const ids = rows.map((r) => r.importId)
  const existing = new Set()
  for (let i = 0; i < ids.length; i += 100) {
    const { data } = await supabase.from('transactions').select('import_id')
      .in('import_id', ids.slice(i, i + 100))
    for (const d of data || []) existing.add(d.import_id)
  }
  for (const r of rows) {
    if (existing.has(r.importId)) { progress.value.dup++; progress.value.done++; continue }
    try {
      const { error } = await supabase.rpc('record_tx', {
        p_account_id: mapping.value[r.methodRaw], p_type: r.type, p_amount: r.amount,
        p_category: r.category, p_note: r.note, p_occurred_at: r.date,
        p_peer_account_id: null, p_batch_id: null, p_loan_id: null, p_recurring_id: null,
        p_import_id: r.importId,
      })
      if (error) throw error
    } catch { progress.value.fail++ }
    progress.value.done++
  }
  try { await supabase.rpc('snapshot_net_worth') } catch { /* 忽略 */ }
  await loadAll()
  step.value = 'done'
}

function reset() { step.value = 'pick'; parsed.value = null; mapping.value = {}; err.value = '' }
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5">
    <h1 class="text-xl font-bold mb-2"><button class="mr-1" @click="router.back()">‹</button> 📑 账单导入</h1>
    <p class="text-[12px] mb-4" style="color: var(--ink-3)">
      支持:微信账单(.xlsx)、支付宝账单(.csv)、美团账单(.csv)。重复导入自动跳过,放心多导。淘宝/滴滴的消费都在支付宝账单里。
    </p>
    <p v-if="err" class="text-sm mb-3" style="color: var(--danger)">{{ err }}</p>

    <!-- 选文件 -->
    <template v-if="step === 'pick'">
      <label class="card block p-8 text-center cursor-pointer" style="border-style: dashed; border-width: 2px">
        <input type="file" accept=".xlsx,.xls,.csv" class="hidden" @change="onPick" />
        <div class="text-3xl mb-2">📄</div>
        <div class="text-sm" style="color: var(--ink-2)">点击选择账单文件</div>
        <div class="text-[11px] mt-1" style="color: var(--ink-3)">微信:钱包→账单→下载 · 支付宝:我的→账单→开具流水</div>
      </label>
      <div class="card p-4 mt-4 text-[12px] leading-relaxed" style="color: var(--ink-3)">
        💡 抖音账单是 PDF,发到「随手拍」由管家处理;账单里的充值/提现/理财等内部往来也建议交给管家精细入账。
      </div>
    </template>

    <!-- 映射+预览 -->
    <template v-else-if="step === 'map'">
      <div class="card p-4 mb-4">
        <div class="text-sm font-medium mb-2" style="color: var(--ink-2)">{{ parsed.platform }}账单 · 解析结果</div>
        <div class="text-[13px] space-y-1" style="color: var(--ink-2)">
          <div>时间:{{ stats.from }} ~ {{ stats.to }}</div>
          <div>可入账 <b>{{ stats.n }}</b> 笔:收入 <span class="tabular" style="color: var(--c-in)">{{ fmtCNY(stats.inc, true) }}</span>
            / 支出 <span class="tabular" style="color: var(--c-out)">{{ fmtCNY(stats.exp, true) }}</span></div>
          <div v-for="(v, k) in parsed.skipped" :key="k" class="text-[11px]" style="color: var(--ink-3)">已跳过 {{ k }}:{{ v }} 笔</div>
        </div>
      </div>

      <div class="card p-4 mb-4">
        <div class="text-sm font-medium mb-2" style="color: var(--ink-2)">支付方式 → 记到哪个账户</div>
        <div v-for="m in methods" :key="m.k" class="flex items-center gap-2 py-1.5">
          <span class="text-[13px] flex-1 min-w-0 truncate" :style="mapping[m.k] ? 'color: var(--ink-2)' : 'color: var(--danger)'">
            {{ m.k }} <span style="color: var(--ink-3)">×{{ m.n }}</span></span>
          <select v-model="mapping[m.k]" class="card px-2 py-1.5 text-[13px] outline-none max-w-[45%]">
            <option :value="undefined" disabled>选账户</option>
            <option v-for="a in accounts" :key="a.id" :value="a.id">{{ a.name }}</option>
          </select>
        </div>
      </div>

      <button class="w-full py-3 rounded-xl font-semibold" style="background: var(--c-net)" @click="doImport">
        确认导入 {{ stats.n }} 笔</button>
      <button class="w-full py-2.5 mt-2 text-sm" style="color: var(--ink-3)" @click="reset">重选文件</button>
    </template>

    <!-- 导入中 -->
    <template v-else-if="step === 'importing'">
      <div class="card p-6 text-center">
        <div class="text-2xl mb-2">⏳</div>
        <div class="text-sm mb-3" style="color: var(--ink-2)">正在入账 {{ progress.done }} / {{ progress.total }}</div>
        <div class="h-2 rounded-full overflow-hidden" style="background: var(--plane)">
          <div class="h-full rounded-full" style="background: linear-gradient(90deg, #8a6f35, #f2dda2); transition: width .2s"
            :style="{ width: (progress.done / Math.max(progress.total, 1) * 100) + '%' }"></div>
        </div>
      </div>
    </template>

    <!-- 完成 -->
    <template v-else>
      <div class="card p-6 text-center">
        <div class="text-3xl mb-2">✅</div>
        <div class="text-[15px] font-medium mb-1">导入完成</div>
        <div class="text-[13px]" style="color: var(--ink-2)">
          新入账 {{ progress.total - progress.dup - progress.fail }} 笔
          <template v-if="progress.dup"> · 重复跳过 {{ progress.dup }}</template>
          <template v-if="progress.fail"> · <span style="color: var(--danger)">失败 {{ progress.fail }}</span></template>
        </div>
        <div class="flex gap-2 mt-4">
          <button class="flex-1 py-2.5 rounded-xl text-sm" style="background: var(--c-net)" @click="router.push('/tx')">看流水</button>
          <button class="flex-1 py-2.5 rounded-xl text-sm border" style="border-color: var(--hairline); color: var(--ink-2)" @click="reset">再导一份</button>
        </div>
      </div>
    </template>
  </div>
</template>
