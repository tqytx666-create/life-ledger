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
  await bootSettle()
}

const tabs = [
  { path: '/', label: '总览', icon: 'grid' },
  { path: '/tx', label: '流水', icon: 'list' },
  { path: '/record', label: '记账', icon: 'plus', big: true },
  { path: '/family', label: '家人', icon: 'users' },
  { path: '/me', label: '我的', icon: 'sliders' },
]
const showTabs = computed(() => tabs.some((t) => t.path === route.path))
const spinning = ref(false)
const fabOpen = ref(false)
const FAB = [
  { icon: 'camera', label: '拍小票 · 自动识别', to: '/record?focus=scan' },
  { icon: 'spark', label: '问一嘴 · 这个能买吗', to: '/askbuy' },
  { icon: 'plus', label: '手动记一笔', to: '/record' },
]
function onTab(t) {
  if (t.big) { fabOpen.value = !fabOpen.value; return }
  fabOpen.value = false
  router.push(t.path)
}
function goFab(to) { fabOpen.value = false; router.push(to) }
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
        <button v-for="(f, i) in FAB" :key="f.to" class="fab-item flex items-center gap-4 px-7 py-4 rounded-2xl w-[82%] max-w-xs"
          :style="`animation-delay: ${(FAB.length - 1 - i) * 60}ms; background: var(--surface-1); border: 1.5px solid rgba(216,178,92,.5); box-shadow: 0 8px 28px rgba(0,0,0,.5)`"
          @click="goFab(f.to)">
          <span class="w-13 h-13 rounded-full flex items-center justify-center shrink-0" style="background: var(--c-net)">
            <Icon :name="f.icon" :size="26" /></span>
          <span class="text-[19px] font-semibold" style="color: var(--ink-1)">{{ f.label }}</span>
        </button>
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
            <span class="tab-ic" :class="[t.big ? '-mt-3 rounded-full w-11 h-11 flex items-center justify-center shadow fab-plus' : 'py-0.5', t.big && fabOpen ? 'open' : '']"
              :style="t.big ? 'background: var(--c-net)' : (route.path === t.path ? 'color: var(--c-net)' : 'color: var(--ink-3)')">
              <Icon :name="t.icon" :size="t.big ? 22 : 20" /></span>
            <span class="text-[11px]" :style="{ color: route.path === t.path ? 'var(--c-net)' : 'var(--ink-3)', fontWeight: route.path === t.path ? 600 : 400 }">
              {{ t.label }}</span>
          </button>
        </div>
      </nav>
    </template>
  </template>
</template>
