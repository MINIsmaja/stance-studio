<template>
  <div class="fun-adv">
    <div class="ss-muted fun-adv-note">
      Every JBeam value of this car, by section. The middle of a slider is stock, the ends are ×0.01 and ×1000,
      and the box takes any number, <b>inf</b>, or <b>x10</b>.
    </div>
    <input v-model="query" v-bng-text-input class="ss-input fun-search" placeholder="Search values (maxRPM, brakeTorque, torque…)" />

    <div v-if="loading" class="ss-muted">Reading this car's JBeam…</div>

    <template v-else-if="query.trim()">
      <div v-if="searching" class="ss-muted">Searching…</div>
      <div v-else-if="!results.length" class="ss-muted">Nothing matches "{{ query }}".</div>
      <div v-for="r in results" :key="r.name" class="fun-group">
        <div class="fun-result-head">{{ r.name }} <span class="ss-muted">{{ r.group }}</span></div>
        <FunSection :sec="r" :api="api" />
      </div>
    </template>

    <template v-else>
      <template v-for="g in groups" :key="g.name">
        <div class="fun-sub">{{ g.name }}</div>
        <div v-for="s in g.sections" :key="s.name" class="fun-group">
          <button class="fun-group-head" @click="toggle(s.name)">
            <span>{{ s.name }}</span>
            <span class="fun-head-right">
              <span v-if="changedIn(s.name)" class="ss-badge accent">{{ changedIn(s.name) }} changed</span>
              <span class="ss-muted">{{ s.kind === "rows" ? `${s.count} rows` : `${s.fields} values` }} {{ open[s.name] ? "▾" : "▸" }}</span>
            </span>
          </button>
          <div v-if="open[s.name]" class="fun-group-body">
            <div v-if="!details[s.name]" class="ss-muted">Loading…</div>
            <FunSection v-else :sec="details[s.name]" :api="api" />
          </div>
        </div>
      </template>
    </template>
  </div>
</template>

<script setup>
// The full JBeam editor (every section, every value), shown under "Advanced" in the Fun tab.
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, reactive, ref, watch, onMounted } from "vue"
import { luaCall, list } from "../api.js"
import FunSection from "./FunSection.vue"

const props = defineProps({
  api: { type: Object, required: true },
  pending: { type: Object, default: () => ({}) },
  reloadKey: { type: Number, default: 0 }, // bumps after every respawn
})

const loading = ref(true)
const sections = ref([])
const details = reactive({})
const open = reactive({})
const query = ref("")
const results = ref([])
const searching = ref(false)

async function load() {
  const res = await luaCall("stanceStudio_core.funGetSections")
  sections.value = list(res?.sections)
  for (const k of Object.keys(details)) delete details[k]
  loading.value = false
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

// changes in a section, from the ids: "v|mainEngine|...", "r|beams|...", "w|pressureWheels|..."
function changedIn(name) {
  let n = 0
  for (const id of Object.keys(props.pending)) if (id.split("|")[1] === name && id[0] !== "q") n++
  return n
}

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
watch(() => props.reloadKey, load)
onMounted(load)
</script>

<style lang="scss" scoped>
.fun-adv-note { font-size: 0.76rem; margin-bottom: 0.5rem; line-height: 1.35; }
.fun-search { margin-bottom: 0.6rem; }
.fun-group { margin-bottom: 0.45rem; }
.fun-group-head {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border: 0;
  background: rgba(255, 255, 255, 0.06);
  color: #fff;
  padding: 0.5rem 0.7rem;
  border-radius: 0.5rem;
  cursor: pointer;
  font-weight: 700;
  font-size: 0.85rem;
}
.fun-head-right { display: flex; align-items: center; gap: 0.45rem; font-weight: 400; }
.fun-group-body { padding-top: 0.45rem; }
.fun-sub { font-size: 0.7rem; letter-spacing: 0.1em; text-transform: uppercase; opacity: 0.5; margin: 0.6rem 0 0.3rem 0.2rem; }
.fun-result-head { font-weight: 700; font-size: 0.85rem; margin: 0.4rem 0 0.3rem 0.1rem; }
</style>
