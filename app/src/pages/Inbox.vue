<script setup>
// 随手拍收件箱:小票/截图/语音先丢进来,回家喊 Claude「处理收件箱」自动入账
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = useRouter()
const items = ref([])
const previews = ref({})   // id -> signed url
const busy = ref(false)
const err = ref('')
const quickNote = ref('')
const doneCount = ref(0)

async function load() {
  const { data, error } = await supabase.from('inbox_items').select('*')
    .eq('status', 'pending').order('created_at', { ascending: false })
  if (error) { err.value = error.message; return }
  items.value = data || []
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

async function onPick(e) {
  const files = [...(e.target.files || [])]
  if (!files.length) return
  busy.value = true; err.value = ''
  try {
    for (const f of files) {
      const kind = f.type.startsWith('audio') ? 'audio' : 'image'
      const ext = (f.name.split('.').pop() || 'bin').toLowerCase()
      const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
      const { error: e1 } = await supabase.storage.from('inbox').upload(path, f)
      if (e1) throw e1
      const { error: e2 } = await supabase.from('inbox_items').insert({ kind, path, note: '' })
      if (e2) throw e2
    }
    await load()
  } catch (ex) { err.value = ex.message } finally { busy.value = false; e.target.value = '' }
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
      在外面消费了?拍小票、截支付页、发语音丢进来就行。回家跟 Claude 说一句「处理收件箱」,他识别后帮你记好账,这里的条目会自动清掉。
    </p>
    <p v-if="err" class="text-sm mb-3" style="color: var(--danger)">{{ err }}</p>

    <!-- 上传 -->
    <label class="card block p-6 mb-3 text-center cursor-pointer" style="border-style: dashed; border-width: 2px">
      <input type="file" accept="image/*,audio/*" multiple class="hidden" @change="onPick" :disabled="busy" />
      <div class="text-3xl mb-1">📸</div>
      <div class="text-sm" style="color: var(--ink-2)">{{ busy ? '正在上传…' : '拍照 / 选图 / 传语音' }}</div>
    </label>

    <!-- 文字速记 -->
    <div class="flex gap-2 mb-5">
      <input v-model="quickNote" placeholder="或者打一句:加油200 兴业卡" class="flex-1 card px-3.5 py-2.5 outline-none text-[14px]"
        @keyup.enter="addText" />
      <button :disabled="busy || !quickNote.trim()" class="px-4 rounded-xl text-white text-sm disabled:opacity-40"
        style="background: var(--c-net)" @click="addText">存</button>
    </div>

    <!-- 待处理 -->
    <div v-if="!items.length" class="card p-8 text-center text-sm" style="color: var(--ink-3)">
      收件箱空空,好账清清
    </div>
    <div v-for="it in items" :key="it.id" class="card p-3 mb-3">
      <div class="flex gap-3">
        <img v-if="it.kind === 'image' && previews[it.id]" :src="previews[it.id]"
          class="w-16 h-16 rounded-lg object-cover shrink-0" />
        <div v-else-if="it.kind === 'audio'" class="w-16 h-16 rounded-lg flex items-center justify-center text-2xl shrink-0" style="background: var(--plane)">🎙</div>
        <div v-else class="w-16 h-16 rounded-lg flex items-center justify-center text-2xl shrink-0" style="background: var(--plane)">✏️</div>
        <div class="flex-1 min-w-0">
          <div class="text-[11px] mb-1" style="color: var(--ink-3)">{{ new Date(it.created_at).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }) }} · 待处理</div>
          <input v-model="it.note" placeholder="补一句(哪张卡/干嘛的),可不填" @blur="saveNote(it)"
            class="w-full bg-transparent outline-none text-[13px] border-b pb-1" style="border-color: var(--hairline)" />
        </div>
        <button class="text-xs self-start" style="color: var(--ink-3)" @click="del(it)">✕</button>
      </div>
    </div>
  </div>
</template>
