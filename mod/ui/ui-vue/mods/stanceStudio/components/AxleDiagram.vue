<template>
  <div class="ss-diagram">
    <svg viewBox="0 0 360 240" preserveAspectRatio="xMidYMid meet">
      <!-- body (fixed): the wheels move relative to it, like looking at the car from the front -->
      <path :d="bodyPath" class="body" />
      <line :x1="fenderL" :x2="fenderL" y1="34" :y2="archBottom" class="fender" />
      <line :x1="fenderR" :x2="fenderR" y1="34" :y2="archBottom" class="fender" />

      <!-- ground under the new wheel position -->
      <line x1="8" x2="352" :y1="groundNew" :y2="groundNew" class="ground" />

      <g v-for="w in wheels" :key="w.key">
        <g :transform="`translate(${w.cur.x} ${w.cur.y}) rotate(${w.cur.rot})`" v-if="moving">
          <rect :x="-tw / 2" :y="-tr" :width="tw" :height="tr * 2" rx="5" class="tire-now" />
        </g>
        <g :transform="`translate(${w.next.x} ${w.next.y}) rotate(${w.next.rot})`">
          <rect :x="-tw / 2" :y="-tr" :width="tw" :height="tr * 2" rx="5" class="tire" :class="{ ghost: moving }" />
          <rect :x="-tw / 2 + 3" :y="-tr * 0.62" :width="tw - 6" :height="tr * 1.24" rx="2" class="rim" />
        </g>
      </g>

      <text x="180" y="16" text-anchor="middle" class="caption">{{ title }} · seen from the front</text>
    </svg>
    <div class="ss-fit">
      <div><span>Camber</span><b>{{ fmtDeg(pending.camber) }}</b></div>
      <div><span>Track</span><b>{{ fmtLen(pending.offset, true) }}</b></div>
      <div><span>Height</span><b>{{ fmtLen(pending.rideHeight, true) }}</b></div>
      <div :title="'Outer top edge of the tire compared to stock'"><span>Top edge</span><b :class="topClass">{{ topText }}</b></div>
    </div>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { units } from "../api.js"

const props = defineProps({
  applied: { type: Object, required: true },
  pending: { type: Object, required: true },
  wheel: { type: Object, default: () => ({}) },
  settings: { type: Object, default: () => ({}) },
  title: { type: String, default: "Front axle" },
})

const radius = computed(() => props.wheel.radius || 0.33)
const width = computed(() => props.wheel.width || 0.23)
const halfTrack = computed(() => props.wheel.halfTrack || 0.78)
const scale = computed(() => 300 / (2 * (halfTrack.value + width.value / 2 + 0.16)))
const tr = computed(() => radius.value * scale.value)
const tw = computed(() => width.value * scale.value)
const groundStock = 168
const centerStockY = computed(() => groundStock - tr.value)
const fenderX = computed(() => (halfTrack.value + width.value / 2 + 0.012) * scale.value)
const fenderL = computed(() => 180 - fenderX.value)
const fenderR = computed(() => 180 + fenderX.value)
const archBottom = computed(() => centerStockY.value - tr.value * 0.15)

const moving = computed(() => ["camber", "offset", "rideHeight", "toe"].some(k => Math.abs((props.pending[k] || 0) - (props.applied[k] || 0)) > 1e-5))

function place(v, sideSign) {
  // sideSign: -1 = wheel drawn on the left, +1 = right; negative camber leans the top inward
  const x = 180 + sideSign * (halfTrack.value + (v.offset || 0)) * scale.value
  // positive ride height = lift = the wheel drops below the (fixed) body; kept inside the picture
  const dy = Math.min(Math.max((v.rideHeight || 0) * scale.value, 2 + 2 * tr.value - groundStock), 236 - groundStock)
  const y = centerStockY.value + dy
  const rot = sideSign * (v.camber || 0)
  return { x, y, rot }
}
const wheels = computed(() => [-1, 1].map(s => ({ key: s, cur: place(props.applied, s), next: place(props.pending, s) })))
const groundNew = computed(() => wheels.value[0].next.y + tr.value)

const bodyPath = computed(() => {
  const f = fenderX.value
  const top = 30, belt = 62
  const arch = archBottom.value
  const l = 180 - f, r = 180 + f
  return `M ${l + 26} ${top} L ${r - 26} ${top} Q ${r - 6} ${top + 4} ${r} ${belt} L ${r} ${arch} L ${r - tw.value - 10} ${arch}` +
    ` L ${r - tw.value - 10} ${arch + 18} L ${l + tw.value + 10} ${arch + 18} L ${l + tw.value + 10} ${arch} L ${l} ${arch} L ${l} ${belt} Q ${l + 6} ${top + 4} ${l + 26} ${top} Z`
})

// outer top edge of the tire, relative to the stock wheel (positive = sticks out more)
function topOuter(v) {
  const a = ((v.camber || 0) * Math.PI) / 180
  const w = width.value / 2, r = radius.value
  return halfTrack.value + (v.offset || 0) + w * Math.cos(a) + r * Math.sin(a)
}
const topDelta = computed(() => topOuter(props.pending) - topOuter({ camber: 0, offset: 0 }))
const topText = computed(() => {
  const d = topDelta.value
  if (Math.abs(d) < 0.002) return "stock"
  return (d > 0 ? "out " : "in ") + fmtLen(Math.abs(d), false)
})
const topClass = computed(() => (topDelta.value > 0.01 ? "poke" : topDelta.value < -0.01 ? "tuck" : ""))

function fmtLen(m, signed) {
  const v = units.toDisplay(m || 0, props.settings)
  const dec = props.settings.units === "imperial" ? 2 : 0
  const s = v.toFixed(dec)
  return (signed && v > 0 ? "+" : "") + s + " " + units.lengthUnit(props.settings)
}
function fmtDeg(d) {
  return ((d || 0) > 0 ? "+" : "") + (d || 0).toFixed(1) + "°"
}
</script>

<style lang="scss" scoped>
.ss-diagram {
  background: rgba(0, 0, 0, 0.28);
  border-radius: 0.6rem;
  padding: 0.4rem 0.4rem 0.6rem;
  margin-bottom: 0.8rem;
}
svg { width: 100%; height: auto; display: block; }
.body { fill: rgba(255, 255, 255, 0.07); stroke: rgba(255, 255, 255, 0.35); stroke-width: 1.2; }
.fender { stroke: rgba(255, 102, 0, 0.55); stroke-dasharray: 4 4; stroke-width: 1.2; }
.ground { stroke: rgba(255, 255, 255, 0.25); stroke-width: 1.5; }
.tire { fill: #23262c; stroke: #e9edf2; stroke-width: 1.4; transition: transform 0.08s; }
.tire.ghost { fill: rgba(56, 189, 248, 0.28); stroke: #38bdf8; }
.tire-now { fill: none; stroke: rgba(255, 255, 255, 0.55); stroke-dasharray: 3 3; stroke-width: 1.2; }
.rim { fill: rgba(255, 255, 255, 0.14); }
.caption { fill: rgba(255, 255, 255, 0.45); font-size: 10px; }
.ss-fit {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 0.3rem;
  padding: 0 0.4rem;
  font-size: 0.78rem;
  span { display: block; opacity: 0.55; }
  b { font-variant-numeric: tabular-nums; }
  b.poke { color: #fca5a5; }
  b.tuck { color: #93c5fd; }
}
</style>
