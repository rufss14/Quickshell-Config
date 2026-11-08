// Run: bun scripts/test-clockfmt.js   (exit 1 on any failure)
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "services", "clockfmt.js"), "utf8")
const { clock } = new Function(src + "\nreturn { clock }")()

const cases = [
    [0, "0:00"], [-3, "0:00"], [NaN, "0:00"], [undefined, "0:00"],
    [5, "0:05"], [59.9, "0:59"], [65, "1:05"], [600, "10:00"],
    [3599, "59:59"], [3600, "1:00:00"], [3725, "1:02:05"], [36000, "10:00:00"],
]
let fails = 0
for (const [input, want] of cases) {
    const got = clock(input)
    if (got !== want) { fails++; console.log(`FAIL clock(${input}) = ${got}, want ${want}`) }
}
console.log(fails ? `${fails} failed` : `${cases.length} passed`)
process.exit(fails ? 1 : 0)
