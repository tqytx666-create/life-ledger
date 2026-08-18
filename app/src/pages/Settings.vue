<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { store, loadAll } from '../lib/store'
import { CURRENCIES } from '../lib/fmt'

const router = useRouter()
const err = ref('')
const busy = ref(false)
const fxEdit = ref({ ...store.fx })
const newPass = ref('')
const passMsg = ref('')

// 家庭
import { onMounted } from 'vue'
import { fmtCNY } from '../lib/fmt'
const hh = ref(null)
const inviteCode = ref('')
onMounted(async () => {
  try {
    const { data } = await supabase.rpc('household_overview')
    hh.value = data
  } catch { /* 忽略 */ }
})
async function makeInvite() {
  err.value = ''
  try {
    const { data, error } = await supabase.rpc('create_invite')
    if (error) throw error
    inviteCode.value = data
    try { await navigator.clipboard.writeText(data) } catch { /* 手动复制 */ }
  } catch (e) { err.value = e.message }
}

async function changePass() {
  passMsg.value = ''
  if ((newPass.value || '').length < 6) { passMsg.value = '至少 6 位'; return }
  busy.value = true
  try {
    const { error } = await supabase.auth.updateUser({ password: newPass.value })
    if (error) throw error
    passMsg.value = '改好了 ✓ 下次登录用新密码'
    newPass.value = ''
  } catch (e) {
    passMsg.value = e.message.includes('different from the old') ? '新密码不能和旧的一样' : e.message
  } finally {
    busy.value = false
  }
}

async function saveFx() {
  err.value = ''; busy.value = true
  try {
    for (const c of CURRENCIES) {
      if (c === 'CNY') continue
      const v = Number(fxEdit.value[c])
      if (!v || v <= 0) throw new Error(c + ' 汇率要大于 0')
      const { error } = await supabase.from('fx_rates').update({ to_cny: v, updated_at: new Date().toISOString() }).eq('currency', c)
      if (error) throw error
    }
    try { await supabase.rpc('snapshot_net_worth') } catch { /* 忽略 */ }
    await loadAll()
    fxEdit.value = { ...store.fx }
  } catch (e) { err.value = e.message } finally { busy.value = false }
}

async function exportExcel() {
  err.value = ''; busy.value = true
  try {
    const XLSX = await import('xlsx')
    // 全量拉取(不用 store 里截断的近半年)
    const tables = [
      ['accounts', '账户'], ['transactions', '流水'], ['members', '家庭成员'],
      ['batches', '给钱批次'], ['batch_expenses', '批次花销'], ['loans', '贷款'],
      ['recurring', '固定支出'], ['fx_rates', '汇率'], ['net_worth_snapshots', '净资产快照'],
    ]
    const wb = XLSX.utils.book_new()
    for (const [t, label] of tables) {
      const { data, error } = await supabase.from(t).select('*').limit(100000)
      if (error) throw new Error(t + ': ' + error.message)
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(data || []), label)
    }
    const d = new Date(), p = (x) => String(x).padStart(2, '0')
    XLSX.writeFile(wb, `人生账本备份-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}.xlsx`)
  } catch (e) { err.value = e.message } finally { busy.value = false }
}

async function logout() {
  if (!confirm('退出账本?')) return
  await supabase.auth.signOut()
  store.ready = false
}
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-6">
    <h1 class="text-xl font-bold mb-4">我的</h1>
    <p v-if="err" class="text-sm mb-3" style="color: var(--danger)">{{ err }}</p>

    <div class="card mb-4 divide-y" style="--tw-divide-opacity:1">
      <button class="w-full flex items-center justify-between p-4" @click="router.push('/accounts')">
        <span>💼 账户管理</span><span style="color: var(--ink-3)">›</span>
      </button>
      <button class="w-full flex items-center justify-between p-4 border-t" style="border-color: var(--hairline)" @click="router.push('/loans')">
        <span>🏠 按揭贷款</span><span style="color: var(--ink-3)">›</span>
      </button>
      <button class="w-full flex items-center justify-between p-4 border-t" style="border-color: var(--hairline)" @click="router.push('/recurring')">
        <span>🔁 固定支出</span><span style="color: var(--ink-3)">›</span>
      </button>
      <button class="w-full flex items-center justify-between p-4 border-t" style="border-color: var(--hairline)" @click="router.push('/inbox')">
        <span>📥 随手拍收件箱</span><span style="color: var(--ink-3)">›</span>
      </button>
      <button class="w-full flex items-center justify-between p-4 border-t" style="border-color: var(--hairline)" @click="router.push('/import')">
        <span>📑 账单导入(微信/支付宝/美团)</span><span style="color: var(--ink-3)">›</span>
      </button>
    </div>

    <!-- 我的家庭 -->
    <div v-if="hh && hh.role" class="card p-4 mb-4">
      <div class="flex items-center justify-between mb-1">
        <div class="text-sm font-medium" style="color: var(--ink-2)">🏠 {{ hh.household }}</div>
        <span class="text-xs px-2 py-0.5 rounded-full" :style="hh.role === 'head' ? 'background: var(--c-net); color:#171106' : 'background: var(--plane); color: var(--ink-3)'">
          {{ hh.role === 'head' ? '家主' : '成员' }}</span>
      </div>
      <template v-if="hh.role === 'head'">
        <div v-for="m in hh.members" :key="m.display_name" class="py-2 border-b last:border-0" style="border-color: var(--hairline)">
          <div class="flex justify-between text-sm">
            <span>{{ m.display_name }}<span v-if="m.role==='head'" class="text-xs ml-1" style="color: var(--ink-3)">(家主)</span></span>
            <span class="tabular" :style="m.liquid < 0 ? 'color: var(--danger)' : ''">净 {{ fmtCNY(m.liquid, true) }}</span>
          </div>
          <div class="text-[11px] tabular" style="color: var(--ink-3)">本月 收{{ fmtCNY(m.month_income, true) }} / 支{{ fmtCNY(m.month_expense, true) }}</div>
        </div>
        <div class="mt-3">
          <button class="px-4 py-2 rounded-lg text-sm border" style="border-color: var(--c-net); color: var(--c-net)" @click="makeInvite">+ 生成邀请码拉家人</button>
          <div v-if="inviteCode" class="mt-2 text-sm" style="color: var(--ink-2)">
            邀请码:<span class="tabular font-bold text-[17px] ml-1" style="color: var(--gold)">{{ inviteCode }}</span>
            <span class="text-xs ml-2" style="color: var(--ink-3)">已复制,7天有效;对方注册时填入即可加入</span>
          </div>
        </div>
      </template>
      <p v-else class="text-xs" style="color: var(--ink-3)">你的账只有你和家主能看到</p>
    </div>

    <div class="card p-4 mb-4">
      <div class="text-sm font-medium mb-3" style="color: var(--ink-2)">汇率(折人民币)</div>
      <div class="space-y-2">
        <div v-for="c in CURRENCIES.filter((x) => x !== 'CNY')" :key="c" class="flex items-center gap-3">
          <span class="w-12 text-sm">1 {{ c }}</span>
          <span class="text-sm" style="color: var(--ink-3)">=</span>
          <input v-model="fxEdit[c]" type="number" inputmode="decimal" step="0.0001"
            class="flex-1 card px-3 py-2 outline-none tabular text-sm" />
          <span class="text-sm" style="color: var(--ink-3)">元</span>
        </div>
      </div>
      <button :disabled="busy" class="mt-3 px-4 py-2 rounded-lg text-white text-sm disabled:opacity-50" style="background: var(--c-net)" @click="saveFx">保存汇率</button>
    </div>

    <div class="card p-4 mb-4">
      <div class="text-sm font-medium mb-1" style="color: var(--ink-2)">数据备份</div>
      <p class="text-xs mb-3" style="color: var(--ink-3)">导出全部数据为 Excel,自己留底</p>
      <button :disabled="busy" class="px-4 py-2 rounded-lg text-sm border disabled:opacity-50" style="border-color: var(--c-net); color: var(--c-net)" @click="exportExcel">
        {{ busy ? '正在导出…' : '📥 导出 Excel' }}</button>
    </div>

    <div class="card p-4 mb-4">
      <div class="text-sm font-medium mb-1" style="color: var(--ink-2)">修改密码</div>
      <p class="text-xs mb-3" style="color: var(--ink-3)">改成只有你自己知道的,至少 6 位</p>
      <div class="flex gap-2">
        <input v-model="newPass" type="password" placeholder="新密码" autocomplete="new-password"
          class="flex-1 card px-3 py-2 outline-none text-sm" />
        <button :disabled="busy" class="px-4 rounded-lg text-white text-sm disabled:opacity-50"
          style="background: var(--c-net)" @click="changePass">改密码</button>
      </div>
      <p v-if="passMsg" class="text-xs mt-2" :style="{ color: passMsg.includes('✓') ? 'var(--good-text)' : 'var(--danger)' }">{{ passMsg }}</p>
    </div>

    <button class="w-full py-3 rounded-xl text-sm border" style="border-color: var(--hairline); color: var(--danger)" @click="logout">退出账本</button>
    <p class="text-center text-xs mt-6 mb-2" style="color: var(--ink-3)">人生账本 v1.0</p>
  </div>
</template>
