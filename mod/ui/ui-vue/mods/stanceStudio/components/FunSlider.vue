<template>
  <div class="fun-slider" :class="{ changed }">
    <div class="fun-head">
      <span class="fun-label" :title="title || label">{{ label }}</span>
      <span class="fun-ctrl">
        <button v-if="mode !== 'scale'" class="fun-inf" :class="{ on: isInf(shown) }" title="Infinite (FLT_MAX)" @click="commit('FLT_MAX')">∞</button>
        <input v-bng-text-input class="fun-num" :value="text" @keydown.enter="$event.target.blur()" @change="onText" />
        <button class="fun-reset" :class="{ hidden: !changed }" title="Back to stock" @click="commit(stockValue)">↺</button>
      </span>
    </div>
    <input
      class="fun-range"
      type="range"
      :min="range.min"
      :max="range.max"
      :step="range.step"
      :value="position"
      :disabled="range.disabled"
      :style="trackStyle"
      @input="onInput"
      @change="onChange" />
    <div v-if="sub || changed" class="fun-sub">
      <span v-if="changed">stock {{ fmt(stockValue) }}<template v-if="mode === 'scale'"> (×1)</template></span>
      <span v-if="sub">{{ sub }}</span>
    </div>
  </div>
</template>

<script setup>
// One slider for any JBeam number. The slider is logarithmic around the stock value: the middle
// is stock, the ends are ×0.01 and ×1000. The box takes any number, "inf" / "∞", or "x10".
// mode "value": value is the number itself; mode "scale": value is a multiplier (stock 1).
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, ref, watch } from "vue"

const props = defineProps({
  label: String,
  title: String,
  sub: String,
  mode: { type: String, default: "value" },
  value: { type: [Number, String], default: 0 },
  stock: { type: [Number, String], default: 0 },
})
const emit = defineEmits(["change"])

const LOG_MIN = -2
const LOG_MAX = 3

const isInf = x => x === "FLT_MAX" || x === "-FLT_MAX"
const stockValue = computed(() => (props.mode === "scale" ? 1 : props.stock))
const dragging = ref(null) // value while the slider is held
const shown = computed(() => (dragging.value !== null ? dragging.value : props.value))
watch(() => props.value, () => (dragging.value = null))

function same(a, b) {
  if (isInf(a) || isInf(b)) return a === b
  const x = Number(a), y = Number(b)
  return Math.abs(x - y) <= 1e-9 * Math.max(1, Math.abs(y))
}
const changed = computed(() => !same(props.value, stockValue.value))

// log slider around a finite, non-zero base; linear 0..100 when stock is 0; no slider for infinite stock
const base = computed(() => (isInf(stockValue.value) ? null : Number(stockValue.value)))
const logMode = computed(() => base.value !== null && base.value !== 0)
const range = computed(() => {
  if (logMode.value) return { min: LOG_MIN, max: LOG_MAX, step: 0.005, disabled: false }
  if (base.value === 0) return { min: 0, max: 100, step: 0.01, disabled: false }
  return { min: 0, max: 1, step: 1, disabled: true }
})
const position = computed(() => {
  const v = shown.value
  if (!logMode.value) return isInf(v) ? range.value.max : Math.min(Math.max(Number(v) || 0, range.value.min), range.value.max)
  if (isInf(v)) return LOG_MAX
  const ratio = Number(v) / base.value
  if (!(ratio > 0)) return LOG_MIN
  return Math.min(Math.max(Math.log10(ratio), LOG_MIN), LOG_MAX)
})
function fromPosition(p) {
  if (!logMode.value) return round(p)
  if (Math.abs(p) < 0.01) return base.value // snap to stock
  return round(base.value * Math.pow(10, p))
}
function round(v) {
  if (v === 0 || !isFinite(v)) return v
  const digits = 4 - Math.floor(Math.log10(Math.abs(v)))
  const f = Math.pow(10, Math.max(Math.min(digits, 12), -12))
  return Math.round(v * f) / f
}

// fill the track from the stock point to the current value
const trackStyle = computed(() => {
  const span = range.value.max - range.value.min || 1
  const stockPos = logMode.value ? 0 : (base.value === 0 ? 0 : range.value.min)
  const a = ((stockPos - range.value.min) / span) * 100
  const b = ((position.value - range.value.min) / span) * 100
  const lo = Math.min(a, b), hi = Math.max(a, b)
  const fill = "var(--bng-orange, #ff6600)"
  const bg = "rgba(255,255,255,0.14)"
  return { background: `linear-gradient(90deg, ${bg} ${lo}%, ${fill} ${lo}%, ${fill} ${hi}%, ${bg} ${hi}%)` }
})

function fmt(v) {
  if (v === "FLT_MAX") return "∞"
  if (v === "-FLT_MAX") return "−∞"
  const n = Number(v)
  if (!isFinite(n)) return String(v)
  const a = Math.abs(n)
  let s
  if (a !== 0 && (a < 0.001 || a >= 1e12)) s = n.toExponential(3)
  else s = n.toLocaleString("en-US", { maximumSignificantDigits: 6 })
  return props.mode === "scale" ? "×" + s : s
}
const text = computed(() => fmt(shown.value))

function onInput(e) { dragging.value = fromPosition(parseFloat(e.target.value)) }
function onChange(e) { commit(fromPosition(parseFloat(e.target.value))) }
function commit(v) {
  dragging.value = null
  emit("change", v)
}
function onText(e) {
  const raw = String(e.target.value).trim().toLowerCase().replace(/,/g, "").replace("×", "x")
  if (["inf", "∞", "flt_max", "infinite", "infinity"].includes(raw)) return commit("FLT_MAX")
  if (["-inf", "−∞", "-flt_max"].includes(raw)) return commit("-FLT_MAX")
  const times = raw.match(/^x\s*(-?[\d.e+-]+)$/)
  if (times) {
    const k = parseFloat(times[1])
    if (!isNaN(k)) {
      if (props.mode === "scale") return commit(k)
      if (base.value !== null) return commit(round(base.value * k))
    }
  }
  const v = parseFloat(raw)
  if (!isNaN(v)) return commit(v)
  e.target.value = text.value
}
</script>

<style lang="scss" scoped>
.fun-slider {
  padding: 0.45rem 0.6rem 0.5rem;
  border-radius: 0.5rem;
  background: rgba(255, 255, 255, 0.035);
  margin-bottom: 0.35rem;
  &.changed { background: rgba(255, 102, 0, 0.08); }
}
.fun-head { display: flex; align-items: center; justify-content: space-between; gap: 0.4rem; margin-bottom: 0.3rem; }
.fun-label { font-weight: 600; font-size: 0.85rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.fun-ctrl { display: flex; align-items: center; gap: 0.2rem; flex-shrink: 0; }
.fun-num {
  width: 6.2rem;
  text-align: right;
  border: 1px solid transparent;
  background: rgba(0, 0, 0, 0.25);
  color: #fff;
  border-radius: 0.3rem;
  padding: 0.18rem 0.35rem;
  font-size: 0.85rem;
  font-variant-numeric: tabular-nums;
  outline: none;
  &:focus { border-color: var(--bng-orange, #ff6600); }
}
.fun-inf, .fun-reset {
  border: 0;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: 0.3rem;
  background: rgba(255, 255, 255, 0.06);
  color: rgba(255, 255, 255, 0.7);
  cursor: pointer;
  font-size: 0.9rem;
  line-height: 1;
  &:hover { background: rgba(255, 255, 255, 0.16); }
}
.fun-inf.on { color: var(--bng-orange, #ff6600); }
.fun-reset { background: transparent; color: var(--bng-orange, #ff6600); &.hidden { visibility: hidden; } }
.fun-range {
  -webkit-appearance: none;
  appearance: none;
  width: 100%;
  height: 5px;
  border-radius: 3px;
  outline: none;
  cursor: pointer;
  &:disabled { opacity: 0.35; cursor: default; }
  &::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: #fff;
    border: 3px solid var(--bng-orange, #ff6600);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.5);
  }
}
.fun-sub { display: flex; justify-content: space-between; gap: 0.5rem; font-size: 0.72rem; opacity: 0.55; margin-top: 0.25rem; }
</style>
