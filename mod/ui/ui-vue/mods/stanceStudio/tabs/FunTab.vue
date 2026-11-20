<template>
  <div class="ss-fun">
    <div class="fun-top">
      <div><span class="ss-muted">Engine now</span> <b>{{ hpText }}</b></div>
      <button class="ss-btn ss-small" :disabled="!appliedCount || busy" @click="askReset = !askReset">Reset car to stock</button>
    </div>
    <div v-if="askReset" class="fun-confirm">
      <span>Undo all {{ appliedCount }} change{{ appliedCount === 1 ? "" : "s" }} to this car?</span>
      <span class="ss-row">
        <button class="ss-btn ss-small ss-primary" @click="resetAll">Reset</button>
        <button class="ss-btn ss-small" @click="askReset = false">Cancel</button>
      </span>
    </div>
    <div v-if="missed.length" class="fun-warn">
      <span>{{ missed.length }} change{{ missed.length === 1 ? " does" : "s do" }} not fit this car's current parts.</span>
      <button class="ss-btn ss-small" @click="dropMissed">Remove {{ missed.length === 1 ? "it" : "them" }}</button>
    </div>

    <div v-if="loading" class="ss-muted">Reading this car…</div>
    <template v-else>
      <!-- ENGINE -->
      <div v-if="!engines.length" class="fun-card">
        <div class="fun-card-title">Engine</div>
        <div class="ss-muted">This vehicle has no combustion engine.</div>
      </div>
      <div v-for="e in engines" :key="e.name" class="fun-card">
        <div class="fun-card-title">{{ engines.length > 1 ? e.name : "Engine" }}</div>

        <label class="fun-toggle" :class="{ on: has('indestructibleEngine', e.name) }">
          <input type="checkbox" :checked="has('indestructibleEngine', e.name)" @change="ev => flag('indestructibleEngine', e.name, ev.target.checked)" />
          <span><b>Indestructible engine</b><small>No damage from too much torque, over-revving, heat, oil starvation, water or crashes.</small></span>
        </label>
        <label class="fun-toggle" :class="{ on: has('noRevLimiter', e.name) }">
          <input type="checkbox" :checked="has('noRevLimiter', e.name) || !e.stockRevLimiter" :disabled="!e.stockRevLimiter"
            @change="ev => flag('noRevLimiter', e.name, ev.target.checked)" />
          <span><b>No rev limiter</b><small>{{ e.stockRevLimiter ? "Rev it as high as it goes. Pair it with Indestructible." : "This engine has no rev limiter." }}</small></span>
        </label>

        <FunSlider label="Max RPM" unit="rpm" :value="qVal('maxRPM', e.name, 'value', e.stockMaxRPM)" :stock="e.stockMaxRPM"
          :log-min="-0.5" :log-max="1" no-inf @change="v => qSet('maxRPM', e.name, { value: v }, v === e.stockMaxRPM)" />

        <FunCurve :rows="curveOf(e)" :stock="list(e.stockCurve)" :max-rpm="Number(qVal('maxRPM', e.name, 'value', e.stockMaxRPM))"
          @change="rows => setCurve(e, rows)" />

        <FunSlider v-if="e.boost" :label="e.boost.kind === 'turbo' ? 'Turbo boost' : 'Supercharger boost'" unit="psi"
          :sub="e.boost.kind === 'turbo' ? 'Wastegate target' : 'At the blower’s top speed'"
          :value="qVal('boost', e.name, 'psi', e.boost.stock)" :stock="e.boost.stock" :min="0" :max="boostMax(e)" :step="0.5" no-inf
          @change="v => qSet('boost', e.name, { psi: v }, same(v, e.boost.stock))" />
        <div v-else class="fun-none">No turbo or supercharger on this engine. Put one on in the Performance tab to get a boost slider.</div>

        <FunSlider label="Pops & bangs" sub="0 = none, most stock engines are 2 to 5"
          :value="qVal('afterfire', e.name, 'level', round1(e.afterfire.stock))" :stock="round1(e.afterfire.stock)" :min="0" :max="20" :step="0.5" no-inf
          @change="v => qSet('afterfire', e.name, { level: v }, same(v, round1(e.afterfire.stock)))" />

        <FunSlider v-if="e.nitrous" label="Nitrous shot" unit="hp" :value="qVal('nitrous', e.name, 'hp', roundHp(e.nitrous.stock))" :stock="roundHp(e.nitrous.stock)"
          :min="0" :max="2000" :step="5" no-inf @change="v => qSet('nitrous', e.name, { hp: v }, same(v, roundHp(e.nitrous.stock)))" />
      </div>

      <!-- CAR -->
      <div class="fun-card">
        <div class="fun-card-title">Car</div>
        <FunSlider label="Weight" mode="scale" :sub="weightText" :value="qVal('weight', null, 'scale', 1)" :stock="1" :log-min="-1" :log-max="1"
          @change="k => qSet('weight', null, { scale: k }, same(k, 1))" />
        <FunSlider v-if="car.wheels" label="Tire grip" mode="scale" sub="Below ×1 = drift tires, above = glue" :value="qVal('grip', null, 'scale', 1)" :stock="1"
          :log-min="-1" :log-max="1" @change="k => qSet('grip', null, { scale: k }, same(k, 1))" />
        <FunSlider v-if="car.wheels" label="Brake power" mode="scale" :value="qVal('brakes', null, 'scale', 1)" :stock="1" :log-min="-1" :log-max="1.3"
          @change="k => qSet('brakes', null, { scale: k }, same(k, 1))" />
        <label class="fun-toggle" :class="{ on: has('unbreakable') }">
          <input type="checkbox" :checked="has('unbreakable')" @change="ev => { flag('unbreakable', null, ev.target.checked); if (ev.target.checked) flag('fragile', null, false) }" />
          <span><b>Unbreakable car</b><small>Nothing bends or breaks, whatever you hit.</small></span>
        </label>
        <label class="fun-toggle" :class="{ on: has('fragile') }">
          <input type="checkbox" :checked="has('fragile')" @change="ev => { flag('fragile', null, ev.target.checked); if (ev.target.checked) flag('unbreakable', null, false) }" />
          <span><b>Paper car</b><small>Crumples at the slightest touch. Great for crash tests.</small></span>
        </label>
      </div>

      <!-- WORLD -->
      <div class="fun-card">
        <div class="fun-card-title">World <span class="ss-muted fun-card-note">changes right away, the whole map, not saved with the car</span></div>
        <div class="fun-label">Gravity <span class="ss-muted">{{ gText }}</span></div>
        <div class="ss-row fun-chips">
          <button v-for="p in gravityPresets" :key="p.label" class="ss-chip" :class="{ active: Math.abs(g - p.g) < 0.01 }" @click="setGravity(p.g)">{{ p.label }}</button>
        </div>
        <FunSlider label="Custom gravity" unit="m/s²" :value="g" :stock="9.81" :min="-10" :max="30" :step="0.01" no-inf @change="setGravity" />
        <div class="fun-label">Speed of time</div>
        <div class="ss-row fun-chips">
          <button v-for="p in speedPresets" :key="p.label" class="ss-chip" :class="{ active: Math.abs(simSpeed - p.s) < 0.001 }" @click="setSpeed(p.s)">{{ p.label }}</button>
        </div>
      </div>

      <!-- ADVANCED -->
      <div class="fun-card">
        <button class="fun-adv-head" @click="advanced = !advanced">
          <span>Advanced: every JBeam value</span><span class="ss-muted">{{ advanced ? "▾" : "▸" }}</span>
        </button>
        <FunAdvanced v-if="advanced" :api="api" :pending="pending" :reload-key="reloadKey" />
      </div>
    </template>

    <div v-if="dirty || busy" class="fun-bar">
      <span v-if="busy">Respawning with your changes…</span>
      <span v-else>{{ dirtyCount }} change{{ dirtyCount === 1 ? "" : "s" }} not applied</span>
      <span class="ss-row">
        <button class="ss-btn ss-small" :disabled="busy" @click="discard">Discard</button>
        <button class="ss-btn ss-small ss-primary" :disabled="busy" @click="apply">Apply</button>
      </span>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch, onMounted } from "vue"
import { luaCall, list } from "../api.js"
import { store, notify } from "../store.js"
import FunSlider from "../components/FunSlider.vue"
import FunCurve from "../components/FunCurve.vue"
import FunAdvanced from "../components/FunAdvanced.vue"

const loading = ref(true)
const busy = ref(false)
const askReset = ref(false)
const advanced = ref(false)
const info = ref({})
const applied = ref({})  // edits on the car right now (id -> edit)
const pending = ref({})  // edits with your unapplied changes
const reloadKey = ref(0)

const engines = computed(() => list(info.value.engines))
const car = computed(() => info.value.car || {})
const missed = computed(() => list(info.value.missed))

const clone = x => JSON.parse(JSON.stringify(x || {}))
const isInf = x => x === "FLT_MAX" || x === "-FLT_MAX"
function same(a, b) {
  if (typeof a === "number" && typeof b === "number") return Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(b))
  return a === b
}
const round1 = v => Math.round(Number(v || 0) * 2) / 2
const roundHp = v => Math.round(Number(v || 0))

async function load() {
  const res = await luaCall("stanceStudio_core.funQuick")
  info.value = res || {}
  applied.value = res?.edits && typeof res.edits === "object" && !Array.isArray(res.edits) ? res.edits : {}
  pending.value = clone(applied.value)
  if (res?.world) { g.value = -Number(res.world.gravity); simSpeed.value = Number(res.world.simSpeed) || 1 }
  loading.value = false
  reloadKey.value++
}

// MARK: pending edits
function put(id, edit) { pending.value = { ...pending.value, [id]: edit } }
function drop(id) { const p = { ...pending.value }; delete p[id]; pending.value = p }
const qid = (name, engine) => `q|${name}|${engine || ""}`

function has(name, engine) { return !!pending.value[qid(name, engine)] }
function quick(name, engine, fields) {
  const e = { kind: "quick", name, ...fields }
  if (engine) e.engine = engine
  return e
}
function flag(name, engine, on) {
  if (on) put(qid(name, engine), quick(name, engine, { value: true }))
  else drop(qid(name, engine))
}
function qVal(name, engine, field, stock) {
  const e = pending.value[qid(name, engine)]
  return e && e[field] !== undefined ? e[field] : stock
}
function qSet(name, engine, fields, isStock) {
  if (isStock || Object.values(fields).some(v => isInf(v) || v === null || v === undefined || (typeof v === "number" && !isFinite(v)))) drop(qid(name, engine))
  else put(qid(name, engine), quick(name, engine, fields))
}

function curveOf(e) {
  const p = pending.value[qid("curve", e.name)]
  return list(p ? p.rows : e.stockCurve).map(r => list(r).map(Number))
}
function setCurve(e, rows) {
  const stock = list(e.stockCurve).map(r => list(r).map(Number))
  const isStock = rows.length === stock.length && rows.every((r, i) => same(r[0], stock[i][0]) && same(r[1], stock[i][1]))
  if (isStock) drop(qid("curve", e.name))
  else put(qid("curve", e.name), quick("curve", e.name, { rows }))
}

const boostMax = e => Math.max(60, Math.ceil((Number(e.boost.stock) || 0) * 4 / 10) * 10)

// the full editor's sliders use the same pending edits
const api = {
  valueOf(f) { const e = pending.value[f.id]; return e && e.value !== undefined ? e.value : f.stock },
  scaleOf(f) { const e = pending.value[f.id]; return e && e.scale !== undefined ? e.scale : 1 },
  setValue(f, v) { if (same(v, f.stock)) drop(f.id); else put(f.id, { kind: "value", path: list(f.path), value: v }) },
  setColumn(f, c, k) {
    if (isInf(k) || !(Number(k) >= 0)) return
    if (same(Number(k), 1)) drop(c.id); else put(c.id, { kind: "column", path: list(f.path), column: c.column, scale: Number(k) })
  },
  setRows(sec, f, k) {
    if (isInf(k) || !(Number(k) >= 0)) return
    if (same(Number(k), 1)) drop(f.id); else put(f.id, { kind: "rows", section: sec.name, field: f.field, scale: Number(k) })
  },
  setRow(sec, r, v, x) { if (same(x, v.stock)) drop(v.id); else put(v.id, { kind: "row", section: sec.name, row: r.row, field: v.field, value: x }) },
}

function editsDiffer(a, b) {
  const ids = new Set([...Object.keys(a), ...Object.keys(b)])
  let n = 0
  for (const id of ids) if (JSON.stringify(a[id] ?? null) !== JSON.stringify(b[id] ?? null)) n++
  return n
}
const dirtyCount = computed(() => editsDiffer(pending.value, applied.value))
const dirty = computed(() => dirtyCount.value > 0)
const appliedCount = computed(() => Object.keys(applied.value).length)

// the car respawns after Apply; if it does not (career mode, no car), give the buttons back
let busyTimer = null
function startBusy() {
  busy.value = true
  clearTimeout(busyTimer)
  busyTimer = setTimeout(() => { if (busy.value) { busy.value = false; load() } }, 15000)
}
async function apply() {
  if (busy.value) return
  startBusy()
  await luaCall("stanceStudio_core.funApply", Object.values(pending.value))
}
function discard() { pending.value = clone(applied.value) }
async function resetAll() {
  askReset.value = false
  pending.value = {}
  startBusy()
  await luaCall("stanceStudio_core.funApply", [])
}
async function dropMissed() {
  const p = { ...applied.value }
  for (const id of missed.value) delete p[id]
  pending.value = p
  await apply()
}

// MARK: car info
const weightText = computed(() => {
  const stock = Number(car.value.stockMass) || 0
  if (!stock) return ""
  const k = Number(qVal("weight", null, "scale", 1)) || 1
  return `${Math.round(stock * k).toLocaleString("en-US")} kg (stock ${Math.round(stock).toLocaleString("en-US")} kg)`
})
const hpText = computed(() => {
  const hp = store.state?.power ?? info.value.power
  if (!hp) return busy.value ? "…" : (engines.value.length ? "…" : "no engine")
  return `${Math.round(hp).toLocaleString("en-US")} hp`
})

// MARK: world (instant)
const g = ref(9.81)        // shown as positive = down, like the game's presets
const simSpeed = ref(1)
const gravityPresets = [
  { label: "Earth", g: 9.81 }, { label: "Moon", g: 1.62 }, { label: "Mars", g: 3.71 },
  { label: "Jupiter", g: 24.92 }, { label: "Zero", g: 0 }, { label: "Upside down", g: -9.81 },
]
const speedPresets = [
  { label: "Normal", s: 1 }, { label: "½ slow-mo", s: 0.5 }, { label: "¼", s: 0.25 }, { label: "⅒", s: 0.1 },
]
const gText = computed(() => {
  const p = gravityPresets.find(x => Math.abs(x.g - g.value) < 0.01)
  return `${g.value.toLocaleString("en-US", { maximumFractionDigits: 2 })} m/s²${p ? " · " + p.label : ""}`
})
async function setGravity(v) {
  const x = Number(v)
  if (!isFinite(x)) return
  g.value = x
  await luaCall("stanceStudio_core.funSetGravity", -x)
}
async function setSpeed(s) {
  simSpeed.value = s
  await luaCall("stanceStudio_core.funSetSimSpeed", s)
}

watch(() => store.state?.spawnCount, async () => {
  const wasBusy = busy.value
  await load()
  if (wasBusy) {
    busy.value = false
    const n = appliedCount.value
    notify(n ? `Respawned with ${n} fun change${n === 1 ? "" : "s"}` : "Back to stock", "info", 3500)
  }
})

onMounted(load)
</script>

<style lang="scss" scoped>
.fun-top { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.6rem; }
.fun-confirm, .fun-warn {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  padding: 0.55rem 0.7rem;
  border-radius: 0.5rem;
  margin-bottom: 0.6rem;
  font-size: 0.82rem;
}
.fun-confirm { background: rgba(255, 102, 0, 0.12); }
.fun-warn { background: rgba(248, 113, 113, 0.14); }
.fun-card {
  padding: 0.7rem 0.7rem 0.45rem;
  border-radius: 0.65rem;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.06);
  margin-bottom: 0.7rem;
}
.fun-card-title { font-weight: 800; font-size: 0.95rem; margin-bottom: 0.55rem; letter-spacing: 0.02em; }
.fun-card-note { font-weight: 400; font-size: 0.72rem; margin-left: 0.3rem; }
.fun-toggle {
  display: flex;
  gap: 0.6rem;
  align-items: flex-start;
  padding: 0.5rem 0.6rem;
  border-radius: 0.5rem;
  background: rgba(255, 255, 255, 0.035);
  margin-bottom: 0.35rem;
  cursor: pointer;
  input { margin-top: 0.2rem; accent-color: var(--bng-orange, #ff6600); }
  span { display: flex; flex-direction: column; gap: 0.1rem; font-size: 0.86rem; }
  small { opacity: 0.6; font-size: 0.74rem; }
  &.on { background: rgba(255, 102, 0, 0.1); }
}
.fun-none { font-size: 0.78rem; opacity: 0.6; padding: 0.4rem 0.2rem 0.5rem; }
.fun-label { font-weight: 600; font-size: 0.85rem; margin: 0.35rem 0 0.35rem 0.1rem; }
.fun-chips { margin-bottom: 0.5rem; gap: 0.35rem; }
.fun-adv-head {
  width: 100%;
  display: flex;
  justify-content: space-between;
  border: 0;
  background: transparent;
  color: #fff;
  padding: 0.1rem 0 0.35rem;
  cursor: pointer;
  font-weight: 700;
  font-size: 0.88rem;
}
.fun-bar {
  position: sticky;
  bottom: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  margin-top: 0.6rem;
  padding: 0.6rem 0.75rem;
  border-radius: 0.6rem;
  background: rgba(30, 32, 38, 0.97);
  border: 1px solid rgba(255, 102, 0, 0.45);
  box-shadow: 0 -0.4rem 1.2rem rgba(0, 0, 0, 0.35);
  font-size: 0.85rem;
  font-weight: 600;
}
</style>
