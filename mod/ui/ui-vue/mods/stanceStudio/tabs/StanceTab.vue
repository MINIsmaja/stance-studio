<template>
  <div class="ss-stance">
    <div class="ss-section">
      <div class="ss-row ss-axle-row">
        <div class="ss-seg ss-grow">
          <button :class="{ active: axle === 'F' }" @click="pickAxle('F')">Front</button>
          <button :class="{ active: axle === 'R' }" @click="pickAxle('R')">Rear</button>
        </div>
        <button class="ss-chip" :class="{ active: link }" title="Change front and rear together" @click="toggleLink">⛓ Link</button>
        <button class="ss-chip" title="Point the camera at this axle" @click="focusAxle">◎ Focus</button>
      </div>
    </div>

    <AxleDiagram
      :applied="applied[axle]"
      :pending="edit[axle]"
      :wheel="wheels[axle] || {}"
      :settings="s"
      :title="axle === 'F' ? 'Front axle' : 'Rear axle'" />

    <div class="ss-status">
      <span v-if="busy" class="ss-badge accent">Applying…</span>
      <span v-else-if="dirty" class="ss-badge accent">Not applied yet</span>
      <span v-if="methodText" class="ss-badge">{{ methodText }}</span>
      <span v-if="measuredText" class="ss-badge good" title="Measured on the car after the last change">{{ measuredText }}</span>
      <span v-if="report && report.error" class="ss-badge warn">Stance error, see console</span>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Quick looks</div>
      <div class="ss-row">
        <button v-for="p in presets" :key="p.id" class="ss-chip" @click="applyPreset(p)">{{ p.label }}</button>
      </div>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Height & fitment</div>
      <SliderRow v-for="d in geometryDefs" :key="d.key" v-bind="d.props" :value="display(d.key)"
        @grab="grab" @input="v => setValue(d.key, v, false)" @commit="v => setValue(d.key, v, true)" />
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Suspension feel</div>
      <SliderRow v-for="d in suspensionDefs" :key="d.key" v-bind="d.props" :value="display(d.key)"
        @grab="grab" @input="v => setValue(d.key, v, false)" @commit="v => setValue(d.key, v, true)" />
    </div>

    <div v-if="axle === 'F'" class="ss-section">
      <div class="ss-section-title">Steering</div>
      <SliderRow v-bind="steerDef.props" :value="display('steer')"
        @grab="grab" @input="v => setValue('steer', v, false)" @commit="v => setValue('steer', v, true)" />
    </div>

    <div class="ss-actions">
      <button v-if="s.applyMode === 'button' || dirty" class="ss-btn ss-primary" :disabled="!dirty || busy" @click="apply">Apply</button>
      <button class="ss-btn" :disabled="!dirty" @click="revert">Undo changes</button>
      <button class="ss-btn" @click="resetAll">Stock stance</button>
    </div>
  </div>
</template>

<script setup>
import { computed, reactive, ref, watch, onMounted, onUnmounted } from "vue"
import { luaCall, throttle, units, list } from "../api.js"
import { store, saveSettings } from "../store.js"
import SliderRow from "../components/SliderRow.vue"
import AxleDiagram from "../components/AxleDiagram.vue"

const KEYS = ["rideHeight", "camber", "toe", "offset", "spring", "damp", "steer"]
const neutral = () => ({ rideHeight: 0, camber: 0, toe: 0, offset: 0, spring: 1, damp: 1, steer: 1 })

const s = computed(() => store.state?.settings || {})
const report = computed(() => store.state?.report)
const wheels = computed(() => store.state?.wheels || {})
const busy = computed(() => !!store.state?.busy)

const axle = ref("F")
const link = ref(!!s.value.linkAxles)
const dirty = ref(false)
let dragging = false

const applied = reactive({ F: neutral(), R: neutral() })
const edit = reactive({ F: neutral(), R: neutral() })

function syncFromState() {
  const st = store.state?.stance
  if (!st) return
  for (const a of ["F", "R"]) {
    for (const k of KEYS) {
      applied[a][k] = st[a]?.[k] ?? neutral()[k]
      if (!dirty.value && !dragging) edit[a][k] = applied[a][k]
    }
  }
}
watch(() => store.state?.stance, syncFromState, { deep: true, immediate: true })

// MARK: slider definitions (display units)
const lenUnit = computed(() => units.lengthUnit(s.value))
const imperial = computed(() => s.value.units === "imperial")
const extreme = computed(() => s.value.range === "extreme")

function lenRange(normal, ext) {
  const r = extreme.value ? ext : normal // mm
  if (!imperial.value) return { min: r[0], max: r[1], step: 1, decimals: 0 }
  return { min: +(r[0] / 25.4).toFixed(1), max: +(r[1] / 25.4).toFixed(1), step: 0.05, decimals: 2 }
}

const geometryDefs = computed(() => [
  { key: "rideHeight", props: { label: "Ride height", unit: lenUnit.value, ...lenRange([-250, 100], [-500, 250]), hint: "Negative = lower. Goes past the bump stops, all the way down to scraping." } },
  { key: "camber", props: { label: "Camber", unit: "°", min: extreme.value ? -30 : -15, max: extreme.value ? 15 : 5, step: 0.1, decimals: 1, hint: "Negative = top of the wheel leans in." } },
  { key: "offset", props: { label: "Wheel offset / track", unit: lenUnit.value, ...lenRange([-30, 120], [-100, 350]), hint: "Per side, like spacers. Positive = wheels further out." } },
  { key: "toe", props: { label: "Toe", unit: "°", min: extreme.value ? -5 : -2, max: extreme.value ? 5 : 2, step: 0.05, decimals: 2, hint: "Positive = toe-in (fronts of the wheels point inward)." } },
])
const steerDef = computed(() => ({ key: "steer", props: { label: "Steering angle", unit: "%", min: 50, max: extreme.value ? 400 : 300, step: 5, decimals: 0, stock: 100, signed: false, hint: "Drift-kit style lock. 100% = stock, 200% = twice the angle." } }))
const suspensionDefs = computed(() => [
  { key: "spring", props: { label: "Spring stiffness", unit: "%", min: extreme.value ? 20 : 50, max: extreme.value ? 500 : 200, step: 1, decimals: 0, stock: 100, signed: false, hint: "100% = stock springs." } },
  { key: "damp", props: { label: "Damping", unit: "%", min: extreme.value ? 20 : 50, max: extreme.value ? 500 : 200, step: 1, decimals: 0, stock: 100, signed: false, hint: "100% = stock shocks." } },
])

function display(key) {
  const v = edit[axle.value][key]
  if (key === "rideHeight" || key === "offset") return units.toDisplay(v, s.value)
  if (key === "spring" || key === "damp" || key === "steer") return v * 100
  return v
}
function toModel(key, v) {
  if (key === "rideHeight" || key === "offset") return units.fromDisplay(v, s.value)
  if (key === "spring" || key === "damp" || key === "steer") return v / 100
  return v
}

// MARK: editing
const plain = () => JSON.parse(JSON.stringify({ F: edit.F, R: edit.R }))
const preview = throttle(() => luaCall("stanceStudio_core.previewStance", plain()), 33)

function setValue(key, v, commit) {
  const m = toModel(key, v)
  edit[axle.value][key] = m
  if (link.value && key !== "steer") edit[axle.value === "F" ? "R" : "F"][key] = m
  if (!commit) {
    dirty.value = true
    preview()
    return
  }
  dragging = false
  if (s.value.applyMode === "button") {
    dirty.value = true
    preview()
  } else {
    apply()
  }
}

function apply() {
  dirty.value = false
  dragging = false
  luaCall("stanceStudio_core.applyStance", plain())
}

function revert() {
  dirty.value = false
  for (const a of ["F", "R"]) for (const k of KEYS) edit[a][k] = applied[a][k]
  luaCall("stanceStudio_core.clearPreview")
}

function resetAll() {
  for (const a of ["F", "R"]) Object.assign(edit[a], neutral())
  apply()
}

function grab() {
  dragging = true
  if (s.value.autoFocus) focusAxle()
}
function focusAxle() { luaCall("stanceStudio_core.focus", axle.value) }
function pickAxle(a) {
  axle.value = a
  if (s.value.autoFocus) focusAxle()
}
function toggleLink() {
  link.value = !link.value
  saveSettings({ linkAxles: link.value })
}
function onPointerUp() { dragging = false }

// MARK: presets (meters / degrees / multipliers)
const presets = [
  { id: "stock", label: "Stock", F: {}, R: {} },
  { id: "flush", label: "Flush", F: { rideHeight: -0.03, camber: -1.5, offset: 0.015 }, R: { rideHeight: -0.03, camber: -1.5, offset: 0.015 } },
  { id: "track", label: "Track", F: { rideHeight: -0.025, camber: -2.5, spring: 1.35, damp: 1.25 }, R: { rideHeight: -0.02, camber: -1.5, toe: 0.1, spring: 1.3, damp: 1.2 } },
  { id: "slammed", label: "Slammed", F: { rideHeight: -0.07, camber: -3.5, offset: 0.02, spring: 1.2 }, R: { rideHeight: -0.07, camber: -4, offset: 0.025, spring: 1.2 } },
  { id: "hellaflush", label: "Hellaflush", F: { rideHeight: -0.06, camber: -8, offset: 0.03 }, R: { rideHeight: -0.06, camber: -9, offset: 0.04 } },
  { id: "scrape", label: "Scraping", F: { rideHeight: -0.16, camber: -6, offset: 0.04 }, R: { rideHeight: -0.16, camber: -7, offset: 0.05 } },
  { id: "drift", label: "Drift lock", F: { rideHeight: -0.04, camber: -4.5, toe: -0.1, steer: 2.4, spring: 1.3, damp: 1.2 }, R: { rideHeight: -0.035, camber: -1, toe: 0.15, spring: 1.25, damp: 1.15 } },
  { id: "lifted", label: "Lifted", F: { rideHeight: 0.07, offset: 0.02, spring: 0.95, damp: 1.1 }, R: { rideHeight: 0.07, offset: 0.02, spring: 0.95, damp: 1.1 } },
]
function applyPreset(p) {
  for (const a of ["F", "R"]) Object.assign(edit[a], neutral(), p[a])
  if (s.value.applyMode === "button") {
    dirty.value = true
    preview()
  } else {
    apply()
  }
}

// MARK: status texts
const methodText = computed(() => {
  const corners = list(report.value?.corners).filter(c => c.axle === axle.value)
  if (!corners.length) return "Universal stance: works on any car"
  if (corners.some(c => c.method === "springs+hub")) return "Ride height: springs + drop hub"
  if (corners.some(c => c.method === "springs")) return "Ride height: springs"
  if (corners.some(c => c.method === "hub")) return "Ride height: drop hub"
  return "Universal stance"
})
const measuredText = computed(() => {
  const v = store.state?.actual?.[axle.value]
  if (v === undefined || v === null) return ""
  const d = units.toDisplay(v, s.value)
  const dec = imperial.value ? 2 : 0
  return `Measured ${d > 0 ? "+" : ""}${d.toFixed(dec)} ${lenUnit.value} vs stock`
})

onMounted(() => window.addEventListener("pointerup", onPointerUp))
onUnmounted(() => {
  window.removeEventListener("pointerup", onPointerUp)
  luaCall("stanceStudio_core.clearPreview")
})
</script>

<style lang="scss" scoped>
.ss-axle-row { flex-wrap: nowrap; }
.ss-grow { flex: 1; }
.ss-status { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 0.9rem; min-height: 1.2rem; }
.ss-badge.warn { background: rgba(248, 113, 113, 0.2); color: #fca5a5; }
.ss-actions { display: flex; gap: 0.5rem; flex-wrap: wrap; margin-top: 0.4rem; }
</style>
