<script setup>
// 注册:自立门户当家主,或凭邀请码加入已有家庭
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = useRouter()
const phone = ref('')
const password = ref('')
const display = ref('')
const invite = ref('')
const busy = ref(false)
const err = ref('')
const inviteRetry = ref(false)

async function doRegister() {
  err.value = ''
  const p = phone.value.trim()
  if (!/^1\d{10}$/.test(p)) { err.value = '手机号看起来不对(11位)'; return }
  if ((password.value || '').length < 6) { err.value = '密码至少 6 位'; return }
  if (!display.value.trim()) { err.value = '给自己起个称呼'; return }
  busy.value = true
  try {
    const { data, error } = await supabase.auth.signUp({
      email: p + '@ll.local', password: password.value,
    })
    if (error) throw new Error(error.message.includes('already registered') ? '这个手机号已经注册过了,直接登录' : error.message)
    if (!data.session) throw new Error('注册成功但未登录,请回登录页登录')
    await joinHousehold()
  } catch (e) {
    err.value = e.message
    busy.value = false
  }
}

async function joinHousehold() {
  err.value = ''
  busy.value = true
  try {
    const { error } = await supabase.rpc('ensure_household', {
      p_display: display.value.trim(), p_invite: invite.value.trim() || null,
    })
    if (error) throw new Error(error.message)
    localStorage.setItem('ll_phone', phone.value.trim())
    router.replace('/')
  } catch (e) {
    // 邀请码错误:已注册成功,给重试/自立门户的机会
    err.value = e.message
    inviteRetry.value = true
  } finally {
    busy.value = false
  }
}

async function goSolo() {
  invite.value = ''
  await joinHousehold()
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center px-8">
    <div class="w-full max-w-sm">
      <div class="text-center mb-8">
        <div class="text-5xl mb-3">📒</div>
        <h1 class="text-2xl font-bold">开一本自己的账</h1>
        <p class="text-sm mt-1" style="color: var(--ink-3)">一个家庭一本账,数据只属于你</p>
      </div>

      <template v-if="!inviteRetry">
        <form @submit.prevent="doRegister" class="space-y-3">
          <input v-model="phone" type="tel" placeholder="手机号(登录用)" class="w-full px-4 py-3 rounded-xl card outline-none" />
          <input v-model="password" type="password" placeholder="设个密码(至少6位)" autocomplete="new-password" class="w-full px-4 py-3 rounded-xl card outline-none" />
          <input v-model="display" placeholder="你的称呼(如:老王)" class="w-full px-4 py-3 rounded-xl card outline-none" />
          <input v-model="invite" placeholder="邀请码(有则填,加入家人的账本)" class="w-full px-4 py-3 rounded-xl card outline-none" />
          <button type="submit" :disabled="busy" class="w-full py-3 rounded-xl font-semibold disabled:opacity-50" style="background: var(--c-net)">
            {{ busy ? '正在开户…' : invite.trim() ? '加入家庭' : '创建我的账本' }}
          </button>
        </form>
      </template>
      <template v-else>
        <div class="card p-4 mb-3 text-sm" style="color: var(--ink-2)">
          账号注册好了,但邀请码没对上。可以改邀请码重试,或者先自立门户(以后也能让家主拉你)。
        </div>
        <input v-model="invite" placeholder="重新输入邀请码" class="w-full px-4 py-3 rounded-xl card outline-none mb-3" />
        <div class="flex gap-2">
          <button :disabled="busy" class="flex-1 py-3 rounded-xl font-semibold disabled:opacity-50" style="background: var(--c-net)" @click="joinHousehold">重试加入</button>
          <button :disabled="busy" class="flex-1 py-3 rounded-xl font-semibold border" style="border-color: var(--hairline); color: var(--ink-2)" @click="goSolo">自立门户</button>
        </div>
      </template>

      <p v-if="err" class="text-sm text-center mt-3" style="color: var(--danger)">{{ err }}</p>
      <button class="block mx-auto mt-6 text-sm" style="color: var(--ink-3)" @click="router.push('/')">已有账号?去登录 ›</button>
    </div>
  </div>
</template>
