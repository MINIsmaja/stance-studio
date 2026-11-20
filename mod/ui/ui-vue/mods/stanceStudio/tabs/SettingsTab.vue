<template>
  <div class="ss-settings">
    <div class="ss-section">
      <div class="ss-section-title">Open key</div>
      <div class="ss-key-row">
        <div class="ss-keycap" :class="{ capturing: listening || captured }">{{ keycapText }}</div>
        <template v-if="listening">
          <button class="ss-btn" @click="cancelKey">Cancel</button>
        </template>
        <template v-else-if="captured">
          <button class="ss-btn ss-primary" :disabled="saving" @click="saveKey">Save</button>
          <button class="ss-btn" @click="startCapture">Try again</button>
          <button class="ss-btn" @click="cancelKey">Cancel</button>
        </template>
        <template v-else>
          <button class="ss-btn ss-primary" @click="startCapture">Change key</button>
          <button class="ss-btn" :disabled="!current" @click="removeKey">Remove</button>
        </template>
      </div>
      <div v-if="captured && conflicts.length" class="ss-warn">Already used by: {{ conflicts.join(', ') }}. Both will trigger.</div>
      <div class="ss-muted ss-note">Also listed as "Stance Studio: open / close" under Options › Controls › Bindings.</div>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Applying changes</div>
      <div class="ss-seg">
        <button :class="{ active: s.applyMode === 'release' }" @click="set({ applyMode: 'release' })">When I let go of a slider</button>
        <button :class="{ active: s.applyMode === 'button' }" @click="set({ applyMode: 'button' })">With an Apply button</button>
      </div>
      <div class="ss-muted ss-note">Applying respawns the car in place for a moment, like the base tuning menu.</div>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Units</div>
      <div class="ss-seg">
        <button :class="{ active: s.units !== 'imperial' }" @click="set({ units: 'metric' })">Millimeters</button>
        <button :class="{ active: s.units === 'imperial' }" @click="set({ units: 'imperial' })">Inches</button>
      </div>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Slider range</div>
      <div class="ss-seg">
        <button :class="{ active: s.range !== 'extreme' }" @click="set({ range: 'normal' })">Normal</button>
        <button :class="{ active: s.range === 'extreme' }" @click="set({ range: 'extreme' })">Extreme</button>
      </div>
      <div class="ss-muted ss-note">Normal ride height is ±400 mm on pickups and heavy vehicles (4 t and up: box trucks, semis, buses) and −250 to +200 mm on everything else, SUVs and vans included. Extreme allows up to −30° camber, ±50 cm ride height and 35 cm wider per side.</div>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Ride height method</div>
      <div class="ss-seg">
        <button :class="{ active: !s.method || s.method === 'auto' }" @click="setMethod('auto')">Auto (slam-ready)</button>
        <button :class="{ active: s.method === 'springs' }" @click="setMethod('springs')">Springs only</button>
        <button :class="{ active: s.method === 'hub' }" @click="setMethod('hub')">Drop hub only</button>
      </div>
      <div class="ss-muted ss-note">Auto lowers the first 5 cm on the springs like coilovers, then moves the wheels up on the hubs for anything lower, so the car can sit on the ground and still has its suspension travel. Lifting works the same way: the first 10 cm on the springs, anything higher drops the wheels on the hubs. Springs only stops where the bump stops are. Drop hub only never touches the springs.</div>
      <label class="ss-toggle">
        <input type="checkbox" :checked="s.autoCorrect" @change="e => set({ autoCorrect: e.target.checked })" />
        <span>Auto-correct ride height (one extra respawn when the measured height misses the target)</span>
      </label>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Preview & camera</div>
      <label class="ss-toggle">
        <input type="checkbox" :checked="s.preview" @change="e => set({ preview: e.target.checked })" />
        <span>Show a ghost tire where the wheel will end up while dragging</span>
      </label>
      <div class="ss-row ss-colors">
        <span class="ss-muted">Ghost color</span>
        <button v-for="c in colors" :key="c" class="ss-swatch" :class="{ active: s.previewColor === c }" :style="{ background: c }" @click="set({ previewColor: c })"></button>
      </div>
      <label class="ss-toggle">
        <input type="checkbox" :checked="s.autoFocus" @change="e => set({ autoFocus: e.target.checked })" />
        <span>Point the camera at the axle I'm editing</span>
      </label>
    </div>

    <div class="ss-section">
      <div class="ss-section-title">Wheel photos</div>
      <div class="ss-seg">
        <button :class="{ active: s.photoPass === 'auto' || !s.photoPass }" @click="set({ photoPass: 'auto' })">Automatic</button>
        <button :class="{ active: s.photoPass === 'ask' }" @click="set({ photoPass: 'ask' })">Ask first</button>
        <button :class="{ active: s.photoPass === 'off' }" @click="set({ photoPass: 'off' })">Off</button>
      </div>
      <div class="ss-muted ss-note">Each rim is photographed on its own, face-on, on a temporary copy of your car parked behind you, so you can keep tuning. Photos are saved under screenshots/stanceStudio/rims in your user folder and shared between cars that use the same wheels.</div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, onUnmounted } from "vue"
import { lua, useBridge } from "@/bridge"
import { luaCall, controlLabel, keyEventToControl, list } from "../api.js"
import { store, saveSettings, refresh, notify } from "../store.js"

const s = computed(() => store.state?.settings || {})
const current = computed(() => store.state?.keybind)
const listening = ref(false) // waiting for a key press
const captured = ref(null)   // the combo you pressed, not saved yet
const saving = ref(false)
const conflicts = ref([])
const colors = ["#38bdf8", "#4ade80", "#facc15", "#f472b6", "#ff6600", "#ffffff"]
const MODIFIERS = ["lalt", "ralt", "lshift", "rshift", "lcontrol", "rcontrol", "lwin", "rwin", "alt", "shift", "ctrl", "control", "meta"]

const label = controlLabel
const { events } = useBridge()
const keycapText = computed(() => {
  if (listening.value) return "Press a key combo…"
  if (captured.value) return label(captured.value)
  return label(current.value) || "No key"
})

function set(patch) { saveSettings(patch) }

function setMethod(m) {
  saveSettings({ method: m })
  // switch the current car too, keeping its stance values
  luaCall("stanceStudio_core.applyStance", { method: m })
}

// Like Options > Controls: listen to raw engine input only until one combo is pressed, then hand
// the mouse and keyboard back so Save / Cancel can be clicked.
async function accept(control) {
  if (!listening.value || !control) return
  const last = control.split(" ").pop()
  if (last === "escape") { cancelKey(); return }
  if (MODIFIERS.includes(last)) return // wait for the real key
  stopListening()
  captured.value = control
  conflicts.value = list(await luaCall("stanceStudio_core.getKeyConflicts", control))
}

function onRawInput(data) {
  if (!listening.value || !data) return
  if (!String(data.devName || "").startsWith("keyboard")) return
  if (data.controlType !== "key" && data.controlType !== "button") return
  if (!data.value) return // presses only
  accept(String(data.control || "").trim())
}

// backup path: with CEF typing on, the menu itself also sees the key
function onKeyDown(e) {
  if (!listening.value) return
  e.preventDefault()
  e.stopPropagation()
  if (e.key === "Escape") { cancelKey(); return }
  accept(keyEventToControl(e))
}

function startCapture() {
  if (listening.value) return
  listening.value = true
  captured.value = null
  conflicts.value = []
  window.__stanceStudioCapturing = true
  events.on("RawInputChanged", onRawInput)
  window.addEventListener("keydown", onKeyDown, true)
  try {
    lua.ActionMap.enableBindingCapturing(true) // keys don't run their actions (Esc won't close menus)
    lua.setCEFTyping(true)
    lua.Input.setForwardRawEvents(true)
  } catch (err) {
    console.error("[StanceStudio] key capture setup failed", err)
  }
}
function stopListening() {
  if (!listening.value) return
  listening.value = false
  events.off("RawInputChanged", onRawInput)
  window.removeEventListener("keydown", onKeyDown, true)
  try {
    lua.Input.setForwardRawEvents(false)
    lua.ActionMap.enableBindingCapturing(false)
    lua.setCEFTyping(false)
  } catch (err) {
    console.error("[StanceStudio] key capture teardown failed", err)
  }
  // let the release of the captured key pass before the menu reacts to keys again
  setTimeout(() => { if (!listening.value) window.__stanceStudioCapturing = false }, 300)
}
function cancelKey() {
  stopListening()
  captured.value = null
  conflicts.value = []
}
async function saveKey() {
  const control = captured.value
  if (!control || saving.value) return
  saving.value = true
  const ok = await luaCall("stanceStudio_core.setKeybind", control)
  saving.value = false
  if (ok) {
    captured.value = null
    conflicts.value = []
    notify("Open key set to " + controlLabel(control), "success")
  } else {
    notify("Couldn't save the key. You can also set it in Options › Controls.", "error", 6000)
  }
  setTimeout(refresh, 800) // bindings reload a moment after saving
}
async function removeKey() {
  await luaCall("stanceStudio_core.setKeybind", "")
  setTimeout(refresh, 800)
}

onUnmounted(stopListening)
</script>

<style lang="scss" scoped>
.ss-key-row { display: flex; gap: 0.45rem; align-items: center; }
.ss-keycap {
  flex: 1;
  padding: 0.55rem 0.8rem;
  border-radius: 0.45rem;
  background: rgba(0, 0, 0, 0.35);
  border: 1px solid rgba(255, 255, 255, 0.14);
  font-weight: 700;
  letter-spacing: 0.04em;
  &.capturing { border-color: var(--bng-orange, #ff6600); }
}
.ss-note { font-size: 0.76rem; margin-top: 0.4rem; line-height: 1.35; }
.ss-warn { margin-top: 0.4rem; font-size: 0.8rem; color: #fcd34d; }
.ss-toggle {
  display: flex;
  gap: 0.55rem;
  align-items: flex-start;
  margin-top: 0.55rem;
  font-size: 0.86rem;
  cursor: pointer;
  input { margin-top: 0.15rem; accent-color: var(--bng-orange, #ff6600); }
}
.ss-colors { margin-top: 0.55rem; }
.ss-swatch {
  width: 1.4rem;
  height: 1.4rem;
  border-radius: 50%;
  border: 2px solid transparent;
  cursor: pointer;
  &.active { border-color: #fff; }
}
</style>
