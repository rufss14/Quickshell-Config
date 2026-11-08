// ── test-material-presets.qml ─────────────────────────────────────────────────
// The harness scripts/test-material-presets.sh runs: services/MaterialPresets driven through its states
// with a stub Config and ColorScheme. Prints "ALL OK" or the failed checks.
import QtQuick
import "config"
import "services"
Item {
    id: t
    width: 100; height: 100
    function pal(seed) {
        const o = { special: { background: "#101010", foreground: "#eeeeee", cursor: "#eeeeee" }, colors: {} }
        for (let i = 0; i < 16; i++) { const h = ((seed * 37 + i * 11) % 200 + 20).toString(16).padStart(2, "0"); o.colors["color" + i] = "#" + h + h + ((seed * 7 + i) % 200 + 20).toString(16).padStart(2, "0") }
        o.special.background = "#" + ((seed * 13) % 60 + 10).toString(16).padStart(2, "0") + "1010"
        return o
    }
    property int fails: 0
    function say(m) { console.log(m) }
    function ok(n, c) { if (!c) { fails++; say("FAIL " + n) } else say("ok   " + n) }
    MaterialPresets { id: mp }
    property var step: 0
    Timer { interval: 60; repeat: true; running: true; onTriggered: { try { t.run(t.step++) } catch (e) { say("EXC " + e); Qt.quit() } } }
    function run(n) {
        switch (n) {
        case 0:   // startup: live and library arrive
            ColorScheme.live = pal(1)
            ColorScheme.presets = [{ name: "A", variants: { dark: pal(1), light: null } }, { name: "B", variants: { dark: pal(2), light: null } }]
            break
        case 2:
            ok("scheme A is worn", mp.wornScheme === "A")
            ok("start-up loaded nothing", Config.wallMaterialContrast === 1)
            // user makes a mix, saves it
            Config.wallMaterial = true
            Config.wallMaterialContrast = 1.3; Config.wallMaterialMirror = true
            ok("a mix is no look", mp.currentKey === "")
            ok("save names it", mp.save("  Mine ") === "my:Mine")
            ok("then it is the look in use", mp.currentKey === "my:Mine")
            mp.toggleLink()
            ok("the lock links it to the scheme worn", mp.linkedKey === "my:Mine" && mp.schemesOf("my:Mine").join() === "A")
            break
        case 3:   // change the style, apply scheme B (no link) then A again
            Config.wallMaterialContrast = 0.7
            ColorScheme.live = pal(2)
            break
        case 5:
            ok("scheme B is worn, unlinked: style untouched", mp.wornScheme === "B" && Config.wallMaterialContrast === 0.7)
            ColorScheme.live = pal(1)
            break
        case 7:
            ok("applying A again loads its look", Config.wallMaterialContrast === 1.3 && Config.wallMaterialMirror === true)
            // a wallpaper change (no scheme), then tweak, then the same scheme back within the hold: nothing
            ColorScheme.live = pal(50)
            break
        case 9:
            ok("a wallpaper's palette is no scheme", mp.wornScheme === "")
            Config.wallMaterialContrast = 0.9
            ColorScheme.live = pal(1)
            break
        case 11:
            ok("the same scheme back after a blink is not applying it", Config.wallMaterialContrast === 0.9)
            // Material off: applying a scheme does nothing
            Config.wallMaterial = false
            ColorScheme.live = pal(2)
            break
        case 13:
            ColorScheme.live = pal(1)
            break
        case 15:
            ok("with Material off a scheme loads nothing", Config.wallMaterialContrast === 0.9)
            // Applying Material over a custom unsaved mix keeps it
            Config.wallMaterial = true
            ok("Apply over a mix of one's own leaves it", Config.wallMaterialContrast === 0.9)
            // …and over one of the looks wears the link
            mp.apply("calm")
            Config.wallMaterial = false
            Config.wallMaterial = true
            break
        case 17:
            ok("Apply over a look wears the scheme's look", Config.wallMaterialContrast === 1.3)
            // delete the saved look: its link goes
            mp.remove("my:Mine")
            break
        case 19:
            ok("deleting a look drops its links", Object.keys(mp.links).length === 0 && mp.saved.length === 0)
            // a scheme that goes: links are pruned
            Config.wallMaterialLinks = { A: "calm", Gone: "calm" }
            ColorScheme.presets = [{ name: "A", variants: { dark: pal(1), light: null } }]
            break
        case 21:
            ok("a link to a deleted scheme is dropped", JSON.stringify(mp.links) === '{"A":"calm"}')
            // hand-edited junk
            Config.wallMaterialSaved = [{ name: "x", style: { contrast: 99, evil: 1 } }, { name: "X", style: {} }, null, { name: "", style: {} }]
            ok("saved looks are cleaned: one, in range", mp.saved.length === 1 && mp.saved[0].style.contrast === 1.5)
            Config.wallMaterialLinks = { A: "my:nope", B: 5 }
            ok("links to nothing are ignored", Object.keys(mp.links).length === 0)
            ok("no scheme: no lock", (ColorScheme.live = pal(99), true))
            break
        case 23:
            mp.toggleLink()
            ok("no scheme worn: the lock does nothing", Object.keys(mp.links).length === 0 && mp.linkBlocker() !== "")
            say(t.fails === 0 ? "ALL OK" : t.fails + " FAILED"); Qt.quit()
            break
        }
    }
}
