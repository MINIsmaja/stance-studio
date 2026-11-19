// Shared state for all Stance Studio tabs
import { reactive } from "vue"
import { luaCall } from "./api.js"

export const store = reactive({
  state: null,          // from stanceStudio_core.getState()
  loading: true,
  photos: { running: false, index: 0, total: 0 },
  photoVersion: 0,      // bumps when a new wheel photo was saved
  notice: null,         // {kind, text}
})

let noticeTimer = null
export function notify(text, kind = "info", ms = 4000) {
  store.notice = { text, kind }
  clearTimeout(noticeTimer)
  noticeTimer = setTimeout(() => (store.notice = null), ms)
}

export async function refresh() {
  const s = await luaCall("stanceStudio_core.getState")
  if (s) store.state = s
  store.loading = false
  return s
}

export function settings() {
  return store.state?.settings || {}
}

export async function saveSettings(patch) {
  const s = await luaCall("stanceStudio_core.saveSettings", patch)
  if (s && store.state) store.state.settings = s
  return s
}
