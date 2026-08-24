<script setup>
import { onMounted, computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from './lib/supabase'
import { store, loadAll, bootSettle } from './lib/store'
import Login from './pages/Login.vue'
import Icon from './components/Icon.vue'

const route = useRoute()
const router = useRouter()

onMounted(async () => {
  const { data } = await supabase.auth.getSession()
  store.session = data.session
  supabase.auth.onAuthStateChange((_e, session) => {
    store.session = session
    if (session && !store.ready) init()
  })
  if (store.session) init()
})

async function init() {
  try { await supabase.rpc('ensure_household') } catch (e) { console.warn('ensure_household:', e.message) }
  await loadAll()
  supabase.from('inbox_items').select('*', { count: 'exact', head: true }).eq('status', 'pending')
    .then(({ count }) => { store.inboxPending = count || 0 })
  await bootSettle()
}

const tabs = [
  { path: '/', label: '总览', icon: 'grid' },
  { path: '/tx', label: '流水', icon: 'list' },
  { path: '/record', label: '记账', icon: 'plus', big: true },
  { path: '/inbox', label: '收件箱', icon: 'camera' },
  { path: '/me', label: '我的', icon: 'sliders' },
]
const showTabs = computed(() => tabs.some((t) => t.path === route.path))
const spinning = ref(false)
const fabOpen = ref(false)
const scanInput = ref(null)
const quickInput = ref(null)
const toast = ref('')
let toastTimer = null
function showToast(msg) {
  toast.value = msg
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.value = '' }, 2600)
}
const FAB = [
  { icon: 'camera', label: '随手拍 · 丢给管家', action: 'quick' },
  { icon: 'spark', label: '拍小票 · 当场记', action: 'scan' },
  { icon: 'plus', label: '手动记一笔', to: '/record' },
]
function onTab(t) {
  if (t.big) { fabOpen.value = !fabOpen.value; return }
  fabOpen.value = false
  router.push(t.path)
}
function goFab(f) {
  fabOpen.value = false
  if (f.action === 'scan') { scanInput.value?.click(); return }
  if (f.action === 'quick') { quickInput.value?.click(); return }
  router.push(f.to)
}
function onScanFile(e) {
  const file = (e.target.files || [])[0]
  e.target.value = ''
  if (!file) return
  store.pendingScanFile = file
  router.push('/record?focus=scan')
}
// 随手拍:任意页面一键上传到收件箱,交给管家,不跳页
async function onQuickFiles(e) {
  const files = [...(e.target.files || [])]
  e.target.value = ''
  if (!files.length) return
  showToast(`上传中… 共 ${files.length} 张`)
  let ok = 0
  const ids = []
  for (const f of files) {
    try {
      const kind = f.type.startsWith('audio') ? 'audio' : 'image'
      const ext = (f.name.split('.').pop() || 'jpg').toLowerCase()
      const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
      const { error: e1 } = await supabase.storage.from('inbox').upload(path, f)
      if (e1) throw e1
      const { data: row, error: e2 } = await supabase.from('inbox_items').insert({ kind, path, note: '' }).select().single()
      if (e2) throw e2
      ok++
      if (kind === 'image') ids.push(row.id)
    } catch { /* 单张失败不阻塞其余 */ }
  }
  store.inboxPending += ok
  showToast(ok === files.length ? `已丢给管家 ${ok} 张,晚上取件 ✓` : `传上 ${ok}/${files.length} 张,失败的重试一下`)
  for (const id of ids) supabase.functions.invoke('ocr-inbox', { body: { id } }).catch(() => {})
}
function hardRefresh() {
  spinning.value = true
  setTimeout(() => window.location.reload(), 350)
}
</script>

<template>
  <template v-if="!store.session">
    <router-view v-if="route.path === '/register'" />
    <Login v-else />
  </template>
  <template v-else>
    <div v-if="!store.ready" class="min-h-screen flex items-center justify-center">
      <div class="text-center">
        <div class="text-3xl mb-3 animate-pulse">📒</div>
        <div class="text-sm" style="color: var(--ink-3)">正在打开账本…</div>
        <div v-if="store.error" class="mt-4 text-sm px-6" style="color: var(--danger)">
          {{ store.error }}
          <button class="block mx-auto mt-3 underline" @click="loadAll()">重试</button>
        </div>
      </div>
    </div>
    <template v-else>
      <router-view v-slot="{ Component }">
        <transition name="page">
          <component :is="Component" class="pb-safe" />
        </transition>
      </router-view>
      <!-- 记账三连 -->
      <div v-if="fabOpen" class="fixed inset-0 z-40 fab-backdrop" @click="fabOpen = false"></div>
      <div v-if="fabOpen" class="fixed inset-x-0 z-50 flex flex-col items-center gap-4"
        style="bottom: calc(env(safe-area-inset-bottom, 0px) + 6.5rem)">
        <button v-for="(f, i) in FAB" :key="f.label" class="fab-item flex items-center gap-4 px-7 py-4 rounded-2xl w-[82%] max-w-xs"
          :style="`animation-delay: ${(FAB.length - 1 - i) * 60}ms; background: var(--surface-1); border: 1.5px solid rgba(216,178,92,.5); box-shadow: 0 8px 28px rgba(0,0,0,.5)`"
          @click="goFab(f)">
          <span class="w-13 h-13 rounded-full flex items-center justify-center shrink-0" style="background: var(--c-net)">
            <Icon :name="f.icon" :size="26" /></span>
          <span class="text-[19px] font-semibold" style="color: var(--ink-1)">{{ f.label }}</span>
        </button>
      </div>

      <input ref="scanInput" type="file" accept="image/*" class="hidden" @change="onScanFile" />
      <input ref="quickInput" type="file" accept="image/*,audio/*" multiple class="hidden" @change="onQuickFiles" />

      <!-- 轻提示 -->
      <div v-if="toast" class="fixed inset-x-0 z-50 flex justify-center pointer-events-none"
        style="bottom: calc(env(safe-area-inset-bottom, 0px) + 8.5rem)">
        <div class="px-4 py-2 rounded-full text-[13px]"
          style="background: rgba(22,21,26,.94); border: 1px solid rgba(216,178,92,.5); color: var(--gold-bright, #f2dda2); backdrop-filter: blur(8px)">
          {{ toast }}</div>
      </div>

      <button class="fixed right-4 z-50 w-9 h-9 rounded-full flex items-center justify-center"
        style="bottom: calc(env(safe-area-inset-bottom, 0px) + 5.5rem); background: rgba(22,21,26,.85); border: 1px solid var(--hairline); color: var(--gold); backdrop-filter: blur(8px)"
        aria-label="刷新" @click="hardRefresh">
        <Icon name="refresh" :size="17" :class="{ 'spin-once': spinning }" />
      </button>
      <nav v-if="showTabs" class="fixed bottom-0 inset-x-0 z-50 tabbar-safe border-t"
        style="background: var(--surface-1); border-color: var(--hairline)">
        <div class="flex items-stretch max-w-md mx-auto">
          <button v-for="t in tabs" :key="t.path" class="flex-1 py-2 flex flex-col items-center gap-0.5"
            :class="{ 'tab-on': route.path === t.path }" @click="onTab(t)">
            <span class="tab-ic relative" :class="[t.big ? '-mt-3 rounded-full w-11 h-11 flex items-center justify-center shadow fab-plus' : 'py-0.5', t.big && fabOpen ? 'open' : '']"
              :style="t.big ? 'background: var(--c-net)' : (route.path === t.path ? 'color: var(--c-net)' : 'color: var(--ink-3)')">
              <Icon :name="t.icon" :size="t.big ? 22 : 20" />
              <i v-if="t.path === '/inbox' && store.inboxPending" class="absolute -top-1 -right-2 min-w-[15px] h-[15px] px-0.5 rounded-full text-[9px] font-bold flex items-center justify-center not-italic"
                style="background: var(--danger); color: #fff">{{ store.inboxPending > 9 ? '9+' : store.inboxPending }}</i></span>
            <span class="text-[11px]" :style="{ color: route.path === t.path ? 'var(--c-net)' : 'var(--ink-3)', fontWeight: route.path === t.path ? 600 : 400 }">
              {{ t.label }}</span>
          </button>
        </div>
      </nav>
    </template>
  </template>
</template>
