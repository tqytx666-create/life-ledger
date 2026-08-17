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
      <button class="fixed right-4 z-50 w-9 h-9 rounded-full flex items-center justify-center"
        style="bottom: calc(env(safe-area-inset-bottom, 0px) + 5.5rem); background: rgba(22,21,26,.85); border: 1px solid var(--hairline); color: var(--gold); backdrop-filter: blur(8px)"
        aria-label="刷新" @click="hardRefresh">
        <Icon name="refresh" :size="17" :class="{ 'spin-once': spinning }" />
      </button>
      <nav v-if="showTabs" class="fixed bottom-0 inset-x-0 z-50 tabbar-safe border-t"
        style="background: var(--surface-1); border-color: var(--hairline)">
        <div class="flex items-stretch max-w-md mx-auto">
          <button v-for="t in tabs" :key="t.path" class="flex-1 py-2 flex flex-col items-center gap-0.5"
            :class="{ 'tab-on': route.path === t.path }" @click="router.push(t.path)">
            <span class="tab-ic" :class="t.big ? '-mt-3 rounded-full w-11 h-11 flex items-center justify-center shadow' : 'py-0.5'"
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
