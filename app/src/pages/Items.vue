<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, loadAll, toCNY } from '../lib/store'
import { fmtCNY, fmtDate } from '../lib/fmt'
import Icon from '../components/Icon.vue'

const router = useRouter()
const tab = ref('trial')
const busy = ref('')
const err = ref('')

const TABS = [
  ['trial', '试用期'], ['kept', '在用'], ['idle', '闲置'], ['selling', '在卖'], ['done', '已处理'],
]
const DONE = ['sold', 'returned', 'consumed']

const list = computed(() => store.items.filter((i) => (tab.value === 'done' ? DONE.includes(i.status) : i.status === tab.value)))
const counts = computed(() => {
  const c = {}
  for (const i of store.items) {
    const k = DONE.includes(i.status) ? 'done' : i.status
    c[k] = (c[k] || 0) + 1
  }
  return c
})
const assetTotal = computed(() => store.items
  .filter((i) => ['kept', 'idle', 'selling'].includes(i.status))
  .reduce((s, i) => s + Number(i.value), 0))

function daysSince(d) { return Math.floor((Date.now() - new Date(d).getTime()) / 864e5) }
function trialBadge(i) {
  const left = 7 - daysSince(i.bought_at)
  if (left > 2) return { text: `退货窗口剩 ${left} 天`, color: 'var(--ink-3)' }
  if (left >= 0) return { text: `⚠ 退货窗口剩 ${left} 天`, color: 'var(--danger)' }
  return { text: `已过退货期 ${-left} 天 · 该定去留了`, color: 'var(--gold)' }
}

async function setStatus(i, status, extra = {}) {
  busy.value = i.id
  err.value = ''
  try {
    const { error } = await supabase.from('items').update({ status, ...extra }).eq('id', i.id)
    if (error) throw new Error(error.message)
    await supabase.rpc('sync_items_asset')
    await loadAll()
  } catch (e) { err.value = e.message } finally { busy.value = '' }
}
function keep(i) {
  const v = prompt(`「${i.name}」留下。它现在值多少?(默认按买价 ${i.price})`, String(i.price))
  if (v === null) return
  setStatus(i, 'kept', { value: Number(v) || Number(i.price) })
}
function markSold(i) {
  const v = prompt(`「${i.name}」卖了多少钱?`, String(i.value || i.price))
  if (v === null) return
  setStatus(i, 'sold', { sold_price: Number(v) || 0, sold_at: new Date().toISOString().slice(0, 10), value: 0 })
  alert('记得把回款截图丢收件箱,管家记「闲置变现」收入')
}
function reprice(i) {
  const v = prompt(`「${i.name}」当前估值?`, String(i.value))
  if (v === null) return
  setStatus(i, i.status, { value: Number(v) || 0 })
}

// 从流水导入:近45天购物类支出,未建档的
const showImport = ref(false)
const importable = computed(() => {
  const cutoff = new Date(Date.now() - 45 * 864e5).toISOString().slice(0, 10)
  const linked = new Set(store.items.map((i) => i.tx_id).filter(Boolean))
  return store.recentTx.filter((t) =>
    t.type === 'expense' && t.occurred_at >= cutoff && Number(t.amount) >= 100 &&
    ['购物', '其他', '娱乐'].includes(t.category) && !linked.has(t.id))
})
async function importTx(t) {
  busy.value = t.id
  try {
    const name = (t.note || '').replace(/^(微信|支付宝|抖音支付|美团|随手拍|拍单)\|/, '').split('|')[0].slice(0, 30) || t.category
    const { error } = await supabase.from('items').insert({
      owner: store.session.user.id, name, price: t.amount, value: t.amount,
      bought_at: t.occurred_at, tx_id: t.id, category: t.category,
      source: (t.note || '').includes('抖音') ? '抖音' : (t.note || '').includes('微信') ? '微信' : (t.note || '').includes('支付宝') ? '支付宝' : '',
    })
    if (error) throw new Error(error.message)
    await loadAll()
  } catch (e) { err.value = e.message } finally { busy.value = '' }
}

// 手动添加
const showAdd = ref(false)
const form = ref({ name: '', price: '', bought_at: new Date().toISOString().slice(0, 10) })
async function addItem() {
  if (!form.value.name || !Number(form.value.price)) return
  busy.value = 'add'
  try {
    const { error } = await supabase.from('items').insert({
      owner: store.session.user.id, name: form.value.name, price: Number(form.value.price),
      value: Number(form.value.price), bought_at: form.value.bought_at,
    })
    if (error) throw new Error(error.message)
    form.value = { name: '', price: '', bought_at: new Date().toISOString().slice(0, 10) }
    showAdd.value = false
    await loadAll()
  } catch (e) { err.value = e.message } finally { busy.value = '' }
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <div class="flex items-center gap-2 mb-1">
      <h1 class="text-xl font-bold flex-1"><button class="mr-1" @click="router.back()">‹</button> 📦 物品间</h1>
      <button class="text-xs px-3 py-1.5 rounded-full border" style="border-color: var(--hairline); color: var(--ink-2)" @click="showAdd = !showAdd">＋手动</button>
      <button class="text-xs px-3 py-1.5 rounded-full border" style="border-color: rgba(216,178,92,.5); color: var(--gold)" @click="showImport = !showImport">从流水导入</button>
    </div>
    <p class="text-xs mb-3" style="color: var(--ink-3)">买回来的东西要么被使用,要么被变现 · 在用+闲置估值 <b class="tabular" style="color: var(--gold)">{{ fmtCNY(assetTotal) }}</b> 已计入沉淀资产</p>

    <p v-if="err" class="text-sm mb-2" style="color: var(--danger)">{{ err }}</p>

    <!-- 手动添加 -->
    <div v-if="showAdd" class="card p-3.5 mb-3">
      <div class="flex gap-2">
        <input v-model="form.name" placeholder="买了什么" class="flex-1 min-w-0 card px-3 py-2 text-[14px] outline-none" />
        <input v-model="form.price" type="number" placeholder="价格" class="w-24 card px-3 py-2 text-[14px] outline-none" />
      </div>
      <div class="flex gap-2 mt-2 items-center">
        <input v-model="form.bought_at" type="date" class="card px-3 py-2 text-[13px] outline-none" />
        <button class="flex-1 py-2 rounded-xl text-[14px] font-medium disabled:opacity-40" style="background: var(--c-net)"
          :disabled="busy === 'add'" @click="addItem">{{ busy === 'add' ? '…' : '入间,开始7天试用期' }}</button>
      </div>
    </div>

    <!-- 从流水导入 -->
    <div v-if="showImport" class="card px-4 py-2 mb-3">
      <div class="text-xs py-1.5" style="color: var(--ink-3)">近45天 ≥100元 的购物类流水(点一下建档):</div>
      <div v-if="!importable.length" class="text-sm py-3 text-center" style="color: var(--ink-3)">没有待建档的购物流水</div>
      <div v-for="t in importable.slice(0, 15)" :key="t.id" class="flex items-center justify-between py-2 border-t" style="border-color: var(--grid)">
        <div class="min-w-0 flex-1">
          <div class="text-[13px] truncate">{{ (t.note || t.category).replace(/^(微信|支付宝|抖音支付|美团)\|/, '') }}</div>
          <div class="text-[11px]" style="color: var(--ink-3)">{{ fmtDate(t.occurred_at) }} · {{ fmtCNY(t.amount) }}</div>
        </div>
        <button class="text-xs px-2.5 py-1 rounded-full border shrink-0" style="border-color: rgba(216,178,92,.5); color: var(--gold)"
          :disabled="busy === t.id" @click="importTx(t)">{{ busy === t.id ? '…' : '＋收进来' }}</button>
      </div>
    </div>

    <!-- 状态页签 -->
    <div class="flex gap-1.5 mb-3 overflow-x-auto">
      <button v-for="[k, label] in TABS" :key="k" class="px-3 py-1.5 rounded-full text-[13px] border shrink-0"
        :style="tab === k ? 'background: var(--c-net); color:#fff; border-color:transparent' : 'border-color: var(--hairline); color: var(--ink-2)'"
        @click="tab = k">{{ label }}<span v-if="counts[k]" class="ml-1 text-[11px] opacity-70">{{ counts[k] }}</span></button>
    </div>

    <div v-if="!list.length" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      {{ tab === 'trial' ? '没有试用期的东西 · 新买的会从这里开始' : '这里空着' }}
    </div>

    <div v-for="i in list" :key="i.id" class="card p-3.5 mb-2.5">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0 flex-1">
          <div class="text-[15px] font-medium truncate">{{ i.name }}</div>
          <div class="text-[11px] mt-0.5" style="color: var(--ink-3)">
            {{ fmtDate(i.bought_at) }} 买入 {{ fmtCNY(i.price) }}<span v-if="i.source"> · {{ i.source }}</span>
            <span v-if="['kept','idle','selling'].includes(i.status)"> · 已持有 {{ daysSince(i.bought_at) }} 天 · 估值 {{ fmtCNY(i.value) }}</span>
            <span v-if="i.status === 'sold'"> · 卖出 {{ fmtCNY(i.sold_price) }}({{ Math.round((i.sold_price / i.price) * 100) }}%残值)</span>
            <span v-if="i.status === 'returned'"> · 已退货</span>
            <span v-if="i.status === 'consumed'"> · 耗材</span>
          </div>
          <div v-if="i.status === 'trial'" class="text-[12px] mt-1 font-medium" :style="{ color: trialBadge(i).color }">{{ trialBadge(i).text }}</div>
        </div>
      </div>
      <div class="flex gap-1.5 mt-2.5 flex-wrap" v-if="i.status !== 'sold' && i.status !== 'returned' && i.status !== 'consumed'">
        <template v-if="i.status === 'trial'">
          <button class="it-btn gold" :disabled="busy === i.id" @click="keep(i)">✓ 留下</button>
          <button class="it-btn" :disabled="busy === i.id" @click="setStatus(i, 'returned')">↩ 退货了</button>
          <button class="it-btn" :disabled="busy === i.id" @click="setStatus(i, 'consumed')">是耗材</button>
        </template>
        <template v-if="i.status === 'kept'">
          <button class="it-btn" :disabled="busy === i.id" @click="setStatus(i, 'idle')">吃灰了→闲置</button>
          <button class="it-btn" :disabled="busy === i.id" @click="reprice(i)">改估值</button>
        </template>
        <template v-if="i.status === 'idle'">
          <button class="it-btn gold" :disabled="busy === i.id" @click="setStatus(i, 'selling')">挂卖变现</button>
          <button class="it-btn" :disabled="busy === i.id" @click="setStatus(i, 'kept')">又用起来了</button>
        </template>
        <template v-if="i.status === 'selling'">
          <button class="it-btn gold" :disabled="busy === i.id" @click="markSold(i)">💰 卖出了</button>
          <button class="it-btn" :disabled="busy === i.id" @click="setStatus(i, 'idle')">先不卖了</button>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.it-btn {
  padding: 5px 12px; border-radius: 999px; font-size: 12px;
  border: 1px solid var(--hairline); color: var(--ink-2);
}
.it-btn.gold { border-color: rgba(216, 178, 92, 0.5); color: var(--gold); }
.it-btn:disabled { opacity: 0.4; }
</style>
