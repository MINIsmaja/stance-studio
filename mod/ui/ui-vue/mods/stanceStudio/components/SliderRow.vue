<template>
  <div class="ss-slider" :class="{ changed }">
    <div class="ss-slider-head">
      <span class="ss-slider-label" :title="hint">{{ label }}</span>
      <span class="ss-slider-ctrl">
        <button class="ss-step" title="Smaller" @click="nudge(-1)">−</button>
        <input v-bng-text-input class="ss-num" :value="text" @focus="editing = true" @blur="editing = false" @keydown.enter="$event.target.blur()" @change="onText" />
        <span class="ss-unit">{{ unit }}</span>
        <button class="ss-step" title="Bigger" @click="nudge(1)">+</button>
        <button class="ss-reset" :class="{ hidden: !changed }" title="Back to stock" @click="commit(stock)">↺</button>
      </span>
    </div>
    <input
      class="ss-range"
      type="range"
      :min="min"
      :max="max"
      :step="step"
      :value="clamped"
      :style="trackStyle"
      @pointerdown="emit('grab')"
      @input="onInput"
      @change="onChange" />
    <div v-if="hint" class="ss-slider-hint">{{ hint }}</div>
  </div>
</template>

<script setup>
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, ref } from "vue"

const props = defineProps({
  label: String,
  value: { type: Number, default: 0 },
  min: { type: Number, default: -1 },
  max: { type: Number, default: 1 },
  step: { type: Number, default: 0.01 },
  unit: { type: String, default: "" },
  decimals: { type: Number, default: 1 },
  stock: { type: Number, default: 0 },
  signed: { type: Boolean, default: true },
  hint: String,
})
const emit = defineEmits(["input", "commit", "grab"])
const editing = ref(false)

const changed = computed(() => Math.abs(props.value - props.stock) > props.step / 2)
const clamped = computed(() => Math.min(Math.max(props.value, props.min), props.max))
const text = computed(() => {
  const v = props.value.toFixed(props.decimals)
  return props.signed && props.value > 0 ? "+" + v : v
})

// fill the track from the stock point to the current value
const trackStyle = computed(() => {
  const span = props.max - props.min || 1
  const a = ((Math.min(Math.max(props.stock, props.min), props.max) - props.min) / span) * 100
  const b = ((clamped.value - props.min) / span) * 100
  const lo = Math.min(a, b), hi = Math.max(a, b)
  const fill = "var(--bng-orange, #ff6600)"
  const base = "rgba(255,255,255,0.14)"
  return { background: `linear-gradient(90deg, ${base} ${lo}%, ${fill} ${lo}%, ${fill} ${hi}%, ${base} ${hi}%)` }
})

function round(v) {
  const f = Math.pow(10, Math.max(props.decimals, 0) + 1)
  return Math.round(v * f) / f
}
function onInput(e) { emit("input", round(parseFloat(e.target.value))) }
function onChange(e) { emit("commit", round(parseFloat(e.target.value))) }
function commit(v) { emit("commit", round(v)) }
function nudge(dir) { commit(props.value + dir * props.step) }
function onText(e) {
  const v = parseFloat(String(e.target.value).replace(",", "."))
  if (!isNaN(v)) commit(v)
  else e.target.value = text.value
}
</script>

<style lang="scss" scoped>
.ss-slider {
  padding: 0.55rem 0.7rem 0.65rem;
  border-radius: 0.55rem;
  background: rgba(255, 255, 255, 0.035);
  margin-bottom: 0.45rem;
  &.changed { background: rgba(255, 102, 0, 0.07); }
}
.ss-slider-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.35rem; }
.ss-slider-label { font-weight: 600; font-size: 0.92rem; }
.ss-slider-ctrl { display: flex; align-items: center; gap: 0.2rem; }
.ss-num {
  width: 4.2rem;
  text-align: right;
  border: 1px solid transparent;
  background: rgba(0, 0, 0, 0.25);
  color: #fff;
  border-radius: 0.3rem;
  padding: 0.2rem 0.35rem;
  font-size: 0.9rem;
  font-variant-numeric: tabular-nums;
  outline: none;
  &:focus { border-color: var(--bng-orange, #ff6600); }
}
.ss-unit { width: 1.9rem; font-size: 0.78rem; opacity: 0.6; }
.ss-step, .ss-reset {
  border: 0;
  width: 1.6rem;
  height: 1.6rem;
  border-radius: 0.3rem;
  background: rgba(255, 255, 255, 0.08);
  color: #fff;
  cursor: pointer;
  font-size: 0.95rem;
  line-height: 1;
  &:hover { background: rgba(255, 255, 255, 0.18); }
}
.ss-reset { background: transparent; color: var(--bng-orange, #ff6600); &.hidden { visibility: hidden; } }
.ss-range {
  -webkit-appearance: none;
  appearance: none;
  width: 100%;
  height: 6px;
  border-radius: 3px;
  outline: none;
  cursor: pointer;
  &::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: #fff;
    border: 3px solid var(--bng-orange, #ff6600);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.5);
  }
}
.ss-slider-hint { font-size: 0.75rem; opacity: 0.5; margin-top: 0.3rem; }
</style>
