<script setup>
// 随手拍收件箱:拍完自动识别出草稿 → 一键确认入账;识别错可改;取件员每晚复核
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, recordTx, loadAll } from '../lib/store'
import { EXPENSE_CATS, todayStr } from '../lib/fmt'

const router = useRouter()
const items = ref([])
const previews = ref({})
const busy = ref(false)
const ocrBusy = ref({})     // id -> 识别中
const confirmBusy = ref({})
const err = ref('')
const quickNote = ref('')
const doneCount = ref(0)
const editId = ref('')      // 展开编辑的条目
const viewer = ref('')      // 大图查看
const viewerZoom = ref(false)
function openViewer(it) {
  if (previews.value[it.id]) { viewer.value = previews.value[it.id]; viewerZoom.value = false }
}

const accounts = computed(() => store.accounts.filter((a) => !a.archived && !['loan','property','vehicle'].includes(a.type)))

function guessAccount(draft) {
  const hint = (draft?.method || '') + ''
  if (hint) {
    const hit = accounts.value.find((a) => hint.includes(a.name.replace(/\(.*?\)/g, '')) ||
      (hint.includes('月付') && a.name.includes('月付') && (hint.includes('美团') ? a.name.includes('美团') : true)) ||
      (/\((\d{4})\)/.test(a.name) && hint.includes(a.name.match(/\((\d{4})\)/)[1])))
    if (hit) return hit.id
    if (hint.includes('零钱') || hint.includes('微信')) {
      const wx = accounts.value.find((a) => a.name.includes('微信零钱')); if (wx) return wx.id
    }
  }
  const last = localStorage.getItem('ll_last_acc')
  if (accounts.value.some((a) => a.id === last)) return last
  return accounts.value[0]?.id
}

// 每个条目的可编辑草稿态
const edit = ref({})  // id -> {amount, category, account_id, direction}
function editState(it) {
  if (!edit.value[it.id]) {
    const d = it.draft || {}
    edit.value[it.id] = {
      amount: d.amount || '',
      category: d.category || '其他',
      account_id: guessAccount(d),
      direction: d.direction === 'income' ? 'income' : 'expense',
      merchant: d.merchant || '',
      date: d.date || it.created_at.slice(0, 10),
    }
  }
  return edit.value[it.id]
}

async function load() {
  const { data, error } = await supabase.from('inbox_items').select('*')
    .eq('status', 'pending').order('created_at', { ascending: false })
  if (error) { err.value = error.message; return }
  items.value = data || []
  store.inboxPending = items.value.length
  const { count } = await supabase.from('inbox_items').select('*', { count: 'exact', head: true }).eq('status', 'done')
  doneCount.value = count || 0
  for (const it of items.value) {
    if (it.kind === 'image' && it.path && !previews.value[it.id]) {
      const { data: s } = await supabase.storage.from('inbox').createSignedUrl(it.path, 3600)
      if (s?.signedUrl) previews.value[it.id] = s.signedUrl
    }
  }
}
onMounted(load)

async function runOcr(id) {
  ocrBusy.value[id] = true
  try {
    const { data, error } = await supabase.functions.invoke('ocr-inbox', { body: { id } })
    if (error) throw error
    const it = items.value.find((x) => x.id === id)
    if (it && data?.draft) { it.draft = data.draft; delete edit.value[id] }
  } catch (e) {
    err.value = '识别失败:' + (e.message || e)
  } finally {
    ocrBusy.value[id] = false
  }
}

async function onPick(e) {
  const files = [...(e.target.files || [])]
  if (!files.length) return
  busy.value = true; err.value = ''
  try {
    const newIds = []
    for (const f of files) {
      const kind = f.type.startsWith('audio') ? 'audio' : 'image'
      const ext = (f.name.split('.').pop() || 'bin').toLowerCase()
      const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
      const { error: e1 } = await supabase.storage.from('inbox').upload(path, f)
      if (e1) throw e1
      const { data: row, error: e2 } = await supabase.from('inbox_items').insert({ kind, path, note: '' }).select().single()
      if (e2) throw e2
      if (kind === 'image') newIds.push(row.id)
    }
    await load()
    for (const id of newIds) runOcr(id)  // 上传完自动识别
  } catch (ex) { err.value = ex.message } finally { busy.value = false; e.target.value = '' }
}

async function confirmBook(it) {
  const s = editState(it)
  const amt = Number(s.amount)
  if (!amt || amt <= 0) { err.value = '金额不对,改一下再确认'; return }
  if (!s.account_id) { err.value = '选个账户'; return }
  confirmBusy.value[it.id] = true; err.value = ''
  try {
    const txId = await recordTx({
      p_account_id: s.account_id, p_type: s.direction, p_amount: amt,
      p_category: s.category, p_note: '拍单|' + (s.merchant || it.note || '图片识别'),
      p_occurred_at: s.date || todayStr(), p_peer_account_id: null,
      p_batch_id: null, p_loan_id: null, p_recurring_id: null,
      p_import_id: 'inbox-' + it.id,
    })
    // 图片识别入账 → 标记待复核,取件员晚上对图核对
    await supabase.from('transactions').update({ verified: false }).eq('id', txId)
    await supabase.from('inbox_items').update({
      status: 'done', result: `已记:${s.category} ¥${amt}(待复核)`,
    }).eq('id', it.id)
    await load()
  } catch (e) { err.value = e.message } finally { confirmBusy.value[it.id] = false }
}

async function skipItem(it) {
  await supabase.from('inbox_items').update({ status: 'skipped', result: '手动标记:不是账单' }).eq('id', it.id)
  await load()
}

async function addText() {
  if (!quickNote.value.trim()) return
  busy.value = true; err.value = ''
  try {
    const { error } = await supabase.from('inbox_items').insert({ kind: 'text', note: quickNote.value.trim() })
    if (error) throw error
    quickNote.value = ''
    await load()
  } catch (ex) { err.value = ex.message } finally { busy.value = false }
}

async function saveNote(it) {
  await supabase.from('inbox_items').update({ note: it.note }).eq('id', it.id)
}

async function del(it) {
  if (!confirm('删掉这条?')) return
  if (it.path) await supabase.storage.from('inbox').remove([it.path])
  await supabase.from('inbox_items').delete().eq('id', it.id)
  await load()
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5">
    <div class="flex items-center justify-between mb-2">
      <h1 class="text-xl font-bold"><button class="mr-1" @click="router.back()">‹</button> 📥 随手拍</h1>
      <span class="text-xs" style="color: var(--ink-3)">已入账 {{ doneCount }} 条</span>
    </div>
    <p class="text-[12px] mb-4" style="color: var(--ink-3)">
      拍小票/截支付页,3秒出识别草稿,点确认就入账;识别错了改两下再确认。每晚取件员还会对图复核一遍。
    </p>
    <p v-if="err" class="text-sm mb-3" style="color: var(--danger)">{{ err }}</p>

    <label class="card block p-6 mb-3 text-center cursor-pointer" style="border-style: dashed; border-width: 2px">
      <input type="file" accept="image/*,audio/*" multiple class="hidden" @change="onPick" :disabled="busy" />
      <div class="text-3xl mb-1">📸</div>
      <div class="text-sm" style="color: var(--ink-2)">{{ busy ? '正在上传…' : '拍照 / 选图 / 传语音' }}</div>
    </label>

    <div class="flex gap-2 mb-5">
      <input v-model="quickNote" placeholder="或者打一句:加油200 兴业卡" class="flex-1 card px-3.5 py-2.5 outline-none text-[14px]"
        @keyup.enter="addText" />
      <button :disabled="busy || !quickNote.trim()" class="px-4 rounded-xl text-sm disabled:opacity-40"
        style="background: var(--c-net)" @click="addText">存</button>
    </div>

    <div v-if="!items.length" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      收件箱空空,好账清清
    </div>

    <div v-for="it in items" :key="it.id" class="card p-3 mb-3">
      <div class="flex gap-3">
        <img v-if="it.kind === 'image' && previews[it.id]" :src="previews[it.id]"
          class="w-16 h-16 rounded-lg object-cover shrink-0 cursor-zoom-in" @click="openViewer(it)" />
        <div v-else class="w-16 h-16 rounded-lg flex items-center justify-center text-2xl shrink-0" style="background: var(--plane)">
          {{ it.kind === 'audio' ? '🎙' : '✏️' }}</div>
        <div class="flex-1 min-w-0">
          <div class="text-[11px] mb-1" style="color: var(--ink-3)">
            {{ new Date(it.created_at).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }) }}
            <span v-if="ocrBusy[it.id]" style="color: var(--gold)"> · 🔍 识别中…</span>
          </div>

          <!-- 识别草稿 -->
          <template v-if="it.draft && it.draft.is_bill">
            <div class="text-[14px] font-medium">
              {{ editState(it).merchant || '账单' }}
              <span class="tabular font-bold" :style="editState(it).direction === 'income' ? 'color: var(--c-in)' : ''">
                ¥{{ editState(it).amount }}</span>
              <span v-if="(it.draft.confidence ?? 1) < 0.7" class="text-[11px] ml-1" style="color: var(--danger)">低置信⚠️</span>
            </div>
            <div class="text-[12px]" style="color: var(--ink-3)">
              建议:{{ editState(it).category }} · {{ accounts.find(a => a.id === editState(it).account_id)?.name || '选账户' }}
            </div>
          </template>
          <div v-else-if="it.draft && !it.draft.is_bill" class="text-[13px]" style="color: var(--ink-3)">
            识别:不像账单(可点改一下手动记)</div>
          <input v-else v-model="it.note" placeholder="补一句(哪张卡/干嘛的)" @blur="saveNote(it)"
            class="w-full bg-transparent outline-none text-[13px] border-b pb-1" style="border-color: var(--hairline)" />
        </div>
        <button class="text-xs self-start" style="color: var(--ink-3)" @click="del(it)">✕</button>
      </div>

      <!-- 操作行 -->
      <div v-if="it.kind === 'image'" class="flex gap-2 mt-2.5">
        <template v-if="it.draft">
          <button :disabled="confirmBusy[it.id]" class="flex-1 py-2 rounded-lg text-sm font-medium disabled:opacity-50"
            style="background: var(--c-net)" @click="confirmBook(it)">
            {{ confirmBusy[it.id] ? '入账中…' : '✓ 确认入账' }}</button>
          <button class="px-3 py-2 rounded-lg text-sm border" style="border-color: var(--hairline); color: var(--ink-2)"
            @click="editId = editId === it.id ? '' : it.id">✎ 改</button>
          <button class="px-3 py-2 rounded-lg text-sm border" style="border-color: var(--hairline); color: var(--ink-3)"
            @click="skipItem(it)">不是账单</button>
        </template>
        <button v-else-if="!ocrBusy[it.id]" class="px-3 py-2 rounded-lg text-sm border"
          style="border-color: var(--gold); color: var(--gold)" @click="runOcr(it.id)">🔍 识别</button>
      </div>

      <!-- 编辑区 -->
      <div v-if="editId === it.id && it.draft" class="mt-2.5 p-3 rounded-xl space-y-2" style="background: var(--plane)">
        <div class="flex gap-2">
          <input v-model="editState(it).amount" type="number" inputmode="decimal" placeholder="金额"
            class="w-28 card px-3 py-2 outline-none tabular text-sm" />
          <select v-model="editState(it).direction" class="card px-2 py-2 text-sm outline-none">
            <option value="expense">支出</option><option value="income">收入</option>
          </select>
          <select v-model="editState(it).category" class="card px-2 py-2 text-sm outline-none flex-1 min-w-0">
            <option v-for="c in EXPENSE_CATS" :key="c" :value="c">{{ c }}</option>
          </select>
        </div>
        <select v-model="editState(it).account_id" class="w-full card px-2 py-2 text-sm outline-none">
          <option v-for="a in accounts" :key="a.id" :value="a.id">{{ a.name }}</option>
        </select>
        <input v-model="editState(it).date" type="date" class="w-full card px-2 py-2 text-sm outline-none" />
      </div>
    </div>

    <!-- 大图查看 -->
    <div v-if="viewer" class="fixed inset-0 z-[100] flex items-center justify-center"
      style="background: rgba(4,4,6,.96)" @click.self="viewer = ''">
      <img :src="viewer" class="transition-transform duration-200"
        :class="viewerZoom ? 'max-w-none w-[180%] cursor-zoom-out' : 'max-w-full max-h-full object-contain cursor-zoom-in'"
        :style="viewerZoom ? 'transform-origin: center top' : ''"
        @click="viewerZoom = !viewerZoom" />
      <button class="fixed top-4 right-4 w-9 h-9 rounded-full text-lg"
        style="background: rgba(22,21,26,.9); border: 1px solid var(--hairline); color: var(--ink-1)"
        @click="viewer = ''">✕</button>
      <div class="fixed bottom-6 inset-x-0 text-center text-[12px]" style="color: var(--ink-3)">点图片放大/缩小 · 点空白处关闭</div>
    </div>
  </div>
</template>
