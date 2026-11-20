<template>
  <div class="fun-section">
    <!-- key/value sections (mainEngine, gearbox, turbocharger, ...) -->
    <template v-if="sec.kind === 'settings'">
      <template v-for="f in shownFields" :key="f.id || pathKey(f.path)">
        <FunSlider v-if="f.kind === 'value' && f.type === 'number'" :label="label(f.path)" :title="pathKey(f.path)"
          :value="api.valueOf(f)" :stock="f.stock" @change="v => api.setValue(f, v)" />

        <label v-else-if="f.kind === 'value' && f.type === 'boolean'" class="fun-row" :class="{ changed: api.valueOf(f) !== f.stock }">
          <span class="fun-row-label" :title="pathKey(f.path)">{{ label(f.path) }}</span>
          <input type="checkbox" :checked="api.valueOf(f)" @change="e => api.setValue(f, e.target.checked)" />
        </label>

        <div v-else-if="f.kind === 'value' && f.type === 'string'" class="fun-row" :class="{ changed: api.valueOf(f) !== f.stock }">
          <span class="fun-row-label" :title="pathKey(f.path)">{{ label(f.path) }}</span>
          <input v-bng-text-input class="fun-text" :value="api.valueOf(f)" @keydown.enter="$event.target.blur()" @change="e => api.setValue(f, e.target.value)" />
        </div>

        <div v-else-if="f.kind === 'list'" class="fun-block">
          <div class="fun-block-title">{{ label(f.path) }} <span class="ss-muted">{{ list(f.values).length }} values</span></div>
          <FunSlider v-for="(v, i) in list(f.values)" :key="v.id" :label="`${lastKey(f.path)} [${i + 1}]`"
            :value="api.valueOf(v)" :stock="v.stock" @change="x => api.setValue(v, x)" />
        </div>

        <div v-else-if="f.kind === 'column'" class="fun-block">
          <div class="fun-block-title">{{ label(f.path) }} <span class="ss-muted">curve, {{ list(f.rows).length }} points</span></div>
          <FunSlider v-for="c in list(f.columns)" :key="c.id" mode="scale" :label="`all ${c.name} ×`"
            :sub="`stock ${fmtRange(c.stockMin, c.stockMax)}`" :value="api.scaleOf(c)" :stock="1"
            @change="k => api.setColumn(f, c, k)" />
          <button class="fun-more" @click="points[pathKey(f.path)] = !points[pathKey(f.path)]">
            {{ points[pathKey(f.path)] ? "Hide points ▴" : "Edit single points ▾" }}
          </button>
          <template v-if="points[pathKey(f.path)]">
            <template v-for="r in list(f.rows)" :key="r.index">
              <template v-for="cell in list(r.cells)" :key="cell.column">
                <FunSlider v-if="cell.id" :label="pointLabel(f, r, cell)" :value="api.valueOf(cell)" :stock="cell.stock"
                  @change="x => api.setValue(cell, x)" />
              </template>
            </template>
          </template>
        </div>
      </template>
      <button v-if="fieldCount > limit" class="fun-more" @click="limit += 80">Show more ({{ fieldCount - limit }} left)</button>
    </template>

    <!-- row sections (nodes, beams, wheels, hydros, ...) -->
    <template v-else>
      <div class="ss-muted fun-note">{{ sec.count }} rows. Each slider changes that value on every row.</div>
      <FunSlider v-for="f in list(sec.fields)" :key="f.id" mode="scale" :label="`${f.field} ×`" :title="`${sec.name} › ${f.field}`"
        :sub="rowsSub(f)" :value="api.scaleOf(f)" :stock="1" @change="k => api.setRows(sec, f, k)" />
      <template v-if="list(sec.rows).length">
        <button class="fun-more" @click="perRow = !perRow">{{ perRow ? "Hide single rows ▴" : `Edit single rows (${list(sec.rows).length}) ▾` }}</button>
        <template v-if="perRow">
          <div v-for="r in list(sec.rows)" :key="r.row" class="fun-block">
            <div class="fun-block-title">{{ r.row }}</div>
            <FunSlider v-for="v in list(r.values)" :key="v.id" :label="v.field" :value="api.valueOf(v)" :stock="v.stock"
              @change="x => api.setRow(sec, r, v, x)" />
          </div>
        </template>
      </template>
    </template>
  </div>
</template>

<script setup>
import { vBngTextInput } from "@/common/directives" // turns on CEF typing while a text box has focus
import { computed, reactive, ref } from "vue"
import { list } from "../api.js"
import FunSlider from "./FunSlider.vue"

const props = defineProps({
  sec: { type: Object, required: true },
  api: { type: Object, required: true },
})

const limit = ref(80)
const perRow = ref(false)
const points = reactive({})

const fields = computed(() => list(props.sec.fields))
const fieldCount = computed(() => fields.value.length)
const shownFields = computed(() => fields.value.slice(0, limit.value))

const pathKey = p => list(p).join(" › ")
const lastKey = p => { const l = list(p); return String(l[l.length - 1]) }
// the path without the section name: "particulates › rate"
const label = p => { const l = list(p); return (l.length > 1 ? l.slice(1) : l).join(" › ") }

function num(v) {
  if (v === "FLT_MAX") return "∞"
  if (v === "-FLT_MAX") return "−∞"
  const n = Number(v)
  if (!isFinite(n)) return String(v)
  const a = Math.abs(n)
  return a !== 0 && (a < 0.001 || a >= 1e12) ? n.toExponential(2) : n.toLocaleString("en-US", { maximumSignificantDigits: 5 })
}
function fmtRange(lo, hi) {
  if (lo === undefined || lo === null) return "default"
  return lo === hi ? num(lo) : `${num(lo)} – ${num(hi)}`
}
function rowsSub(f) {
  if (f.defaultOnly) return "game default on every row"
  const of = f.count < props.sec.count ? ` (${f.count} of ${props.sec.count} rows)` : ""
  return `stock ${fmtRange(f.stockMin, f.stockMax)}${of}`
}
function pointLabel(f, r, cell) {
  const cells = list(r.cells)
  const first = cells[0]
  const header = list(list(f.header))
  const name = header[cell.column - 1] ?? `col ${cell.column}`
  const at = first && first !== cell && first.value !== undefined ? ` @ ${num(first.value)}` : ` #${r.index - 1}`
  return `${name}${at}`
}
</script>

<style lang="scss" scoped>
.fun-section { padding: 0.2rem 0 0.3rem; }
.fun-note { font-size: 0.76rem; margin: 0 0 0.45rem 0.1rem; }
.fun-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  padding: 0.45rem 0.6rem;
  border-radius: 0.5rem;
  background: rgba(255, 255, 255, 0.035);
  margin-bottom: 0.35rem;
  cursor: pointer;
  &.changed { background: rgba(255, 102, 0, 0.08); }
}
.fun-row-label { font-weight: 600; font-size: 0.85rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.fun-text {
  width: 11rem;
  border: 1px solid transparent;
  background: rgba(0, 0, 0, 0.25);
  color: #fff;
  border-radius: 0.3rem;
  padding: 0.2rem 0.4rem;
  font-size: 0.85rem;
  outline: none;
  &:focus { border-color: var(--bng-orange, #ff6600); }
}
.fun-block { margin: 0.3rem 0 0.55rem; padding-left: 0.4rem; border-left: 2px solid rgba(255, 255, 255, 0.08); }
.fun-block-title { font-size: 0.8rem; font-weight: 700; margin: 0.2rem 0 0.35rem 0.15rem; }
.fun-more {
  border: 0;
  background: transparent;
  color: var(--bng-orange, #ff6600);
  font-size: 0.8rem;
  font-weight: 600;
  cursor: pointer;
  padding: 0.2rem 0.15rem 0.45rem;
}
</style>
