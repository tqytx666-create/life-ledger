<script setup>
import { ref } from 'vue'
import { supabase } from '../lib/supabase'

const email = ref(localStorage.getItem('ll_email') || '')
const password = ref('')
const busy = ref(false)
const err = ref('')

async function login() {
  if (!email.value || !password.value) return
  busy.value = true
  err.value = ''
  const { error } = await supabase.auth.signInWithPassword({
    email: email.value.trim(),
    password: password.value,
  })
  busy.value = false
  if (error) {
    err.value = error.message.includes('Invalid') ? '邮箱或密码不对' : error.message
  } else {
    localStorage.setItem('ll_email', email.value.trim())
  }
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center px-8">
    <div class="w-full max-w-sm">
      <div class="text-center mb-8">
        <div class="text-5xl mb-3">📒</div>
        <h1 class="text-2xl font-bold">人生账本</h1>
        <p class="text-sm mt-1" style="color: var(--ink-3)">一个账本,管住全部家底</p>
      </div>
      <form @submit.prevent="login" class="space-y-3">
        <input v-model="email" type="email" placeholder="邮箱" autocomplete="username"
          class="w-full px-4 py-3 rounded-xl card outline-none" />
        <input v-model="password" type="password" placeholder="访问密码" autocomplete="current-password"
          class="w-full px-4 py-3 rounded-xl card outline-none" />
        <button type="submit" :disabled="busy"
          class="w-full py-3 rounded-xl font-semibold text-white disabled:opacity-50"
          style="background: var(--c-net)">
          {{ busy ? '正在进入…' : '进入账本' }}
        </button>
        <p v-if="err" class="text-sm text-center" style="color: var(--c-out)">{{ err }}</p>
      </form>
    </div>
  </div>
</template>
