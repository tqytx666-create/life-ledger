<script setup>
import { onMounted, computed } from 'vue'
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
</script>

<template>
  <Login v-if="!store.session" />
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
