import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── PrivacyPill ───────────────────────────────────────────────────────────────
// Two mic-related jobs sharing one bar slot, because they trade off in time rather
// than at once: mid-call, "is something recording me" already has an answer — yes,
// Discord — and the useful question becomes "am I muted, and can it hear me right
// now." Outside a call it reverts to the plain privacy warning.
//
// ── In a Discord call: a real mute toggle ─────────────────────────────────────
// Click dispatches Discord.toggleMute() — real RPC, the same call the participant
// list's own mute button uses — rather than detouring through the mixer. The colour
// is Discord's own SPEAKING flag for your own entry in `Discord.users` (found by
// `isSelf`), so the pill answers "is Discord actually hearing my voice right now",
// not just "is the mic unmuted" — server mute, a bad input device or the mixer's own
// mute could all say unmuted while nothing is actually getting through.
//
// ── Otherwise: the generic privacy warning, unchanged ─────────────────────────
// `Audio.recordingApps` is the mixer's own list of capture streams, already grouped
// by application, already excluding monitors and loopbacks (`_isMonitor` /
// `_capturesSink` — a stream reading what your speakers are playing is not a stream
// listening to your room, and conflating the two would light this up every time you
// screen-shared). It comes off PipeWire's registry, so it is event-driven: there is
// no poll here and no process spawned to answer the question. Present only when
// something IS recording — an always-visible "nothing is recording" indicator is a
// thing you stop seeing within a day, which is exactly the wrong property for a
// warning — and a click goes to the mixer, where you'd actually do something about
// an app that isn't Discord.
//
// ── Microphone only, deliberately ─────────────────────────────────────────────
// There is no camera equivalent here. PipeWire's registry describes audio nodes; a
// webcam in use is a V4L2 file descriptor on /dev/video*, which nothing publishes and
// which could only be discovered by polling `fuser` on every video device on a timer.
// This shell prefers event-driven integration to polling, and a mic indicator that is
// free and honest beats a mic-and-camera one that wakes the process forever. If the
// camera half is wanted later it should be its own opt-in, with its cost stated.
// ─────────────────────────────────────────────────────────────────────────────
BarIconPill {
    id: root

    // No `accent` declared here: IconButton already has one (with the same
    // Colors.primary default), and redeclaring it shadowed that property AND was then
    // assigned over the top — which is "Property value set multiple times", a hard
    // load failure for the whole file. BarIconPill resolves it from `moduleId`, along
    // with container / squareMode / spacing.
    moduleId: "privacy"

    readonly property var apps:  Audio.recordingApps
    readonly property int count: root.apps.length

    // A muted source is the case worth distinguishing: an app still HOLDS the stream
    // (so it will hear you the instant the mute comes off) but is getting silence right
    // now. Showing that as plain "recording" over-warns; hiding the pill entirely
    // under-warns. It stays, dimmed, with the crossed-out icon.
    readonly property bool live: root.count > 0 && !Audio.micMuted

    // Discord takes over the pill's meaning for exactly as long as a call is up.
    readonly property bool discordMode: Discord.enabled && Discord.inCall

    readonly property var  discordSelf:     Discord.users.find(u => u.isSelf ?? false) ?? null
    readonly property bool discordSpeaking: !!(root.discordSelf && root.discordSelf.speaking)

    // Visible whenever Discord is configured, not just mid-call — it's the mic-mute
    // control now, and a control that vanishes the moment you hang up isn't reachable
    // for the NEXT call either. Outside a call it just shows the generic idle/recording
    // state (below) and a click goes to Sound settings, same as it always did.
    //
    // Someone with Discord integration entirely off gets the old behaviour back
    // unchanged: present only while something is actually recording, because for them
    // there's no toggle living here to keep reachable.
    visible: Discord.enabled || root.count > 0

    // No `active:` binding — IconButton fills an accent-tinted background pill whenever
    // `active` is true, which is right for a toggle whose ONLY state signal is that fill
    // (WifiPill, the group pills). This icon already carries its own state entirely
    // through colour (iconColor below) and the corner dot, so the extra fill was a
    // second, redundant "something is happening here" that just read as a stray
    // background behind a small floating icon.

    // Discord's own self-mute and the system mic are two separate switches — Discord's
    // stops the call from TRANSMITTING, PipeWire's stops the hardware from capturing at
    // all, and muting one silently leaves the other live. A click here is meant to mean
    // "stop my mic", full stop, so it drives both rather than only the one Discord
    // happens to expose over RPC. `anyMuted` reads true if EITHER already is, so the
    // icon stays honest even if something outside this pill muted just one side.
    readonly property bool anyMuted: Discord.mute || Audio.micMuted

    symbol: root.discordMode
        ? (root.anyMuted ? "mic_off" : "mic")
        : (root.live     ? "mic"     : "mic_off")

    // Muted: dimmed, same idle colour the generic warning uses for a silenced source.
    // Unmuted-but-quiet: the ordinary accent — you CAN be heard, you aren't right now.
    // Unmuted-and-speaking: success, because that's the one moment worth calling out.
    readonly property color micColor: root.discordMode
        ? (root.anyMuted ? Colors.of(QsWindow.window).stateIdleFg
                          : (root.discordSpeaking ? Colors.of(QsWindow.window).success : root.accent))
        : (root.live ? root.accent : Colors.of(QsWindow.window).stateIdleFg)

    iconColor: root.micColor

    onClicked: {
        if (root.discordMode) {
            // Set BOTH to the same target rather than blind-toggling each — a blind
            // toggle on top of a drifted state (say Discord already muted, mic not)
            // would just swap which one is muted instead of unifying them. Comparing
            // against the CURRENT value of each before flipping it means one click
            // always converges to fully muted or fully unmuted, never a partial state.
            const target = !root.anyMuted
            if (Discord.mute   !== target) Discord.toggleMute()
            if (Audio.micMuted !== target) Audio.toggleMicMute()
        } else {
            // Outside a call there's no Discord side to unify with — just the mic.
            Audio.toggleMicMute()
        }
    }

    // Settings moved to the second button: a left click is the thing you reach for
    // constantly (every call, every "wait am I muted"), and a control that detours
    // through a settings page on its main action makes the actual toggle a click away
    // from where your hand already is. Right-click is the escape hatch for "no, the
    // mixer" — same button BatteryPill and friends use for their own secondary action.
    onRightClicked: UiState.openSettingsTo("SoundPage.qml")

    // ── The recording dot ──────────────────────────────────────────────────────
    // Unconditional on discordMode: the icon's own colour is busy answering "can
    // Discord hear me right now", which is a different question from "is a stream
    // open at all". A muted Discord call still HOLDS its capture stream — see `live`
    // above — so this stays lit through a mute exactly like it should: your hardware
    // mic is still capturing, only the transmission is (self-reported) silenced.
    // Pinned to the ICON, not the button's own box — `container: false` leaves this
    // sitting in the same padded hit-target every other bar pill uses, so anchoring to
    // `parent`'s corner (UpdatePill's approach, right for a filled pill the same size as
    // its icon) put the dot well past the actual ink. Offset from centre by roughly the
    // icon's own radius instead, so it sits right at the icon's edge regardless of how
    // much empty hit-target surrounds it.
    Rectangle {
        visible: root.count > 0
        width:  Math.round(4 * Config.barIconScale)
        height: Math.round(4 * Config.barIconScale)
        radius: width / 2
        color:  root.micColor

        anchors.centerIn: parent
        anchors.horizontalCenterOffset:  Math.round(root.glyphSize * 0.4)
        anchors.verticalCenterOffset:   -Math.round(root.glyphSize * 0.4)
    }
}
