<template>
  <div class="ss-pause-card">
    <h2>Stance Studio</h2>
    <p>Stance, wheels and performance parts in one place. Works on every car, mod cars included.</p>
    <button class="ss-btn ss-primary" @click="open">Open Stance Studio</button>
    <p class="ss-hint">Shortcut: {{ keyLabel }} (change it in the Settings tab)</p>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue"
import { luaCall, controlLabel } from "./api.js"

const keyLabel = ref("Alt + E")
onMounted(async () => {
  const state = await luaCall("stanceStudio_core.getState")
  if (state) keyLabel.value = controlLabel(state.keybind)
})
function open() {
  luaCall("stanceStudio_core.open")
}
</script>

<style lang="scss" scoped>
.ss-pause-card {
  padding: 1.5rem;
  color: #fff;
  h2 { margin: 0 0 0.5rem; font-size: 1.4rem; }
  p { opacity: 0.85; line-height: 1.4; }
  .ss-hint { font-size: 0.85rem; opacity: 0.6; }
}
.ss-btn {
  border: 0;
  border-radius: 0.4rem;
  padding: 0.7rem 1.2rem;
  font-size: 1rem;
  cursor: pointer;
  color: #fff;
  background: rgba(255, 255, 255, 0.12);
}
.ss-primary { background: var(--bng-orange, #ff6600); }
</style>
