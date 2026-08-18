<script setup>
// 买前问一嘴:商品截图/文字 → 结合本人预算/目标/债务的五维购买建议
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { loadAll } from '../lib/store'
import { fmtCNY, todayStr } from '../lib/fmt'

const router = useRouter()
const text = ref('')
const busy = ref(false)
const err = ref('')
const result = ref(null)
const imgPreview = ref('')
const savedOk = ref(false)

function resizeToDataUrl(file, maxW = 1000) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => {
      const scale = Math.min(1, maxW / img.width)
      const c = document.createElement('canvas')
      c.width = Math.round(img.width * scale)
      c.height = Math.round(img.height * scale)
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height)
      resolve(c.toDataURL('image/jpeg', 0.82))
    }
    img.onerror = reject
    img.src = URL.createObjectURL(file)
  })
}

async function ask(imageB64) {
  busy.value = true; err.value = ''; result.value = null; savedOk.value = false
  try {
    const { data, error } = await supabase.functions.invoke('buy-advisor', {
      body: { image_b64: imageB64 || null, text: text.value.trim() || null },
    })
    if (error) throw error
    if (data?.error) throw new Error(data.error)
    result.value = data.result
  } catch (e) { err.value = '分析失败:' + (e.message || e) } finally { busy.value = false }
}

async function onPick(e) {
  const f = (e.target.files || [])[0]
  if (!f) return
  try {
    const b64 = await resizeToDataUrl(f)
    imgPreview.value = b64
    await ask(b64)
  } catch (ex) { err.value = String(ex) } finally { e.target.value = '' }
}

const VERDICT = {
  buy: { label: '买!', color: '#d8b25c', tip: '预算内的痛快,该花花' },
  wait: { label: '缓一缓', color: '#eda100', tip: '放购物车睡一觉,明天还想要再说' },
  skip: { label: '别买', color: '#e0564d', tip: '这钱有更好的去处' },
}

async function obeyAndSave() {
  if (!result.value?.price) return
  busy.value = true
  try {
    const { error } = await supabase.from('savings').insert({
      amount: Number(result.value.price), way: '忍住没买',
      note: '听劝没买:' + (result.value.product || ''), saved_at: todayStr(),
    })
    if (error) throw error
    savedOk.value = true
    await loadAll()
  } catch (e) { err.value = e.message } finally { busy.value = false }
}

function reset() { result.value = null; imgPreview.value = ''; text.value = ''; err.value = ''; savedOk.value = false }
</script>

<template>
  <div class="max-w-md mx-auto px-4 pt-5">
    <h1 class="text-xl font-bold mb-2"><button class="mr-1" @click="router.back()">‹</button> 🤔 这个能买吗</h1>
    <p class="text-[12px] mb-4" style="color: var(--ink-3)">
      截个商品图或打一句话,我结合你本月预算、省钱目标、债务情况,给你个懂行的判断。
    </p>
    <p v-if="err" class="text-sm mb-3" style="color: var(--danger)">{{ err }}</p>

    <template v-if="!result">
      <label class="scan-btn block p-4 mb-3 cursor-pointer">
        <div class="hero-sheen"></div>
        <input type="file" accept="image/*" class="hidden" @change="onPick" :disabled="busy" />
        <div class="flex items-center gap-3">
          <span class="text-2xl">🛍</span>
          <div>
            <div class="font-bold text-[16px]">{{ busy ? '正在帮你掂量…' : '传商品截图问一嘴' }}</div>
            <div class="text-[12px]" style="opacity:.75">淘宝/抖音/京东的商品页截图都行</div>
          </div>
        </div>
      </label>
      <div class="flex gap-2">
        <input v-model="text" placeholder="或打字:华为手表GT5 1500块" class="flex-1 card px-3.5 py-2.5 outline-none text-[14px]"
          @keyup.enter="ask(null)" />
        <button :disabled="busy || !text.trim()" class="px-4 rounded-xl text-sm disabled:opacity-40"
          style="background: var(--c-net)" @click="ask(null)">问</button>
      </div>
    </template>

    <template v-else>
      <div class="card p-5 mb-4" :style="`border-color: ${VERDICT[result.verdict]?.color || 'var(--hairline)'}55`">
        <div class="flex items-center gap-3 mb-1">
          <img v-if="imgPreview" :src="imgPreview" class="w-12 h-12 rounded-lg object-cover" />
          <div class="min-w-0">
            <div class="text-[14px] truncate" style="color: var(--ink-2)">{{ result.product }}
              <span class="tabular font-semibold" style="color: var(--ink-1)">{{ fmtCNY(Number(result.price) || 0) }}</span></div>
          </div>
          <span class="ml-auto shrink-0 px-3 py-1.5 rounded-full font-bold text-[15px]"
            :style="`background: ${VERDICT[result.verdict]?.color}; color: #171106`">
            {{ VERDICT[result.verdict]?.label || result.verdict }}</span>
        </div>
        <div class="text-[15px] font-medium mt-2">{{ result.title }}</div>

        <div class="mt-3 space-y-2">
          <div v-for="d in result.dimensions" :key="d.name" class="flex gap-2 text-[13px]">
            <span :style="d.pass ? 'color: var(--good-text)' : 'color: var(--danger)'">{{ d.pass ? '✓' : '✗' }}</span>
            <span style="color: var(--ink-2)"><b>{{ d.name }}</b> · {{ d.comment }}</span>
          </div>
        </div>

        <div v-if="result.math?.length" class="mt-3 p-3 rounded-xl text-[12px] space-y-1" style="background: var(--plane); color: var(--ink-2)">
          <div v-for="(m, i) in result.math" :key="i">💡 {{ m }}</div>
        </div>

        <div class="mt-3 text-[13px]" style="color: var(--ink-2)">{{ result.advice }}</div>
      </div>

      <button v-if="result.verdict !== 'buy' && !savedOk" :disabled="busy"
        class="w-full py-3 rounded-xl font-semibold mb-2 disabled:opacity-50"
        style="background: var(--c-save)" @click="obeyAndSave">
        👍 听劝不买了,记一笔省下 {{ fmtCNY(Number(result.price) || 0) }}</button>
      <div v-if="savedOk" class="text-center text-sm mb-2" style="color: var(--c-save)">已记进省钱账 ✓ 这就是赢</div>
      <button class="w-full py-2.5 text-sm" style="color: var(--ink-3)" @click="reset">再问一个 ›</button>
    </template>
  </div>
</template>
