<template>
  <div class="ss-perf">
    <div v-if="loadingCats" class="ss-muted">Reading parts…</div>
    <template v-else>
      <div class="ss-cats">
        <button v-for="c in categories" :key="c.id" class="ss-chip" :class="{ active: cat === c.id }" @click="selectCat(c.id)">
          {{ c.title }} <span class="ss-count">{{ c.count }}</span>
        </button>
      </div>

      <div class="ss-power" v-if="carHp">
        <span class="ss-muted">Your car</span>
        <b>{{ Math.round(carHp) }} hp</b>
        <span class="ss-muted">{{ measured ? 'measured' : 'estimated' }}</span>
      </div>
      <input v-model="query" v-bng-text-input class="ss-input ss-search" placeholder="Search parts…" />
      <div class="ss-muted ss-explain">Best first. <b class="ss-up">+hp</b> / <b class="ss-down">−hp</b> is how much power you gain or lose compared to what's on your car now (estimated with the game's engine math).</div>

      <div v-if="loadingSlots" class="ss-muted">Ranking parts…</div>
      <div v-for="slot in visibleSlots" :key="slot.path" class="ss-slot">
        <div class="ss-slot-head">
          <div class="ss-slot-title">{{ slot.title }}</div>
          <div class="ss-slot-now">{{ chosenTitle(slot) }}</div>
        </div>
        <div class="ss-options">
          <button v-for="(o, i) in shownOptions(slot)" :key="o.name || '_empty'" class="ss-opt"
            :class="{ chosen: o.name === slot.chosen, empty: o.name === '' }" @click="pick(slot, o)">
            <span class="ss-rank">{{ o.name === '' ? '–' : i + 1 }}</span>
            <span class="ss-opt-title">{{ o.title }}</span>
            <span v-if="o.name === slot.chosen" class="ss-badge">On car</span>
            <span v-if="o.mod" class="ss-badge mod">{{ o.mod }}</span>
            <span v-if="o.badge" class="ss-badge" :class="o.kind === 'loss' ? 'bad' : 'good'">{{ o.badge }}</span>
          </button>
          <button v-if="slot.options.length > limit && !expanded[slot.path]" class="ss-more" @click="expanded[slot.path] = true">
            Show all {{ slot.options.length }}
          </button>
        </div>
      </div>
      <div v-if="!loadingSlots && !visibleSlots.length" class="ss-muted">Nothing here for this car.</div>
    </template>
  </div>
</template>

<script setup>
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, reactive, ref, watch, onMounted } from "vue"
import { luaCall, list } from "../api.js"
import { store } from "../store.js"

const limit = 8
const loadingCats = ref(true)
const loadingSlots = ref(false)
const categories = ref([])
const cat = ref(null)
const slots = ref([])
const estHp = ref(null)
const carHp = computed(() => store.state?.power || estHp.value)
const measured = computed(() => !!store.state?.power)
const query = ref("")
const expanded = reactive({})
let catSaved = null
try { catSaved = localStorage.getItem("stanceStudio.perfCat") } catch (e) { /* storage off */ }

async function loadCats() {
  const res = await luaCall("stanceStudio_parts.getCategories")
  categories.value = list(res?.categories)
  loadingCats.value = false
  const ids = categories.value.map(c => c.id)
  if (!cat.value || !ids.includes(cat.value)) {
    cat.value = ids.includes(catSaved) ? catSaved : (ids.includes("engine") ? "engine" : ids[0])
  }
  if (cat.value) loadSlots()
}

async function loadSlots() {
  loadingSlots.value = true
  const res = await luaCall("stanceStudio_parts.getCategories", cat.value)
  slots.value = list(list(res?.categories)[0]?.slots).map(sl => ({ ...sl, options: list(sl.options) }))
  if (res?.carHp) estHp.value = res.carHp
  loadingSlots.value = false
}

function selectCat(id) {
  cat.value = id
  try { localStorage.setItem("stanceStudio.perfCat", id) } catch (e) { /* storage off */ }
  slots.value = []
  loadSlots()
}

const visibleSlots = computed(() => {
  const q = query.value.trim().toLowerCase()
  if (!q) return slots.value
  return slots.value.filter(sl => sl.title.toLowerCase().includes(q) || sl.options.some(o => (o.title + " " + o.name).toLowerCase().includes(q)))
})

function shownOptions(slot) {
  const q = query.value.trim().toLowerCase()
  let list = slot.options
  if (q && !slot.title.toLowerCase().includes(q)) list = list.filter(o => o.name === "" || (o.title + " " + o.name).toLowerCase().includes(q))
  if (!expanded[slot.path] && list.length > limit + 1) {
    const top = list.slice(0, limit)
    const chosen = list.find(o => o.name === slot.chosen)
    if (chosen && !top.includes(chosen)) top.push(chosen)
    return top
  }
  return list
}

function chosenTitle(slot) {
  if (!slot.chosen) return "Empty"
  return slot.options.find(o => o.name === slot.chosen)?.title || slot.chosen
}

function pick(slot, o) {
  if (o.name === slot.chosen) return
  slot.chosen = o.name
  luaCall("stanceStudio_parts.setPart", slot.path, o.name)
}

// slots below a swapped part change, so reload after each respawn
watch(() => store.state?.spawnCount, () => { if (!loadingCats.value) loadCats() })
onMounted(loadCats)
</script>

<style lang="scss" scoped>
.ss-cats { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 0.7rem; }
.ss-count { opacity: 0.55; margin-left: 0.2rem; font-size: 0.72rem; }
.ss-search { margin-bottom: 0.4rem; }
.ss-power {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
  margin-bottom: 0.6rem;
  b { font-size: 1.25rem; }
}
.ss-explain { font-size: 0.75rem; margin-bottom: 0.8rem; }
.ss-slot {
  background: rgba(255, 255, 255, 0.035);
  border-radius: 0.6rem;
  padding: 0.6rem 0.6rem 0.4rem;
  margin-bottom: 0.6rem;
}
.ss-slot-head { display: flex; justify-content: space-between; gap: 0.5rem; margin-bottom: 0.4rem; align-items: baseline; }
.ss-slot-title { font-weight: 700; font-size: 0.92rem; }
.ss-slot-now { font-size: 0.78rem; opacity: 0.6; text-align: right; }
.ss-options { display: flex; flex-direction: column; gap: 0.15rem; }
.ss-opt {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  border: 1px solid transparent;
  background: transparent;
  color: #fff;
  border-radius: 0.4rem;
  padding: 0.38rem 0.45rem;
  cursor: pointer;
  text-align: left;
  font-size: 0.85rem;
  &:hover { background: rgba(255, 255, 255, 0.07); }
  &.chosen { border-color: var(--bng-orange, #ff6600); background: rgba(255, 102, 0, 0.1); }
  &.empty { opacity: 0.6; }
}
.ss-rank { width: 1.3rem; text-align: center; opacity: 0.5; font-variant-numeric: tabular-nums; font-size: 0.78rem; }
.ss-opt-title { flex: 1; }
.ss-more {
  border: 0;
  background: transparent;
  color: var(--bng-orange, #ff6600);
  cursor: pointer;
  padding: 0.35rem;
  font-size: 0.82rem;
  text-align: left;
}
.ss-up { color: #a7f3c0; }
.ss-down { color: #fca5a5; }
</style>
