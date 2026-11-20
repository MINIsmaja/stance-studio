<template>
  <div class="ss-fun">
    <div class="ss-muted ss-explain">
      Every JBeam value of this car, with a slider. No game files are touched: changes are saved with this car's
      config (saved .pc files keep them too). The middle of a slider is stock, the ends are ×0.01 and ×1000, and the
      box takes any number, <b>inf</b>, or <b>x10</b>. Big changes can make a car explode. Reset everything puts it back.
    </div>

    <div class="fun-top">
      <div><span class="ss-muted">Engine now</span> <b>{{ hpText }}</b></div>
      <button class="ss-btn ss-small" :disabled="!appliedCount || busy" @click="askReset = !askReset">Reset everything</button>
    </div>
    <div v-if="askReset" class="fun-confirm">
      <span>Put all {{ appliedCount }} JBeam change{{ appliedCount === 1 ? "" : "s" }} back to stock?</span>
      <span class="ss-row">
        <button class="ss-btn ss-small ss-primary" @click="resetAll">Reset</button>
        <button class="ss-btn ss-small" @click="askReset = false">Cancel</button>
      </span>
    </div>
    <div v-if="missed.length" class="fun-warn">
      <span>{{ missed.length }} change{{ missed.length === 1 ? " does" : "s do" }} not match this car's current parts.</span>
      <button class="ss-btn ss-small" @click="dropMissed">Remove {{ missed.length === 1 ? "it" : "them" }}</button>
    </div>
    <div v-if="loadError" class="fun-warn"><span>Some changes could not be applied: {{ loadError }}</span></div>

    <input v-model="query" v-bng-text-input class="ss-input fun-search" placeholder="Search values (maxRPM, brakeTorque, torque…)" />

    <div v-if="loading" class="ss-muted">Reading this car's JBeam…</div>

    <!-- search results -->
    <template v-else-if="query.trim()">
      <div v-if="searching" class="ss-muted">Searching…</div>
      <div v-else-if="!results.length" class="ss-muted">Nothing matches "{{ query }}".</div>
      <div v-for="r in results" :key="r.name" class="ss-group">
        <div class="fun-result-head">{{ r.name }} <span class="ss-muted">{{ r.group }}</span></div>
        <FunSection :sec="r" :api="api" />
      </div>
    </template>

    <!-- all sections, by group -->
    <template v-else>
      <template v-for="g in groups" :key="g.name">
        <div class="ss-sub">{{ g.name }}</div>
        <div v-for="s in g.sections" :key="s.name" class="ss-group">
          <button class="ss-group-head" @click="toggle(s.name)">
            <span>{{ s.name }}</span>
            <span class="fun-head-right">
              <span v-if="changedIn(s.name)" class="ss-badge accent">{{ changedIn(s.name) }} changed</span>
              <span class="ss-muted">{{ s.kind === "rows" ? `${s.count} rows` : `${s.fields} values` }} {{ open[s.name] ? "▾" : "▸" }}</span>
            </span>
          </button>
          <div v-if="open[s.name]" class="ss-group-body">
            <div v-if="!details[s.name]" class="ss-muted">Loading…</div>
            <FunSection v-else :sec="details[s.name]" :api="api" />
          </div>
        </div>
      </template>
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
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, reactive, ref, watch, onMounted } from "vue"
import { luaCall, list } from "../api.js"
import { store, notify } from "../store.js"
import FunSection from "../components/FunSection.vue"

const loading = ref(true)
const busy = ref(false)
const askReset = ref(false)
const sections = ref([])
const details = reactive({})
const open = reactive({})
const applied = ref({})  // edits on the car right now (id -> edit)
const pending = ref({})  // edits with your unapplied changes
const missed = ref([])
const loadError = ref(null)
const power = ref(null)
const query = ref("")
const results = ref([])
const searching = ref(false)

const clone = x => JSON.parse(JSON.stringify(x || {}))
const isInf = x => x === "FLT_MAX" || x === "-FLT_MAX"
function same(a, b) {
  if (typeof a === "number" && typeof b === "number") return Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(b))
  return a === b
}

async function load() {
  const res = await luaCall("stanceStudio_core.funGetSections")
  sections.value = list(res?.sections)
  applied.value = res?.edits && typeof res.edits === "object" && !Array.isArray(res.edits) ? res.edits : {}
  pending.value = clone(applied.value)
  missed.value = list(res?.missed)
  loadError.value = res?.error || null
  power.value = res?.power ?? null
  for (const k of Object.keys(details)) delete details[k]
  loading.value = false
  // reload the sections that are open
  for (const name of Object.keys(open)) if (open[name]) loadSection(name)
  if (query.value.trim()) runSearch()
}

async function loadSection(name) {
  const d = await luaCall("stanceStudio_core.funGetSection", name)
  if (d) details[name] = d
}

function toggle(name) {
  open[name] = !open[name]
  if (open[name] && !details[name]) loadSection(name)
}

const groups = computed(() => {
  const out = []
  for (const s of sections.value) {
    let g = out.find(x => x.name === s.group)
    if (!g) { g = { name: s.group, sections: [] }; out.push(g) }
    g.sections.push(s)
  }
  return out
})

// MARK: pending edits (the api the sliders use)
function put(id, edit) { pending.value = { ...pending.value, [id]: edit } }
function drop(id) { const p = { ...pending.value }; delete p[id]; pending.value = p }

const api = {
  valueOf(f) {
    const e = pending.value[f.id]
    return e && e.value !== undefined ? e.value : f.stock
  },
  scaleOf(f) {
    const e = pending.value[f.id]
    return e && e.scale !== undefined ? e.scale : 1
  },
  setValue(f, v) {
    if (same(v, f.stock)) drop(f.id)
    else put(f.id, { kind: "value", path: list(f.path), value: v })
  },
  setColumn(f, c, k) {
    if (isInf(k) || !(Number(k) >= 0)) return
    if (same(Number(k), 1)) drop(c.id)
    else put(c.id, { kind: "column", path: list(f.path), column: c.column, scale: Number(k) })
  },
  setRows(sec, f, k) {
    if (isInf(k) || !(Number(k) >= 0)) return
    if (same(Number(k), 1)) drop(f.id)
    else put(f.id, { kind: "rows", section: sec.name, field: f.field, scale: Number(k) })
  },
  setRow(sec, r, v, x) {
    if (same(x, v.stock)) drop(v.id)
    else put(v.id, { kind: "row", section: sec.name, row: r.row, field: v.field, value: x })
  },
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

// changes in a section (applied or pending), from the ids: "v|mainEngine|...", "r|beams|...", "w|pressureWheels|..."
function changedIn(name) {
  let n = 0
  for (const id of Object.keys(pending.value)) {
    const parts = id.split("|")
    if (parts[1] === name) n++
  }
  return n
}

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

// MARK: search
let searchTimer = null
async function runSearch() {
  const q = query.value.trim()
  if (!q) { results.value = []; return }
  searching.value = true
  const res = await luaCall("stanceStudio_core.funSearch", q)
  if (query.value.trim() === q) {
    results.value = list(res)
    searching.value = false
  }
}
watch(query, () => {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(runSearch, 300)
})

// MARK: power and respawns
const hpText = computed(() => {
  const hp = store.state?.power ?? power.value
  if (!hp) return busy.value ? "…" : "no engine"
  return `${Math.round(hp).toLocaleString("en-US")} hp`
})

watch(() => store.state?.spawnCount, async () => {
  const wasBusy = busy.value
  await load()
  if (wasBusy) {
    busy.value = false
    const n = appliedCount.value
    notify(n ? `Respawned with ${n} JBeam change${n === 1 ? "" : "s"}` : "Back to the stock JBeam", "info", 3500)
  }
})

onMounted(load)
</script>

<style lang="scss" scoped>
.ss-explain { font-size: 0.78rem; margin-bottom: 0.6rem; line-height: 1.35; }
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
.fun-search { margin-bottom: 0.7rem; }
.ss-group { margin-bottom: 0.45rem; }
.ss-group-head {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border: 0;
  background: rgba(255, 255, 255, 0.06);
  color: #fff;
  padding: 0.55rem 0.75rem;
  border-radius: 0.5rem;
  cursor: pointer;
  font-weight: 700;
  font-size: 0.88rem;
}
.fun-head-right { display: flex; align-items: center; gap: 0.45rem; font-weight: 400; }
.ss-group-body { padding-top: 0.45rem; }
.ss-sub { font-size: 0.72rem; letter-spacing: 0.1em; text-transform: uppercase; opacity: 0.5; margin: 0.7rem 0 0.35rem 0.2rem; }
.fun-result-head { font-weight: 700; font-size: 0.88rem; margin: 0.4rem 0 0.3rem 0.1rem; }
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
