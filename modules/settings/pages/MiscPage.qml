pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/lyricsmotion.js" as LyricMotion

// ── MiscPage — Integrations › Lyrics ──────────────────────────────────────────
// Where the words come from, how they move, and whether they're translated. (The file
// keeps its old name so remembered pages and the media panel's "open settings" link
// still resolve; "misc" survives as a search keyword.)
//
// ── Motion is shown, not described ────────────────────────────────────────────
// "Motion: Subtle" is a word about something that only exists while music is playing
// and the overview is open — you set it here and found out there. The card now holds a
// line of lyric that actually moves, word by word, through
// services/lyricsmotion.js — the SAME function LyricGlyphs calls per syllable, at the
// same intensity — so the preview cannot describe a motion the card doesn't have.
//
// It plays while the pointer is over it, and once by itself whenever you move the
// slider. Not on a loop: an animation running forever behind a settings page is a
// frame clock nobody asked for.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── The demo line ─────────────────────────────────────────────────────────
    // Word durations, not just words: wordMotion() derives travel, pop and attack from
    // how HELD a word is, so a line of equal-length words would show one motion for all
    // of them and hide the thing the setting actually does. "Hold" and "night" are the
    // long ones on purpose.
    readonly property var demoLine: [
        { w: "Hold ",   d: 0.90 },
        { w: "on ",     d: 0.28 },
        { w: "to ",     d: 0.16 },
        { w: "the ",    d: 0.16 },
        { w: "night",   d: 1.10 },
        { w: ", ",      d: 0.20 },
        { w: "just ",   d: 0.24 },
        { w: "a ",      d: 0.14 },
        { w: "little ", d: 0.34 },
        { w: "longer",  d: 0.80 }
    ]
    readonly property string demoTranslation: "encore un peu de cette nuit"

    // Start times, accumulated once rather than per word per frame.
    readonly property var demoWords: {
        let t = 0
        return root.demoLine.map(function (u) {
            const out = { w: u.w, d: u.d, at: t }
            t += u.d
            return out
        })
    }
    readonly property real demoLength:
        root.demoWords.length === 0 ? 1
        : root.demoWords[root.demoWords.length - 1].at
          + root.demoWords[root.demoWords.length - 1].d

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰲹"
        title:     Translation.tr("Lyrics")
        titleTail: Translation.tr("& translation")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  (Lyrics.viaBridge ? "Spotify bridge"
                    : Lyrics.hasSynced   ? "Fallback lookup"
                    : "Nothing loaded")
                 + "  ·  translation " + (Config.lyricsTranslate ? "on" : "off")

        // ══ Motion ════════════════════════════════════════════════════════════
        Section {
            span:     2
            glyph:    "󰓞"
            title:    Translation.tr("Motion")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: Config.lyricsMotion <= 0.01 ? "Words stay still" : ""
            help:     Translation.tr("How far each word travels as it is sung — never the timing, which stays keyed to the vocal. Point at the line to play it.")

            PreviewStage {
                id: stage
                Layout.fillWidth: true
                Layout.preferredHeight: 116
                padding: Tokens.spacingLg
                // The line is opaque text on a dark ground, like the card it imitates;
                // a checkerboard behind it would just be noise under the words.
                checkered: false

                // Where the playhead is, in seconds along the demo line. One clock for
                // the whole line — the same shape the card uses, where every word reads
                // the card's position rather than running an animator each.
                property real clock: 0

                // Seconds, not grid columns — "span" means the latter everywhere else.
                readonly property real lineSpan: root.demoLength

                MouseArea {
                    id: stageHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: replayHold.restart()
                }

                // A one-shot hold, so moving the slider plays the line once and stops.
                Timer { id: replayHold; interval: 4200; repeat: false }

                SequentialAnimation {
                    running: Config.motionEnabled
                             && (stageHover.containsMouse || replayHold.running)
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: stage; property: "clock"
                        from: 0; to: stage.lineSpan
                        duration: Math.round(stage.lineSpan * 1000)
                        easing.type: Easing.Linear
                    }
                    PauseAnimation { duration: 700 }
                    // Back to unlit between passes, or the line would jump from fully
                    // sung to dark mid-frame.
                    ScriptAction { script: stage.clock = 0 }
                }

                Connections {
                    target: Config
                    function onLyricsMotionChanged() { replayHold.restart() }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Tokens.spacingSm

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0

                        Repeater {
                            model: root.demoWords

                            // One word, lit and lifted by the same numbers the real
                            // glyphs use: `rise` in pixels, `pop` as a scale, both
                            // scaled by the user's intensity inside wordMotion().
                            Item {
                                id: word
                                required property var modelData

                                readonly property var m:
                                    LyricMotion.wordMotion(word.modelData.d, Config.lyricsMotion)

                                // 0 before the word, 1 after it — where the voice is
                                // inside this word right now.
                                readonly property real p: {
                                    const x = (stage.clock - word.modelData.at) / word.modelData.d
                                    return x < 0 ? 0 : (x > 1 ? 1 : x)
                                }
                                // Travel is an arc: it swells on the attack and settles
                                // as the word is held, rather than staying lifted.
                                readonly property real arc:
                                    word.p <= 0 ? 0
                                  : word.p < 0.35 ? word.p / 0.35
                                  : Math.max(0, 1 - (word.p - 0.35) / 0.65)

                                width:  label.implicitWidth
                                height: label.implicitHeight

                                StyledText {
                                    id: label
                                    text: word.modelData.w
                                    variant: "title"
                                    y: -word.m.rise * word.arc * 3
                                    scale: 1 + word.m.pop * word.arc
                                    color: word.p > 0
                                           ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).fg, Colors.of(QsWindow.window).primary, word.arc * 0.6)
                                           : Colors.of(QsWindow.window).fgDim
                                }
                            }
                        }
                    }

                    // The translated line, when translation is on — the setting in the
                    // card beside this one, shown where it will actually appear.
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: Config.lyricsTranslate
                        text: root.demoTranslation
                        variant: "caption"
                        emphasis: "dim"
                    }
                }

                StyledText {
                    anchors.right:  parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.spacingSm
                    visible: !stageHover.containsMouse && !replayHold.running
                    text: Translation.tr("hover to play")
                    variant: "micro"
                    emphasis: "dim"
                }
            }

            // Scales the travel and the pop, never the timing, which stays keyed to
            // the vocal. A percentage would be a number pretending to be information.
            Fader {
                label: Translation.tr("Motion")
                accent: Colors.of(QsWindow.window).primary
                from: 0; to: 1; step: 0.05
                value: Config.lyricsMotion
                readout: Config.lyricsMotion <= 0.01 ? "Still"
                       : Config.lyricsMotion <= 0.40 ? "Subtle"
                       : Config.lyricsMotion <= 0.80 ? "Moderate"
                       : "Full"
                onCommit: function (v) { Config.lyricsMotion = v }
            }
        }

        // ══ Source ════════════════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰲹"
            title:    Translation.tr("Source")
            help:     Translation.tr("Which provider answered for the current track, and whether the shell may look lyrics up itself.")
            accent:   Colors.of(QsWindow.window).primary

            // ── Which source is actually in use ───────────────────────────────
            // "The lyrics are worse on this song" and "the bridge isn't running" look
            // identical from the card; telling them apart is why this row exists.
            SettingRow {
                label: Translation.tr("Right now")
                wrapDetail: true
                detail: {
                    if (!Lyrics.hasSynced && Lyrics.state !== "plain") {
                        // The same reasons the card shows, so the two can't disagree.
                        if (Lyrics.blockedReason === "connecting") return "Connecting to Spotify…"
                        if (Lyrics.blockedReason === "waiting")    return "Waiting for Spotify…"
                        if (Lyrics.blockedReason === "unanswered")
                            return "The Spotify bridge has nothing for this track — fallback is off"
                        return "Nothing loaded"
                    }
                    if (Lyrics.viaBridge)
                        return "Spotify bridge — " + Lyrics.provider
                             + (Lyrics.community ? ", community" : "") + ", per-syllable"
                    return "Fallback lookup" + (Lyrics.source ? " — " + Lyrics.source : "")
                         + (Lyrics.kind ? ", per-" + Lyrics.kind : "")
                }
            }

            // ── The fallback ─────────────────────────────────────────────────
            // Two reasons to turn this off: an outbound request per track carrying
            // artist, title and album; and word/line-level results where the bridge
            // is per-syllable, so a "successful" answer can be a downgrade.
            SettingRow {
                label: Translation.tr("Look up as a fallback")
                detail: Config.lyricsFallback ? "NetEase and LRCLIB" : "Off"
                help:   Translation.tr("Asks NetEase and LRCLIB when the Spotify bridge has nothing. It sends the artist, title and album.")
                wrapDetail: true
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.lyricsFallback
                    onToggled: Config.lyricsFallback = !Config.lyricsFallback
                }
            }
        }

        // ══ Translation ═══════════════════════════════════════════════════════
        // Off by default in a published config: the network fallback sends each line to
        // a third party. The tile is the switch; the card beside it only exists once
        // the switch is on, so nothing here is a control you can set and not use.
        QuickToggleTile {
            roomy:  true
            symbol: "translate"
            label:  Translation.tr("Translate lyrics")
            accent: Colors.of(QsWindow.window).primary
            active: Config.lyricsTranslate
            subLabel: !Config.lyricsTranslate ? "A line under each lyric"
                    : LyricsTranslate.backendUsed !== ""
                      ? "Via " + LyricsTranslate.backendUsed
                      : "On-device first, then network"
            onToggled: Config.lyricsTranslate = !Config.lyricsTranslate
        }

        Section {
            span:     2
            visible:  Config.lyricsTranslate
            glyph:    "󰗊"
            title:    Translation.tr("Translation")
            help:     Translation.tr("Which service translates, and its optional API key.")
            accent:   Colors.of(QsWindow.window).primary

            // The order and the cache toggle live on the Now Playing panel's
            // settings — one editor for the backend list, not two to keep in sync.
            SettingRow {
                label: Translation.tr("Backends")
                wrapDetail: true
                detail: (LyricsTranslate.state === "ready" && LyricsTranslate.backendUsed
                            ? "Now: " + LyricsTranslate.backendUsed
                              + (LyricsTranslate.lastCached ? " (cached)" : "") + "  ·  "
                            : "")
                      + LyricsTranslate.backends.join(" → ")
                      + (Config.lyricsTranslateCache ? "  ·  cached 7 days" : "  ·  cache off")
                      + "  ·  reorder from the Now Playing panel"
            }

            // Only while blocked — the same blocker() the media card reads.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: LyricsTranslate.blocker() !== ""
                text: LyricsTranslate.blocker()
                    + (LyricsTranslate.installHint ? "  (" + LyricsTranslate.installHint + ")" : "")
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }

            // ── DeepL key ────────────────────────────────────────────────────
            // Handed straight to scripts/lyrics-translate-credentials.py over stdin,
            // which writes it 0600. Never an argument, never written from QML, never
            // read back: this page only ever learns LyricsTranslate.hasDeeplKey.
            Divider {}

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: LyricsTranslate.hasDeeplKey
                    ? "DeepL key saved — a documented API rather than a scraped endpoint. Leave blank to keep it."
                    : "Optional DeepL key (free, no card) — a documented API instead of a scraped endpoint."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                InputField {
                    cornerRadius: implicitHeight / 2
                    id: deeplKeyField
                    Layout.fillWidth: true
                    secret: true
                    placeholder: LyricsTranslate.hasDeeplKey ? "•••••••••••••• saved" : "Paste your DeepL API key…"
                    onAccepted: function (v) {
                        if (v === "") return
                        LyricsTranslate.saveDeeplKey(v)
                        deeplKeyField.clear()
                    }
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Save")
                    variant: "primary"
                    accent: Colors.of(QsWindow.window).primary
                    enabled: deeplKeyField.text.length > 0
                    onActivated: { LyricsTranslate.saveDeeplKey(deeplKeyField.text); deeplKeyField.clear() }
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Remove")
                    variant: "ghost"
                    visible: LyricsTranslate.hasDeeplKey
                    onActivated: LyricsTranslate.removeDeeplKey()
                }
            }
        }
    }
}
