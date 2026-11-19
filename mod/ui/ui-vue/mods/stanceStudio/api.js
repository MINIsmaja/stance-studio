// Small bridge to the stanceStudio_* Lua extensions
import { useBridge } from "@/bridge"

export function luaCall(fn, ...args) {
  const { api } = useBridge()
  const argStr = args.map(a => api.serializeToLua(a === undefined ? null : a)).join(",")
  return new Promise(resolve => {
    try {
      api.engineLua(`extensions.${fn}(${argStr})`, resolve)
    } catch (err) {
      console.error("[StanceStudio] Lua call failed", fn, err)
      resolve(undefined)
    }
  })
}

// Lua sends an empty table as {} (not []), and sparse ones as objects: always get a real array
export function list(x) {
  if (Array.isArray(x)) return x
  if (x && typeof x === "object") return Object.values(x)
  return []
}

export function onEvent(name, handler) {
  const { events } = useBridge()
  events.on(name, handler)
  return () => events.off(name, handler)
}

// throttle that always delivers the last call
export function throttle(fn, ms) {
  let last = 0
  let timer = null
  let pendingArgs = null
  return (...args) => {
    pendingArgs = args
    const now = Date.now()
    const run = () => {
      last = Date.now()
      timer = null
      fn(...pendingArgs)
    }
    if (now - last >= ms) run()
    else if (!timer) timer = setTimeout(run, ms - (now - last))
  }
}

// unit helpers (values in Lua are meters / degrees / multipliers)
export const units = {
  lengthUnit: s => (s?.units === "imperial" ? "in" : "mm"),
  toDisplay: (m, s) => (s?.units === "imperial" ? m / 0.0254 : m * 1000),
  fromDisplay: (v, s) => (s?.units === "imperial" ? v * 0.0254 : v / 1000),
}

// BeamNG key names from a browser key event ("ctrl alt shift x")
const CODE_MAP = {
  Space: "space", Tab: "tab", Enter: "enter", Backspace: "backspace", Delete: "delete", Insert: "insert",
  Home: "home", End: "end", PageUp: "pageup", PageDown: "pagedown",
  ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
  Comma: "comma", Period: "period", Slash: "slash", Backquote: "tilde", Minus: "minus", Equal: "equals",
  Semicolon: "semicolon", Quote: "apostrophe", BracketLeft: "lbracket", BracketRight: "rbracket", Backslash: "backslash",
  NumpadAdd: "numpadadd", NumpadSubtract: "numpadminus", NumpadMultiply: "numpadmult", NumpadDivide: "numpaddivide",
  NumpadDecimal: "numpaddecimal", NumpadEnter: "numpadenter",
}
export function keyEventToControl(e) {
  const code = e.code || ""
  if (/^(Shift|Control|Alt|Meta)/.test(code) || e.key === "Escape") return null
  let key = null
  if (/^Key[A-Z]$/.test(code)) key = code.slice(3).toLowerCase()
  else if (/^Digit\d$/.test(code)) key = code.slice(5)
  else if (/^F\d{1,2}$/.test(code)) key = code.toLowerCase()
  else if (/^Numpad\d$/.test(code)) key = "numpad" + code.slice(6)
  else key = CODE_MAP[code] || null
  if (!key) return null
  const mods = []
  if (e.ctrlKey) mods.push("ctrl")
  if (e.altKey) mods.push("alt")
  if (e.shiftKey) mods.push("shift")
  return [...mods, key].join(" ")
}

export function controlLabel(control) {
  if (!control) return "Not set"
  return control.split(" ").map(p => (p.length <= 2 ? p.toUpperCase() : p[0].toUpperCase() + p.slice(1))).join(" + ")
}
