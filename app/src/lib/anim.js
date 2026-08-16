import { ref, onMounted } from 'vue'

// 数字滚动:从0缓动到目标值,返回响应式当前值
export function useCountUp(target, duration = 900) {
  const val = ref(0)
  onMounted(() => {
    const t0 = performance.now()
    const to = Number(target.value ?? target) || 0
    function tick(now) {
      const p = Math.min((now - t0) / duration, 1)
      const ease = 1 - Math.pow(1 - p, 3)
      val.value = to * ease
      if (p < 1) requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  })
  return val
}
