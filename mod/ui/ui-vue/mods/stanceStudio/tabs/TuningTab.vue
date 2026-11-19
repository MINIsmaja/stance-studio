<template>
  <div class="ss-tuning">
    <div class="ss-muted ss-explain">This car's own tuning settings (the same ones as the base tuning menu). Changes apply when you let go.</div>
    <input v-model="query" v-bng-text-input class="ss-input ss-search" placeholder="Search settings…" />
    <div v-if="loading" class="ss-muted">Reading tuning…</div>
    <div v-else-if="!groups.length" class="ss-muted">This car has no tuning settings with its current parts.</div>
    <div v-for="g in groups" :key="g.name" class="ss-group">
      <button class="ss-group-head" @click="toggle(g.name)">
        <span>{{ g.name }}</span>
        <span class="ss-muted">{{ g.vars.length }} {{ open[g.name] ? '▾' : '▸' }}</span>
      </button>
      <div v-if="open[g.name] || query" class="ss-group-body">
        <template v-for="(v, i) in g.vars" :key="v.name">
          <div v-if="v.subCategory && (i === 0 || g.vars[i - 1].subCategory !== v.subCategory)" class="ss-sub">{{ v.subCategory }}</div>
          <SliderRow :label="v.title" :hint="v.description" :unit="v.unit || ''" :min="v.minDis" :max="v.maxDis" :step="v.stepDis"
            :decimals="decimalsFor(v)" :stock="toDis(v, v.default)" :signed="false" :value="toDis(v, v.val)"
            @input="d => (v.val = fromDis(v, d))" @commit="d => commit(v, d)" />
        </template>
      </div>
    </div>
  </div>
</template>

<script setup>
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, reactive, ref, watch, onMounted } from "vue"
import { luaCall, list } from "../api.js"
import { store } from "../store.js"
import SliderRow from "../components/SliderRow.vue"

const loading = ref(true)
const vars = ref([])
const query = ref("")
const open = reactive({})

async function load() {
  const res = await luaCall("stanceStudio_parts.getTuning")
  vars.value = list(res?.variables).map(v => ({
    ...v,
    minDis: v.minDis ?? v.min,
    maxDis: v.maxDis ?? v.max,
    stepDis: v.stepDis || Math.abs((v.maxDis ?? v.max) - (v.minDis ?? v.min)) / 100 || 0.01,
  }))
  loading.value = false
}

const groups = computed(() => {
  const q = query.value.trim().toLowerCase()
  const map = new Map()
  for (const v of vars.value) {
    if (q && !(v.title + " " + v.name + " " + v.category).toLowerCase().includes(q)) continue
    if (!map.has(v.category)) map.set(v.category, [])
    map.get(v.category).push(v)
  }
  return [...map.entries()].map(([name, list]) => ({ name, vars: list }))
})

function toDis(v, val) {
  const span = v.max - v.min
  if (!span) return v.minDis
  return v.minDis + ((val - v.min) / span) * (v.maxDis - v.minDis)
}
function fromDis(v, d) {
  const span = v.maxDis - v.minDis
  if (!span) return v.min
  return v.min + ((d - v.minDis) / span) * (v.max - v.min)
}
function decimalsFor(v) {
  const step = Math.abs(v.stepDis || 0.01)
  if (step >= 1) return 0
  return Math.min(4, Math.ceil(-Math.log10(step)))
}
function commit(v, d) {
  v.val = fromDis(v, d)
  luaCall("stanceStudio_parts.setVars", { [v.name]: v.val })
}
function toggle(name) { open[name] = !open[name] }

watch(() => store.state?.spawnCount, load)
onMounted(load)
</script>

<style lang="scss" scoped>
.ss-explain { font-size: 0.78rem; margin-bottom: 0.6rem; }
.ss-search { margin-bottom: 0.8rem; }
.ss-group { margin-bottom: 0.5rem; }
.ss-group-head {
  width: 100%;
  display: flex;
  justify-content: space-between;
  border: 0;
  background: rgba(255, 255, 255, 0.06);
  color: #fff;
  padding: 0.6rem 0.75rem;
  border-radius: 0.5rem;
  cursor: pointer;
  font-weight: 700;
  font-size: 0.9rem;
}
.ss-group-body { padding-top: 0.45rem; }
.ss-sub { font-size: 0.72rem; letter-spacing: 0.1em; text-transform: uppercase; opacity: 0.5; margin: 0.5rem 0 0.3rem 0.2rem; }
</style>
