pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"

// ── Osd ───────────────────────────────────────────────────────────────────────
// "Something just changed because you pressed a key — here is what it is now."
//
// Hardware keys are blind input. A media key has no screen of its own, so pressing one
// leaves two questions it cannot answer: did that register, and what is the value now.
// Without an answer you press it four more times and overshoot. This is the answer, and
// it is the whole job — the overlay is never interacted with, only read.
//
// ── Why this observes rather than being told ──────────────────────────────────
// Pipewire pushes volume and mute reactively, to every client, no matter WHO changed
// them — the shell's own mixer, `wpctl` from a keybind, or an application. So the shell
// already knows, and the OSD needs no keybind changes at all: whatever your volume keys
// currently run, this sees the result. That is the repo's own rule about not spawning a
// subprocess to ask a question the shell has already been told the answer to.
//
// ── Brightness is the exception: it is ROUTED, not observed ───────────────────
// `services/Brightness.qml` only reads the hardware during its one-time probe and tracks
// its own writes thereafter, so a keybind that ran `brightnessctl` directly changed the
// panel without the shell ever hearing — there is no change signal to observe, and
// observing it would mean polling, or paying for a `ddcutil detect` at startup that the
// service is carefully lazy about.
//
// So the brightness keys now call `qs ipc call brightness step up|down` (hypr/binds.lua),
// and the service emits `keyStepped` — which is what is listened to below. Only KEYS,
// not every write: a slider being dragged in the overview or the brightness panel is
// already a screen full of feedback, and an overlay per frame of it would be noise.
// `show()` remains the door for anything else the shell cannot see.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── What is on screen right now ───────────────────────────────────────────
    // "" means nothing is showing. The surface owns its own copies of the rest — see
    // the note there about why a disappearing thing cannot bind to live state.
    property string kind:  ""       // "volume" | "mic" | anything a caller passes
    property real   value: 0        // 0..1, what the meter draws
    property bool   off:   false    // muted, or at zero — the fill and glyph say so
    property string glyph: ""
    property string label: ""

    // A real app icon, when one is known — shown in place of `glyph` rather than beside
    // it. "" (the overwhelming common case: mic, brightness, master volume, anything from
    // the generic IPC door) falls back to the glyph exactly as before; nothing has to
    // know an icon path exists to keep working.
    property string iconPath: ""

    // ── An announcement rather than a level ───────────────────────────────────
    // A Bluetooth device connecting has a NAME to say and maybe no level at all:
    // `caption` is a line of text in the middle, and `meter: false` drops the bar
    // (a full bar for a speaker that reports no battery would claim 100%). Both
    // reset on every show(), so the volume/mic OSD never inherits them.
    property string caption: ""
    property bool   meter:   true

    readonly property bool active: root.kind !== ""

    // ── What it shows ─────────────────────────────────────────────────────────
    // One surface, two contents (modules/osd/OsdColumn). A level (volume, mic, brightness)
    // is a column of sliders on the screen edge, and is the only thing the pointer can
    // drive; everything that has words — an announcement with a caption, a media pill's
    // player icon, an IPC kind the shell doesn't know — is a read-only tile in the same
    // place. `sliders` is the test that tells them apart. Exactly one shows per request.
    readonly property bool sliders: root.active && root.caption === "" && root.iconPath === ""
                                    && (root.kind === "volume" || root.kind === "mic"
                                        || root.kind === "brightness")

    // ── Bumped on every show, and the surface re-arms from THIS ───────────────
    // Not from `value`. Pressing volume-up while already at 100% changes nothing, but it
    // is still a keypress that deserves an answer and a fresh dismiss timer — bound to
    // the value, the second press would be invisible. Same reason ScreenshotToast re-arms
    // from `captureId` rather than from the path.
    property int requestId: 0

    function show(kind, value, off, glyph, label, iconPath) {
        if (!Config.osdEnabled || root.suppressed) return
        root.kind     = kind
        root.value    = Math.max(0, Math.min(1, value))
        root.off      = off
        root.glyph    = glyph
        root.label    = label
        root.iconPath = iconPath || ""
        root.caption  = ""
        root.meter    = true
        root.requestId++
    }

    // `value` < 0 = no meter. `label` is the short text on the right ("80%").
    function announce(kind, glyph, caption, label, value, off) {
        if (!Config.osdEnabled || root.suppressed) return
        root.kind     = kind
        root.value    = Math.max(0, Math.min(1, value))
        root.meter    = value >= 0
        root.off      = off
        root.glyph    = glyph
        root.label    = label
        root.caption  = caption
        root.iconPath = ""
        root.requestId++
    }

    function dismiss() { root.kind = "" }

    // ── A one-shot icon override for the NEXT observed volume change ──────────
    // Still an observer, not being told — `Audio.stepVolume()` itself carries no idea
    // of who called it, and staying that way is the point (see the header). This is the
    // one deliberate exception: a caller that already knows something Pipewire's signal
    // can't say — "this step came from scrolling the media pill, so show THAT player's
    // icon instead of the speaker glyph" — leaves a hint here, and `_fromAudio` spends
    // it on the very next volume OSD and then clears it, so a change from anywhere else
    // (the mixer, a hardware key, wpctl) is never shown under the wrong icon.
    property string _volumeGlyphHint: ""
    property string _volumeIconHint:  ""

    function hintNextVolume(glyph, iconPath) {
        root._volumeGlyphHint = glyph || ""
        root._volumeIconHint  = iconPath || ""
    }

    // ── Layout diagnostics ────────────────────────────────────────────────────
    // The surface reports its measured geometry here so `osd status` can answer "is
    // the meter actually on screen, and how wide" instead of it having to be inferred
    // from a screenshot. Two rounds were spent guessing at a collapsed meter from a
    // photograph — a binding loop, then the width arithmetic — and BOTH guesses were
    // wrong, which is exactly the failure this repo's notes describe: the fix that
    // matters is making the fault reportable, not being cleverer about inferring it.
    //
    // Written by the overlay, read by nothing else. Sizes only — there is no state
    // here worth leaking.
    property int diagCardW:  0
    property int diagGlyphW: 0
    property int diagMeterW: 0
    property int diagLabelW: 0

    // ── Don't narrate what is already on screen ───────────────────────────────
    // The mixer panel IS the volume UI: it is open, it is large, it shows the level and
    // it moves as you drag. A second overlay repeating that number in the middle of the
    // screen is noise, and a slider drag would fire one per frame.
    //
    // The power menu is the same kind of thing (a screen of its own, and on the same edge as
    // the level sliders) — and a volume key under a menu that is asking "shut down?" is not
    // the moment for an overlay.
    //
    // Deliberately NARROW. It would be easy to also suppress under the overview or the
    // settings window, but neither of those is volume UI — pressing a media key with the
    // overview open should still tell you what happened.
    readonly property bool suppressed: UiState.isOpen("equalizer") || UiState.powerMenuOpen

    // ── The startup flash, and why arming is not just a delay ─────────────────
    // Audio's properties settle asynchronously: `volume` exists as 0 until Pipewire
    // answers and is then replaced by the real level, and `muted` does the same. Those
    // are property CHANGES, indistinguishable from a keypress — so a plain connection
    // pops an OSD on every launch and every reload of the shell.
    //
    // A fixed delay doesn't fix it, because it races the very settling it is waiting on.
    // So the timer is RESTARTED by each change while disarmed: the service goes live
    // once audio has been quiet for a moment, whenever that turns out to be. The cost is
    // that a volume press in the first second after a reload is swallowed — which is the
    // right way round, since the alternative is a flash every single reload.
    property bool _armed: false

    Timer {
        id: armTimer
        interval: 1500
        repeat: false
        onTriggered: root._armed = true
    }

    Component.onCompleted: if (Audio.ready) armTimer.start()

    Connections {
        target: Audio

        function onReadyChanged() { if (Audio.ready) armTimer.restart() }

        function onVolumeChanged() { root._fromAudio("volume") }
        function onMutedChanged()  { root._fromAudio("volume") }

        // Mute only, NOT micVolume. Muting the microphone is the blind action — it is
        // what you do mid-call, by feel, and `PrivacyPill` cannot answer it because that
        // pill reports whether something is RECORDING, not whether you are muted. Mic
        // level, by contrast, is something you set once from the mixer while looking at
        // it, so an overlay for it would be noise.
        function onMicMutedChanged() { root._fromAudio("mic") }
    }

    Connections {
        target: Brightness

        function onKeyStepped(index) {
            const m = Brightness.monitors.get(index)
            if (!m) return
            const v = m.brightness / 100
            root.show("brightness", v, v <= 0, root.glyphFor("brightness", v, v <= 0), m.brightness + "%")
        }
    }

    function _fromAudio(which) {
        if (!Audio.ready) return
        if (!root._armed) { armTimer.restart(); return }

        if (which === "volume") {
            const m = Audio.muted
            const glyph = root._volumeGlyphHint || Audio.glyph(Audio.volume, m)
            const icon  = root._volumeIconHint
            root._volumeGlyphHint = ""
            root._volumeIconHint  = ""
            root.show("volume", Audio.volume, m || Audio.volume <= 0,
                      glyph,
                      m ? "Muted" : Math.round(Audio.volume * 100) + "%",
                      icon)
        } else {
            const mm = Audio.micMuted
            root.show("mic", mm ? 0 : Audio.micVolume, mm,
                      mm ? "󰍭" : "󰍬",
                      mm ? "Mic muted" : "Mic on")
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    //     qs ipc -c ~/.config/quicktest call osd show brightness 60 "60%"
    //     qs ipc -c ~/.config/quicktest call osd status
    //
    // The generic door for anything the shell cannot observe. A Hyprland bind that
    // changes brightness can call this straight afterwards to say what it did:
    //
    //     brightnessctl set 5%+ && qs ipc -c ~/.config/quicktest call osd show \
    //         brightness "$(brightnessctl -m | cut -d, -f4 | tr -d '%')" ""
    //
    // An empty label falls back to the percentage, which is what almost every caller
    // wants — the argument exists for the cases that read better as words ("Muted").
    property var _ipc: IpcHandler {
        target: "osd"

        function show(kind: string, percent: int, label: string): void {
            const k = (kind || "").trim() || "value"
            const p = Math.max(0, Math.min(100, percent))
            root.show(k, p / 100, p <= 0,
                      root.glyphFor(k, p / 100, p <= 0),
                      (label || "").trim() || (p + "%"))
        }

        function dismiss(): void { root.dismiss() }

        // Counts and states only — the same discipline the lyrics diagnostics keep.
        function status(): string {
            return "kind="      + (root.kind || "-")
                 + " active="   + root.active
                 + " armed="    + root._armed
                 + " suppressed=" + root.suppressed
                 + " enabled="  + Config.osdEnabled
                 + " ms="       + Config.osdMs
                 + " requests=" + root.requestId
                 + " | card="   + root.diagCardW
                 + " glyph="    + root.diagGlyphW
                 + " meter="    + root.diagMeterW
                 + " label="    + root.diagLabelW
        }
    }

    // Glyphs for kinds the shell drives itself, so an IPC caller gets the same icon the
    // observed path would have used rather than having to know the font.
    function glyphFor(kind, value, isOff) {
        if (kind === "volume") return Audio.glyph(value, isOff)
        if (kind === "mic")    return isOff ? "󰍭" : "󰍬"
        if (kind === "brightness")
            return isOff ? "󰃞" : value < 0.34 ? "󰃞" : value < 0.67 ? "󰃟" : "󰃠"
        return "󰋼"
    }
}
