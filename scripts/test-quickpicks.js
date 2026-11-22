// bun scripts/test-quickpicks.js — the bar pill's wallpaper quick card: which pictures it offers to try.
const fs = require("fs"), path = require("path")
const src = fs.readFileSync(path.join(__dirname, "../modules/bar/quick/quickpicks.js"), "utf8").replace(".pragma library", "")
const { sample } = new Function(src + "; return { sample }")()
let fail = 0
const eq = (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) { fail++; console.log(`FAIL ${name}: ${JSON.stringify(got)} != ${JSON.stringify(want)}`) } }
const lib = ["/w/a.jpg", "/w/b.png", "/w/c.jpg", "/w/d.jpg", "/w/e.jpg", "/w/f.jpg"]
const a = sample(lib, "a.jpg", 3, 7)
eq("count", a.length, 3)
eq("never the one on screen", a.includes("/w/a.jpg"), false)
eq("no duplicates", new Set(a).size, 3)
eq("same seed, same pictures", sample(lib, "a.jpg", 3, 7), a)
let differs = false
for (let s = 0; s < 20; s++) if (JSON.stringify(sample(lib, "a.jpg", 3, s)) !== JSON.stringify(a)) differs = true
eq("another seed can differ", differs, true)
eq("small library: all but the current", sample(["/w/a.jpg", "/w/b.png"], "a.jpg", 3, 1), ["/w/b.png"])
eq("empty library", sample([], "", 3, 1), [])
eq("only the current", sample(["/w/a.jpg"], "a.jpg", 3, 1), [])
eq("input untouched", lib.length, 6)
console.log(fail ? `${fail} failed` : "all passed"); process.exit(fail ? 1 : 0)
