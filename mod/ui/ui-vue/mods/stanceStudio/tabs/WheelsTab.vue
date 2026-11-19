<template>
  <div class="ss-wheels">
    <div v-if="loading" class="ss-muted">Reading wheels…</div>
    <div v-else-if="!axles.length" class="ss-muted">This vehicle has no swappable wheels.</div>
    <template v-else>
      <div class="ss-section">
        <div class="ss-row">
          <div class="ss-seg ss-grow">
            <button v-if="hasSplit" :class="{ active: target === 'both' }" @click="target = 'both'">Both axles</button>
            <button v-if="byAxle.F" :class="{ active: target === 'F' }" @click="target = 'F'">Front</button>
            <button v-if="byAxle.R" :class="{ active: target === 'R' }" @click="target = 'R'">Rear</button>
            <button v-if="byAxle.B" :class="{ active: target === 'B' }" @click="target = 'B'">All wheels</button>
          </div>
        </div>
      </div>

      <div v-if="photos.running" class="ss-photo-bar">
        <div class="ss-row ss-between">
          <span>📷 Photographing rims on a copy of your car behind you… {{ photos.index }} / {{ photos.total }}</span>
          <button class="ss-btn ss-small" @click="cancelPhotos">Stop</button>
        </div>
        <div class="ss-progress"><div :style="{ width: photoPct + '%' }"></div></div>
      </div>
      <div v-else-if="missingPhotos > 0 && s.photoPass !== 'off'" class="ss-photo-bar">
        <div class="ss-row ss-between">
          <span>📷 {{ missingPhotos }} rims have no photo yet (about {{ Math.ceil(missingPhotos * 1.2) }} s).</span>
          <button class="ss-btn ss-small ss-primary" @click="takePhotos">Take photos</button>
        </div>
        <div class="ss-muted">A temporary copy of your car parks behind you and tries each rim once. You can keep browsing and fitting wheels meanwhile.</div>
      </div>

      <div class="ss-section">
        <input v-model="query" v-bng-text-input class="ss-input" placeholder="Search wheels (name, brand, mod)…" />
        <div class="ss-row ss-sizes">
          <button class="ss-chip" :class="{ active: size === null }" @click="size = null">All sizes</button>
          <button v-for="d in sizes" :key="d" class="ss-chip" :class="{ active: size === d }" @click="size = d">{{ d }}″</button>
        </div>
      </div>

      <div class="ss-grid">
        <button v-for="o in filtered" :key="o.name" class="ss-card" :class="{ chosen: o.name === chosenName, busy: pendingName === o.name }"
          :title="o.name" @click="pick(o)">
          <div class="ss-photo">
            <img v-if="o.photo" :src="photoUrl(o)" alt="" />
            <svg v-else viewBox="0 0 100 100" class="ss-rim-icon">
              <circle cx="50" cy="50" r="44" class="t" />
              <circle cx="50" cy="50" r="30" class="r" />
              <g class="s"><line v-for="i in 5" :key="i" x1="50" y1="50" :x2="50 + 28 * Math.cos(i * 1.2566)" :y2="50 + 28 * Math.sin(i * 1.2566)" /></g>
              <circle cx="50" cy="50" r="7" class="h" />
            </svg>
            <span v-if="!o.photo && !o.noPhoto && photos.running" class="ss-soon">photo coming…</span>
            <span v-if="o.diameter" class="ss-size">{{ o.diameter }}″{{ o.width ? ' × ' + o.width : '' }}</span>
          </div>
          <div class="ss-card-title">{{ o.title }}</div>
          <div class="ss-card-meta">
            <span v-if="o.mod" class="ss-badge mod">{{ o.mod }}</span>
            <span v-if="o.name === chosenName" class="ss-badge accent">On car</span>
          </div>
        </button>
      </div>
      <div v-if="!filtered.length" class="ss-muted">No wheels match.</div>

      <div v-for="a in tireAxles" :key="a.axle" class="ss-section ss-tires">
        <div class="ss-section-title">Tires · {{ axleName(a.axle) }}</div>
        <select class="ss-select" :value="a.tires.chosen" @change="e => setTire(a, e.target.value)">
          <option v-for="t in a.tires.options" :key="t.name" :value="t.name">{{ t.title }}{{ t.mod ? ' · ' + t.mod : '' }}</option>
          <option value="">No tire</option>
        </select>
      </div>
    </template>
  </div>
</template>

<script setup>
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, ref, watch, onMounted } from "vue"
import { luaCall, list } from "../api.js"
import { store, notify } from "../store.js"

const s = computed(() => store.state?.settings || {})
const photos = computed(() => store.photos || {})
const loading = ref(true)
const axles = ref([])
const target = ref("both")
const query = ref("")
const size = ref(null)
const pendingName = ref(null)
const autoStarted = new Set()

const byAxle = computed(() => Object.fromEntries(axles.value.map(a => [a.axle, a])))
const hasSplit = computed(() => !!(byAxle.value.F && byAxle.value.R))
const listAxle = computed(() => {
  if (target.value === "both") return byAxle.value.F || byAxle.value.B || axles.value[0]
  return byAxle.value[target.value] || axles.value[0]
})
const chosenName = computed(() => listAxle.value?.chosen)
const options = computed(() => listAxle.value?.options || [])
const sizes = computed(() => [...new Set(options.value.map(o => o.diameter).filter(Boolean))].sort((a, b) => b - a))
const filtered = computed(() => {
  const q = query.value.trim().toLowerCase()
  return options.value.filter(o => {
    if (size.value !== null && o.diameter !== size.value) return false
    if (!q) return true
    return (o.title + " " + o.name + " " + (o.mod || "")).toLowerCase().includes(q)
  })
})
const missingPhotos = computed(() => {
  const missing = new Set()
  for (const a of axles.value) for (const o of a.options) if (!o.photo && !o.noPhoto) missing.add(twinOf(o.name) || o.name)
  return missing.size
})
const photoPct = computed(() => (photos.value.total ? (photos.value.index / photos.value.total) * 100 : 0))
const tireAxles = computed(() => axles.value.filter(a => a.tires && a.tires.options.length))

// rear wheel parts share the photo of their front twin (same rim, other axle)
const TWINS = [[/_R$/, "_F"], [/_r$/, "_f"], [/_R_/, "_F_"], [/_rear/, "_front"], [/_Rear/, "_Front"]]
const frontNames = computed(() => new Set((byAxle.value.F?.options || []).map(o => o.name)))
function twinOf(name) {
  for (const [re, to] of TWINS) {
    const n = name.replace(re, to)
    if (n !== name && frontNames.value.has(n)) return n
  }
  return null
}
function twinsOf(name) {
  return TWINS.map(([re, to]) => name.replace(re, to)).filter(n => n !== name)
}

function axleName(a) { return a === "F" ? "front" : a === "R" ? "rear" : "all" }
function photoUrl(o) { return o.photo + "?v=" + store.photoVersion }

async function load() {
  const res = await luaCall("stanceStudio_parts.getWheels")
  axles.value = list(res?.axles).map(a => ({
    ...a,
    options: list(a.options),
    tires: a.tires ? { ...a.tires, options: list(a.tires.options) } : null,
  }))
  loading.value = false
  if (!hasSplit.value) target.value = byAxle.value.B ? "B" : (axles.value[0]?.axle || "F")
  const model = store.state?.vehicle?.model
  if ((s.value.photoPass || "auto") === "auto" && missingPhotos.value > 0 && !photos.value.running && model && !autoStarted.has(model)) {
    autoStarted.add(model)
    takePhotos()
  }
}

async function pick(o) {
  pendingName.value = o.name
  const res = await luaCall("stanceStudio_parts.setWheel", target.value, o.name)
  if (res?.rearMissing) notify("No matching rear version of this wheel, only the front was changed", "warning", 5000)
  if (res && res.ok === false) notify("Could not fit that wheel", "error")
}

function setTire(a, name) {
  luaCall("stanceStudio_parts.setPart", a.tires.path, name)
}

async function takePhotos() {
  const res = await luaCall("stanceStudio_photos.start", true)
  if (res && res.ok === false && res.reason === "spawn") notify("Couldn't park the photo car behind you. Try a spot with more room.", "warning", 6000)
  else if (res && res.ok === false && res.reason !== "running") notify("Could not start the photo pass", "error")
}
function cancelPhotos() { luaCall("stanceStudio_photos.cancel") }

// reload after every respawn (wheel swaps) and when a photo lands
watch(() => store.state?.spawnCount, () => { pendingName.value = null; load() })
watch(() => photos.value.done, d => { if (d) load() })
watch(() => store.photoVersion, () => {
  const p = photos.value.photo
  if (!p) return
  for (const a of axles.value) for (const o of a.options) {
    if (o.name === p.name || (!o.photo && twinsOf(o.name).includes(p.name))) o.photo = p.path
  }
})

onMounted(load)
</script>

<style lang="scss" scoped>
.ss-grow { flex: 1; }
.ss-between { justify-content: space-between; flex-wrap: nowrap; }
.ss-sizes { margin-top: 0.5rem; }
.ss-photo-bar {
  background: rgba(255, 255, 255, 0.05);
  border-radius: 0.55rem;
  padding: 0.6rem 0.7rem;
  margin-bottom: 0.9rem;
  font-size: 0.88rem;
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
}
.ss-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.5rem;
}
.ss-card {
  border: 2px solid transparent;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 0.6rem;
  padding: 0.35rem 0.35rem 0.5rem;
  color: #fff;
  text-align: left;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  &:hover { background: rgba(255, 255, 255, 0.1); }
  &.chosen { border-color: var(--bng-orange, #ff6600); }
  &.busy { opacity: 0.6; }
}
.ss-photo {
  position: relative;
  aspect-ratio: 1;
  border-radius: 0.4rem;
  overflow: hidden;
  background: radial-gradient(circle at 50% 45%, #2a2e36, #1a1c21);
  isolation: isolate; // the photo only blends with this tile
  display: flex;
  align-items: center;
  justify-content: center;
  // rim photos are shot on pure black, "screen" turns that black into the tile color
  img { width: 100%; height: 100%; object-fit: contain; mix-blend-mode: screen; transition: transform 0.2s ease; }
}
.ss-card:hover .ss-photo img { transform: scale(1.05); }
.ss-rim-icon {
  width: 62%;
  .t { fill: #0d0e10; stroke: #3a3f47; stroke-width: 3; }
  .r { fill: none; stroke: #9aa3ad; stroke-width: 3; }
  .s line { stroke: #9aa3ad; stroke-width: 4; stroke-linecap: round; }
  .h { fill: #9aa3ad; }
}
.ss-soon {
  position: absolute;
  top: 0.3rem;
  right: 0.3rem;
  font-size: 0.66rem;
  padding: 0.1rem 0.35rem;
  border-radius: 0.25rem;
  background: rgba(0, 0, 0, 0.55);
  opacity: 0.85;
}
.ss-size {
  position: absolute;
  left: 0.3rem;
  bottom: 0.3rem;
  font-size: 0.72rem;
  font-weight: 700;
  padding: 0.1rem 0.35rem;
  border-radius: 0.25rem;
  background: rgba(0, 0, 0, 0.65);
}
.ss-card-title {
  font-size: 0.78rem;
  line-height: 1.25;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  min-height: 2em;
}
.ss-card-meta { display: flex; flex-wrap: wrap; gap: 0.2rem; }
.ss-tires { margin-top: 1rem; }
</style>
