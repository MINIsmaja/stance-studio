<template>
  <div class="ss-root">
    <aside class="ss-panel" :class="{ wide: activeTab === 'wheels' || activeTab === 'performance' || activeTab === 'fun' }">
      <header class="ss-header">
        <div class="ss-title">
          <div class="ss-brand">STANCE <span>STUDIO</span></div>
          <div class="ss-car">{{ vehicleName }}</div>
          <div v-if="store.state?.multiplayer === 'beammp'" class="ss-mp" title="Your stance, wheels, parts, tuning and Fun edits are sent with your car. Players who have Stance Studio (the server hands it out) see them.">
            Multiplayer · your changes sync to the other players
          </div>
          <div v-else-if="store.state?.multiplayer === 'tandem'" class="ss-mp" title="Friends in this session see your stance, wheels, parts, tuning and the Fun toggles and sliders. The torque curve and Advanced edits only change your own game. Stance Studio has to be one of the session's shared mods.">
            Tandem · friends see your stance
          </div>
        </div>
        <button class="ss-close" title="Close (Esc)" @click="close">✕</button>
      </header>

      <nav class="ss-tabs">
        <button v-for="t in tabs" :key="t.id" :class="{ active: activeTab === t.id, fun: t.id === 'fun' }" @click="tab = t.id">{{ t.label }}</button>
      </nav>

      <div v-if="store.state?.hookMissing" class="ss-broken">
        Part of Stance Studio did not load, so stance and Fun changes are off. Restart BeamNG to fix it
        (this happens when the mod zip is replaced while the game is running).
      </div>
      <div v-if="store.loading" class="ss-empty">Loading…</div>
      <div v-else-if="!store.state?.vehicle" class="ss-empty">Get in a vehicle to start tuning.</div>
      <div v-else-if="store.state.vehicle.remote" class="ss-empty">
        This is {{ store.state.vehicle.owner ? store.state.vehicle.owner + "'s" : "another player's" }} car.
        In multiplayer you can only change your own car.
      </div>
      <div v-else class="ss-content">
        <StanceTab v-if="activeTab === 'stance'" />
        <WheelsTab v-else-if="activeTab === 'wheels'" />
        <PerformanceTab v-else-if="activeTab === 'performance'" />
        <TuningTab v-else-if="activeTab === 'tuning'" />
        <FunTab v-else-if="activeTab === 'fun'" />
        <SettingsTab v-else-if="activeTab === 'settings'" />
      </div>

      <transition name="ss-fade">
        <div v-if="store.notice" class="ss-notice" :class="store.notice.kind">{{ store.notice.text }}</div>
      </transition>
    </aside>

    <div class="ss-hint">Drag outside the panel to look around · {{ keyLabel }} or Esc to close</div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import { luaCall, onEvent, keyEventToControl, controlLabel } from "./api.js"
import { store, refresh } from "./store.js"
import StanceTab from "./tabs/StanceTab.vue"
import WheelsTab from "./tabs/WheelsTab.vue"
import PerformanceTab from "./tabs/PerformanceTab.vue"
import TuningTab from "./tabs/TuningTab.vue"
import SettingsTab from "./tabs/SettingsTab.vue"
import FunTab from "./tabs/FunTab.vue"

const allTabs = [
  { id: "stance", label: "Stance" },
  { id: "wheels", label: "Wheels" },
  { id: "performance", label: "Performance" },
  { id: "tuning", label: "Tuning" },
  { id: "fun", label: "Fun" },
  { id: "settings", label: "Settings" },
]
// the Fun tab is the easter egg at the bottom of Settings
const funOn = computed(() => store.state?.settings?.funStuff === true)
const tabs = computed(() => allTabs.filter(t => t.id !== "fun" || funOn.value))

let savedTab = "stance"
try { savedTab = localStorage.getItem("stanceStudio.tab") || "stance" } catch (e) { /* storage off */ }
const tab = ref(allTabs.some(t => t.id === savedTab) ? savedTab : "stance")
const activeTab = computed(() => (tab.value === "fun" && !funOn.value ? "stance" : tab.value))
const remember = () => { try { localStorage.setItem("stanceStudio.tab", activeTab.value) } catch (e) { /* storage off */ } }

const vehicleName = computed(() => store.state?.vehicle?.name || "")
const keyLabel = computed(() => controlLabel(store.state?.keybind))

function close() {
  remember()
  luaCall("stanceStudio_core.close")
}

function onKey(e) {
  if (window.__stanceStudioCapturing) return
  const t = e.target
  const typing = t && (t.tagName === "TEXTAREA" || (t.tagName === "INPUT" && !["checkbox", "radio", "range", "button"].includes(t.type)))
  if (typing) {
    // keys typed into a text box are text; Esc just leaves the box
    if (e.key === "Escape") { e.preventDefault(); t.blur() }
    return
  }
  if (e.key === "Escape") { e.preventDefault(); close(); return }
  const control = keyEventToControl(e)
  if (control && store.state?.keybind && control === store.state.keybind) {
    e.preventDefault()
    close()
  }
}

const offs = []
onMounted(() => {
  luaCall("stanceStudio_core.onUiOpened")
  refresh()
  offs.push(onEvent("stanceStudioState", s => { if (s) store.state = s }))
  offs.push(onEvent("stanceStudioPhotos", p => {
    if (!p) return
    store.photos = p
    if (p.photo) store.photoVersion++
  }))
  window.addEventListener("keydown", onKey, true)
})

onUnmounted(() => {
  remember()
  window.removeEventListener("keydown", onKey, true)
  offs.forEach(off => off())
  luaCall("stanceStudio_core.onUiClosed")
})
</script>

<style lang="scss" scoped>
.ss-root {
  position: absolute;
  inset: 0;
  pointer-events: none;
  font-family: inherit;
  color: #f2f4f7;
}

.ss-panel {
  pointer-events: all;
  position: absolute;
  top: 1.5rem;
  left: 1.5rem;
  bottom: 1.5rem;
  width: 27rem;
  max-width: calc(100vw - 3rem);
  display: flex;
  flex-direction: column;
  background: rgba(16, 18, 22, 0.9);
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 0.9rem;
  box-shadow: 0 1rem 3rem rgba(0, 0, 0, 0.45);
  overflow: hidden;
  transition: width 0.2s ease;
  &.wide { width: 34rem; }
}

.ss-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem 1.1rem 0.6rem;
}
.ss-brand {
  font-weight: 800;
  letter-spacing: 0.14em;
  font-size: 1.05rem;
  span { color: var(--bng-orange, #ff6600); }
}
.ss-car { opacity: 0.65; font-size: 0.9rem; margin-top: 0.15rem; }
.ss-mp { font-size: 0.72rem; margin-top: 0.2rem; color: #7dd3fc; opacity: 0.85; }
.ss-close {
  border: 0;
  background: rgba(255, 255, 255, 0.08);
  color: #fff;
  width: 2.2rem;
  height: 2.2rem;
  border-radius: 50%;
  cursor: pointer;
  font-size: 1rem;
  &:hover { background: rgba(255, 255, 255, 0.18); }
}

.ss-tabs {
  display: flex;
  gap: 0.25rem;
  padding: 0 0.8rem 0.6rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.07);
  button {
    flex: 1;
    border: 0;
    background: transparent;
    color: rgba(255, 255, 255, 0.6);
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    padding: 0.55rem 0.15rem;
    border-radius: 0.45rem;
    cursor: pointer;
    font-size: 0.86rem;
    font-weight: 600;
    &:hover { background: rgba(255, 255, 255, 0.06); color: #fff; }
    &.fun:not(.active) { color: #f0abfc; }
    &.active { background: var(--bng-orange, #ff6600); color: #fff; }
  }
}

.ss-content {
  flex: 1;
  overflow-y: auto;
  padding: 0.9rem 1.1rem 1.2rem;
  &::-webkit-scrollbar { width: 6px; }
  &::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, 0.15); border-radius: 3px; }
}
.ss-empty { padding: 2rem 1.2rem; opacity: 0.7; }
.ss-broken {
  margin: 0.6rem 0.9rem 0;
  padding: 0.6rem 0.75rem;
  border-radius: 0.5rem;
  background: rgba(248, 113, 113, 0.16);
  color: #fecaca;
  font-size: 0.82rem;
  line-height: 1.35;
}

.ss-notice {
  position: absolute;
  left: 1rem;
  right: 1rem;
  bottom: 1rem;
  padding: 0.7rem 0.9rem;
  border-radius: 0.5rem;
  background: #2b3340;
  font-size: 0.9rem;
  &.warning { background: #5a4214; }
  &.error { background: #5c1f1f; }
  &.success { background: #1f4d2e; }
}
.ss-fade-enter-active, .ss-fade-leave-active { transition: opacity 0.2s; }
.ss-fade-enter-from, .ss-fade-leave-to { opacity: 0; }

.ss-hint {
  position: absolute;
  right: 1.5rem;
  bottom: 1.5rem;
  padding: 0.45rem 0.8rem;
  border-radius: 0.4rem;
  background: rgba(0, 0, 0, 0.45);
  font-size: 0.82rem;
  opacity: 0.8;
}
</style>

<style lang="scss">
/* shared look for every tab (not scoped) */
.ss-section { margin-bottom: 1.1rem; }
.ss-section-title {
  font-size: 0.75rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  opacity: 0.55;
  margin: 0 0 0.5rem;
}
.ss-seg {
  display: flex;
  background: rgba(255, 255, 255, 0.06);
  border-radius: 0.5rem;
  padding: 0.2rem;
  gap: 0.2rem;
  button {
    flex: 1;
    border: 0;
    background: transparent;
    color: rgba(255, 255, 255, 0.7);
    padding: 0.45rem 0.4rem;
    border-radius: 0.35rem;
    cursor: pointer;
    font-weight: 600;
    font-size: 0.85rem;
    &.active { background: rgba(255, 255, 255, 0.16); color: #fff; }
    &:disabled { opacity: 0.35; cursor: default; }
  }
}
.ss-btn {
  border: 0;
  border-radius: 0.45rem;
  padding: 0.55rem 0.9rem;
  background: rgba(255, 255, 255, 0.1);
  color: #fff;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.88rem;
  &:hover { background: rgba(255, 255, 255, 0.18); }
  &:disabled { opacity: 0.4; cursor: default; }
  &.ss-primary { background: var(--bng-orange, #ff6600); &:hover { filter: brightness(1.1); } }
  &.ss-small { padding: 0.35rem 0.6rem; font-size: 0.8rem; }
}
.ss-chip {
  border: 1px solid rgba(255, 255, 255, 0.14);
  background: transparent;
  color: #fff;
  border-radius: 999px;
  padding: 0.3rem 0.75rem;
  font-size: 0.8rem;
  cursor: pointer;
  &:hover { border-color: rgba(255, 255, 255, 0.4); }
  &.active { background: var(--bng-orange, #ff6600); border-color: transparent; }
}
.ss-row { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
.ss-muted { opacity: 0.6; font-size: 0.85rem; }
.ss-input, .ss-select {
  width: 100%;
  box-sizing: border-box;
  border: 1px solid rgba(255, 255, 255, 0.12);
  background: rgba(0, 0, 0, 0.3);
  color: #fff;
  border-radius: 0.45rem;
  padding: 0.5rem 0.7rem;
  font-size: 0.9rem;
  outline: none;
  &:focus { border-color: var(--bng-orange, #ff6600); }
}
.ss-badge {
  display: inline-block;
  font-size: 0.72rem;
  padding: 0.12rem 0.45rem;
  border-radius: 0.3rem;
  background: rgba(255, 255, 255, 0.1);
  white-space: nowrap;
  &.accent { background: rgba(255, 102, 0, 0.25); color: #ffb380; }
  &.mod { background: rgba(56, 189, 248, 0.18); color: #9adcfb; }
  &.good { background: rgba(74, 222, 128, 0.18); color: #a7f3c0; }
  &.bad { background: rgba(248, 113, 113, 0.18); color: #fca5a5; }
}
.ss-progress {
  height: 6px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.1);
  overflow: hidden;
  > div { height: 100%; background: var(--bng-orange, #ff6600); transition: width 0.3s; }
}
</style>
