// Compiles every .vue file of the mod (script, template and SCSS) to catch errors before the game does.
// Needs @vue/compiler-sfc and sass in a node_modules folder:
//   mkdir -p ~/.cache/stance-studio-vuecheck && cd ~/.cache/stance-studio-vuecheck
//   npm install @vue/compiler-sfc@3 sass@1
// Usage: node tests/tools/check_vue.cjs [mod dir]   (VUECHECK_MODULES overrides the node_modules folder)
const fs = require("fs")
const path = require("path")
const os = require("os")

const modules = process.env.VUECHECK_MODULES || path.join(os.homedir(), ".cache/stance-studio-vuecheck/node_modules")
const sfc = require(path.join(modules, "@vue/compiler-sfc"))
const sass = require(path.join(modules, "sass"))

const modDir = process.argv[2] || path.join(__dirname, "../../mod")
const uiDir = path.join(modDir, "ui/ui-vue/mods/stanceStudio")

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => {
    const p = path.join(dir, e.name)
    return e.isDirectory() ? walk(p) : p.endsWith(".vue") ? [p] : []
  })
}

let failed = 0
for (const file of walk(uiDir)) {
  const rel = path.relative(modDir, file)
  const problems = []
  const src = fs.readFileSync(file, "utf8")
  const { descriptor, errors } = sfc.parse(src, { filename: file })
  errors.forEach(e => problems.push("parse: " + (e.message || e)))
  const id = "x" + Math.random().toString(36).slice(2, 8)
  let bindings
  if (descriptor.script || descriptor.scriptSetup) {
    try {
      const script = sfc.compileScript(descriptor, { id })
      bindings = script.bindings
    } catch (e) { problems.push("script: " + e.message) }
  }
  if (descriptor.template) {
    const t = sfc.compileTemplate({
      source: descriptor.template.content, filename: file, id,
      scoped: descriptor.styles.some(s => s.scoped),
      compilerOptions: { bindingMetadata: bindings },
    })
    t.errors.forEach(e => problems.push("template: " + (e.message || e)))
  }
  for (const style of descriptor.styles) {
    let css = style.content
    if (style.lang === "scss") {
      try { css = sass.compileString(css).css } catch (e) { problems.push("scss: " + e.message.split("\n")[0]); continue }
    }
    const r = sfc.compileStyle({ source: css, filename: file, id, scoped: style.scoped })
    r.errors.forEach(e => problems.push("style: " + (e.message || e)))
  }
  if (problems.length) {
    failed++
    console.log("FAIL " + rel)
    problems.forEach(p => console.log("     " + p))
  } else {
    console.log("ok   " + rel)
  }
}
console.log(failed ? `${failed} file(s) with errors` : "all .vue files compile")
process.exit(failed ? 1 : 0)
