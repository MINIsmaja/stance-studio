// Stance Studio entry point: registers the screen route and a pause-menu button
import { useBridge } from "@/bridge"
import StanceStudio from "./StanceStudio.vue"

const sourceId = "stanceStudio.routes"
const routes = [
  {
    path: "/stance-studio",
    name: "stanceStudio",
    component: StanceStudio,
    meta: {
      infoBar: { visible: false, showSysInfo: false },
      topBar: { visible: false },
      uiApps: { shown: false },
      luaRoute: {
        title: "Stance Studio",
        backTarget: "play",
      },
    },
  },
]

function toLuaRoutes(records) {
  return records.map(record => ({
    name: record.name,
    path: record.path,
    meta: record.meta,
    ...(record.children ? { children: toLuaRoutes(record.children) } : {}),
  }))
}

export async function onLoad() {
  const { lua } = useBridge()
  window.bngRoutes.add([{ path: sourceId, routes }])
  const result = await lua.extensions.ui_router_routeManager.registerModRoutes(sourceId, toLuaRoutes(routes))
  if (!result?.success) {
    window.bngRoutes.remove([sourceId])
    console.error("[StanceStudio] Failed to register route", result?.errors)
    return
  }
  await lua.extensions.ui_pause_actions.registerModButton({
    id: "stanceStudio-open",
    tabId: "mods",
    label: "Stance Studio",
    icon: "wrench",
    componentName: "/ui/ui-vue/mods/stanceStudio/PauseCard.vue",
  })
}

export async function onUnload() {
  const { lua } = useBridge()
  await lua.extensions.ui_pause_actions.unregisterModButton("stanceStudio-open")
  window.bngRoutes.remove([sourceId])
  await lua.extensions.ui_router_routeManager.unregisterModRoutes(sourceId, { fallbackRoute: "play" })
}
