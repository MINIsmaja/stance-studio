<template>
  <div class="fun-curve" :class="{ changed }">
    <div class="fun-curve-title">
      <span>Torque curve</span>
      <button v-if="changed" class="fun-link" @click="emit('change', copy(stock))">↺ Stock curve</button>
    </div>
    <div class="fun-curve-grid head">
      <span>RPM</span><span>Torque (N·m)</span><span>hp</span><span></span>
    </div>
    <div v-for="(r, i) in rows" :key="i" class="fun-curve-grid" :class="{ edited: rowChanged(i) }">
      <input v-bng-text-input class="fun-cell" :value="num(r[0])" @keydown.enter="$event.target.blur()" @change="e => setCell(i, 0, e)" />
      <input v-bng-text-input class="fun-cell" :value="num(r[1])" @keydown.enter="$event.target.blur()" @change="e => setCell(i, 1, e)" />
      <span class="fun-hp">{{ num(hpAt(r)) }}</span>
      <button class="fun-x" :disabled="rows.length <= 2" title="Remove this point" @click="removeRow(i)">✕</button>
    </div>
    <div class="fun-curve-tools">
      <button class="ss-btn ss-small" @click="addRow">+ Add point</button>
      <span class="fun-curve-times">
        <span class="ss-muted">Torque</span>
        <button v-for="k in [2, 10, 100]" :key="k" class="ss-chip" @click="times(k)">×{{ k }}</button>
        <input v-bng-text-input class="fun-cell fun-times" placeholder="×" @keydown.enter="$event.target.blur()" @change="customTimes" />
        <button class="ss-chip fun-million" title="Scale the torque so the curve peaks at 1,000,000 hp" @click="million">1,000,000 hp</button>
      </span>
    </div>
    <div class="ss-muted fun-curve-note">
      Peak {{ num(peak.hp) }} hp at {{ num(peak.rpm) }} rpm (from this curve; boost comes on top).
      <span v-if="endsEarly" class="fun-warn-text">The curve ends at {{ num(lastRpm) }} rpm, below max RPM ({{ num(maxRpm) }}): the engine holds its last torque up to max RPM. Add points to shape it.</span>
    </div>
  </div>
</template>

<script setup>
// The engine's torque curve as an editable RPM → torque table (like editing it in the JBeam file).
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed } from "vue"

const props = defineProps({
  rows: { type: Array, default: () => [] },   // [[rpm, torque], ...] as it is now (with your changes)
  stock: { type: Array, default: () => [] },
  maxRpm: { type: Number, default: 0 },
})
const emit = defineEmits(["change"])

const HP = 1 / 7120.9 // N·m × rpm → hp
const copy = rows => rows.map(r => [Number(r[0]), Number(r[1])])
const hpAt = r => Math.max(Number(r[0]) * Number(r[1]) * HP, 0)

function num(v) {
  const n = Number(v)
  if (!isFinite(n)) return String(v)
  const a = Math.abs(n)
  if (a >= 1e12) return n.toExponential(2)
  return n.toLocaleString("en-US", { maximumFractionDigits: a >= 100 ? 0 : 1 })
}

function sameRows(a, b) {
  if (a.length !== b.length) return false
  return a.every((r, i) => Math.abs(r[0] - b[i][0]) < 1e-6 && Math.abs(r[1] - b[i][1]) < 1e-6)
}
const changed = computed(() => !sameRows(copy(props.rows), copy(props.stock)))
function rowChanged(i) {
  const s = props.stock[i]
  const r = props.rows[i]
  return !s || Math.abs(r[0] - s[0]) > 1e-6 || Math.abs(r[1] - s[1]) > 1e-6
}

const peak = computed(() => {
  let best = { hp: 0, rpm: 0 }
  for (const r of props.rows) {
    const hp = hpAt(r)
    if (hp > best.hp) best = { hp, rpm: Number(r[0]) }
  }
  return best
})
const lastRpm = computed(() => props.rows.reduce((m, r) => Math.max(m, Number(r[0])), 0))
const endsEarly = computed(() => props.maxRpm > 0 && lastRpm.value < props.maxRpm * 0.98)

function parse(e) {
  const v = parseFloat(String(e.target.value).replace(/,/g, ""))
  return isNaN(v) ? null : v
}
function setCell(i, c, e) {
  const v = parse(e)
  if (v === null || (c === 0 && v < 0)) { e.target.value = num(props.rows[i][c]); return }
  const rows = copy(props.rows)
  rows[i][c] = v
  emit("change", rows)
}
function addRow() {
  const rows = copy(props.rows)
  const last = rows[rows.length - 1] || [0, 0]
  rows.push([last[0] + 500, last[1]])
  emit("change", rows)
}
function removeRow(i) {
  if (props.rows.length <= 2) return
  const rows = copy(props.rows)
  rows.splice(i, 1)
  emit("change", rows)
}
function times(k) {
  if (!(k > 0) || !isFinite(k)) return
  emit("change", copy(props.rows).map(r => [r[0], Math.round(r[1] * k * 100) / 100]))
}
function customTimes(e) {
  const v = parseFloat(String(e.target.value).replace(/[x×,\s]/gi, ""))
  e.target.value = ""
  times(v)
}
function million() {
  if (peak.value.hp > 0) times(1e6 / peak.value.hp)
}
</script>

<style lang="scss" scoped>
.fun-curve {
  padding: 0.55rem 0.6rem 0.5rem;
  border-radius: 0.5rem;
  background: rgba(255, 255, 255, 0.035);
  margin-bottom: 0.35rem;
  &.changed { background: rgba(255, 102, 0, 0.08); }
}
.fun-curve-title { display: flex; justify-content: space-between; align-items: center; font-weight: 600; font-size: 0.85rem; margin-bottom: 0.4rem; }
.fun-link { border: 0; background: transparent; color: var(--bng-orange, #ff6600); font-size: 0.78rem; font-weight: 600; cursor: pointer; }
.fun-curve-grid {
  display: grid;
  grid-template-columns: 1fr 1.25fr 0.9fr 1.6rem;
  gap: 0.3rem;
  align-items: center;
  margin-bottom: 0.2rem;
  &.head { font-size: 0.7rem; letter-spacing: 0.06em; text-transform: uppercase; opacity: 0.5; margin-bottom: 0.3rem; }
  &.edited .fun-cell { border-color: rgba(255, 102, 0, 0.5); }
}
.fun-cell {
  width: 100%;
  box-sizing: border-box;
  border: 1px solid transparent;
  background: rgba(0, 0, 0, 0.25);
  color: #fff;
  border-radius: 0.3rem;
  padding: 0.22rem 0.4rem;
  font-size: 0.85rem;
  font-variant-numeric: tabular-nums;
  text-align: right;
  outline: none;
  &:focus { border-color: var(--bng-orange, #ff6600); }
}
.fun-hp { text-align: right; font-size: 0.82rem; opacity: 0.75; font-variant-numeric: tabular-nums; }
.fun-x {
  border: 0;
  height: 1.5rem;
  border-radius: 0.3rem;
  background: transparent;
  color: rgba(255, 255, 255, 0.5);
  cursor: pointer;
  &:hover:not(:disabled) { color: #fca5a5; background: rgba(248, 113, 113, 0.12); }
  &:disabled { opacity: 0.25; cursor: default; }
}
.fun-curve-tools { display: flex; flex-wrap: wrap; gap: 0.4rem; align-items: center; justify-content: space-between; margin: 0.5rem 0 0.35rem; }
.fun-curve-times { display: flex; flex-wrap: wrap; gap: 0.3rem; align-items: center; }
.fun-times { width: 3.4rem; text-align: center; }
.fun-million { border-color: rgba(240, 171, 252, 0.6); color: #f0abfc; }
.fun-curve-note { font-size: 0.75rem; line-height: 1.35; }
.fun-warn-text { color: #fca5a5; display: block; margin-top: 0.2rem; }
</style>
