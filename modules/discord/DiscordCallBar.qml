import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── DiscordCallBar ────────────────────────────────────────────────────────────
// Discord's voice controls as a floating BAR. It was the overview's (top centre of its
// notification page, as OverviewDiscordCall); that page went on 2026-10-04 and the bar
// was kept here, on purpose, for later. The lock screen still shows it during a call.
// The sidebar's VoicePanel is the call's everyday home now.
//
//  ╭──────────────────────────────────────────────────────────────────────────╮
//  │ ◉  Rufss            │  (A)(B)  │  [󰍬][󰋋]   [󰨝][󰕧]        ╭──────╮       │
//  │    Direct call·17ms │          │                          │  󰏳  │       │
//  ╰──────────────────────────────────────────────────────────────────────────╯
//     identity            faces        audio     video          leave
//
// ── Horizontal, and sized to its content ─────────────────────────────────────
// One row: who you're with, then faces, then controls. The card takes exactly the width
// it needs and no more, so a two-person DM is a compact bar and a busy channel grows
// sideways rather than downward — a bar that fits above other content.
//
// ── The subtitle doubles as the hint line ────────────────────────────────────
// A horizontal bar has no room for a dedicated hint row, and adding one would undo the
// shape. So hovering anything — a face, a button — replaces the subtitle for as long as
// the pointer is there. One line, two jobs, no layout change: the bar never resizes
// under the pointer, which a second row of text would have made it do.
//
// ── It mimics Discord's LAYOUT, not Discord's palette ────────────────────────
// Colours are this shell's: `Colors.danger` for muted and for leave, `Colors.success`
// for a good connection and the speaking ring, the rest from the Material You palette
// the wallpaper produced. Hardcoding #5865F2 or #ED4245 would make this the one card in
// the shell that ignores the theme.
//
// ── Two of these buttons are not like the others ─────────────────────────────
// Mute, deafen and leave are real RPC — the state you see is Discord's own. SCREEN
// SHARE AND CAMERA ARE NOT IN DISCORD'S API AT ALL; they work by focusing Discord and
// injecting its keybind (scripts/discord-press.py). So they're drawn as actions rather
// than toggles — nothing reports their state back — and they say why in the hint line
// when they can't work.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation:    Tokens.elevationCard
    cornerRadius: Tokens.radiusXl      // the overview's shared island corner

    // Sized to content, both ways. The bar grows sideways as people join, and eases
    // rather than jumping — it sits at the top centre, so a width change moves BOTH
    // edges and an unanimated one reads as a flicker.
    implicitWidth:  (root.setupMode ? setup.implicitWidth  : bar.implicitWidth)
                  + Tokens.spacingXl * 2
    // Tighter top-to-bottom than side-to-side. Equal padding on a bar this wide reads
    // as slack: the horizontal gap has content either side of it doing work, the
    // vertical gap has nothing.
    implicitHeight: (root.setupMode ? setup.implicitHeight : bar.implicitHeight)
                  + Tokens.spacingLg * 2

    Behavior on implicitWidth {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    // ── Setup mode ────────────────────────────────────────────────────────────
    // Without credentials the helper can't reach Discord at all, so `inCall` is false
    // forever and a card gated only on that would never appear — leaving the feature
    // indistinguishable from one that's broken. Clears itself once you're set up.
    readonly property bool setupMode: !Discord.inCall && Discord.needsAttention

    // Where the per-user menu opens. Passed in from Overview.qml rather than declared
    // here: a menu parented into this card could only ever open within the card.
    property var contextMenu: null
    property string menuUserId: ""

    // ── Discord's red, hardcoded ──────────────────────────────────────────────
    // A DELIBERATE exception to the palette rule, at the user's request: the hangup
    // button is the one control here people recognise by colour before they read it,
    // and Discord's red is part of that recognition in a way a wallpaper-derived
    // `Colors.danger` isn't.
    //
    // Scoped to exactly this button and named, rather than sprinkled: everything else
    // on the bar — muted mic, muted badges, error text — still uses `Colors.danger` and
    // still follows the wallpaper. Reverting is a one-line change here.
    readonly property color discordRed:   "#ED4245"
    readonly property color discordRedFg: "#FFFFFF"   // fixed too; the red never changes

    // Same exception, same reasoning: the speaking ring is Discord's green before it is
    // anything else. `Colors.success` on a warm wallpaper lands somewhere between olive
    // and amber, which reads as a warning ring rather than "this person is talking".
    readonly property color discordGreen: "#23A55A"

    // ── May this card inject keystrokes? ──────────────────────────────────────
    // Screen share and camera are the two controls with no RPC command behind them —
    // they work by focusing Discord and typing its keybind (see scripts/discord-press.py).
    // That is fine from the overview and must NOT happen from the LOCKSCREEN, for a
    // reason worth spelling out: a session-lock surface holds the keyboard, so the
    // injected keystroke is not delivered to Discord at all. It is delivered to whatever
    // has focus — which on that surface is the password field.
    //
    // So this is not merely "it wouldn't work". It is "it would type a keybind into the
    // box you are about to type your password into", from a control reachable by someone
    // who has not authenticated. The lock passes false.
    //
    // Routed through the existing blocker mechanism rather than by hiding the buttons,
    // because that is already this card's contract for an unavailable control: disable
    // it and say why, never fail on click.
    property bool allowInjection: true

    readonly property bool canScreenShare: root.allowInjection && Discord.canPress(Discord.screenShareKey)
    readonly property bool canCamera:      root.allowInjection && Discord.canPress(Discord.cameraKey)

    readonly property string _injectionBlocker:
        "Not available from the lock screen — the keystroke would go to the password box"

    readonly property string shareBlocker:  !root.allowInjection ? root._injectionBlocker
                                                                : Discord.pressBlocker(Discord.screenShareKey)
    readonly property string cameraBlocker: !root.allowInjection ? root._injectionBlocker
                                                                : Discord.pressBlocker(Discord.cameraKey)

    // ── The hint ──────────────────────────────────────────────────────────────
    // Claimed on enter, released on exit. The ownership check matters because leaving
    // one target and entering the next fires in that order, and a blind clear would
    // wipe the incoming tip a frame after it set it.
    property string hoverTip: ""

    function setTip(on, tip) {
        if (on) root.hoverTip = tip
        else if (root.hoverTip === tip) root.hoverTip = ""
    }

    // ── Injection ─────────────────────────────────────────────────────────────
    // Close the overview FIRST. It holds WlrKeyboardFocus.Exclusive, so while it's up
    // the compositor gives it the keyboard and an injected keystroke never reaches
    // Discord. Closing it is a UI decision, which is why it happens here rather than in
    // the service. It's also the right UX: Go Live opens a source picker in Discord, so
    // you want to be there anyway.
    function press(spec) {
        // Belt as well as braces: the buttons are already disabled when injection is not
        // allowed, but this is the function that ends up typing into whatever holds the
        // keyboard, so it refuses on its own rather than trusting its callers.
        if (!root.allowInjection) return
        UiState.overviewOpen = false
        Discord.pressInDiscord(spec)
    }

    // The call iconography, as vector paths. See DiscordIcons.qml.
    DiscordIcons { id: ico }

    // ── The avatar cap ────────────────────────────────────────────────────────
    // Bounds the bar's WIDTH (it grows sideways now, so this is the axis that matters).
    // Beyond the cap the last slot becomes a "+N" chip rather than a face, so the chip
    // is counted in the budget instead of pushing the bar wider.
    readonly property int avatarSize: 56
    readonly property int maxAvatars: 6

    // Ring thickness, and the halo that sits just outside it. Named here because three
    // things have to agree: the border, the avatar's inlay (so the face isn't covered)
    // and the halo's negative margin. Changing one alone puts the ring off-centre.
    readonly property int ringWidth: 3
    readonly property int haloWidth: 3

    readonly property bool overflowing: Discord.users.length > root.maxAvatars
    readonly property var  shownUsers: root.overflowing
        ? Discord.users.slice(0, root.maxAvatars - 1)
        : Discord.users
    readonly property int  overflow: root.overflowing
        ? Discord.users.length - (root.maxAvatars - 1)
        : 0

    // ══ SETUP ═════════════════════════════════════════════════════════════════
    RowLayout {
        id: setup
        anchors.centerIn: parent
        spacing: Tokens.spacingMd
        visible: root.setupMode

        Rectangle {
            Layout.preferredWidth:  32
            Layout.preferredHeight: 32
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.16)

            MaterialIcon {
                anchors.centerIn: parent
                glyph: "󰍬"
                color: Colors.of(QsWindow.window).warning
                variant: "title"
            }
        }

        ColumnLayout {
            spacing: 0
            Layout.maximumWidth: 420

            StyledText {
                text: Discord.awaitingConsent ? "Authorize this shell in Discord"
                                              : "Discord not connected"
                variant: "title"
                font.bold: true
            }
            StyledText {
                Layout.fillWidth: true
                // Points at the settings page rather than the file path it used to
                // name. The path was accurate and useless — it told you where to type
                // JSON, not what to type. Settings → Discord has the fields, the steps
                // and the "why can't I use someone else's" answer.
                text: Discord.lastError !== "" ? Discord.lastError
                    : Discord.awaitingConsent
                        ? "Approve the prompt and this bar takes over."
                        : "Set it up in Settings → Discord"
                variant: "caption"
                color: Discord.lastError !== "" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                elide: Text.ElideRight
            }
        }

        BusyDot {
            visible: Discord.awaitingConsent
            running: Discord.awaitingConsent
            tint:    Colors.of(QsWindow.window).warning
        }
    }

    // ══ THE BAR ═══════════════════════════════════════════════════════════════
    RowLayout {
        id: bar
        anchors.centerIn: parent
        spacing: Tokens.spacingLg
        visible: !root.setupMode

        // ── Identity ──────────────────────────────────────────────────────────
        RowLayout {
            spacing: Tokens.spacingMd

            Rectangle {
                Layout.preferredWidth:  36
                Layout.preferredHeight: 36
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).alpha(root.qualityColor, 0.16)

                MaterialIcon {
                    anchors.centerIn: parent
                    glyph: "󰍬"
                    color: root.qualityColor
                    variant: "title"
                }

                // A quiet pulse while the voice connection is still being established —
                // the one moment the bar is telling you to wait rather than to act.
                SequentialAnimation on opacity {
                    running: Discord.quality === "connecting"
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.45; duration: Motion.pulse; easing.type: Motion.travel }
                    NumberAnimation { to: 1.0;  duration: Motion.pulse; easing.type: Motion.travel }
                }
            }

            ColumnLayout {
                spacing: 0

                // ── Sized to the text it actually has ──────────────────────────
                // This was a flat 200px, which stops the bar resizing under the pointer
                // but leaves a visible void before the first divider whenever the real
                // text is shorter — "Rufss" over "Direct call · 1:09 · 18ms" is nowhere
                // near 200.
                //
                // So it measures instead. Crucially it measures the SUBTITLE, never the
                // hint: hint strings are much longer, and binding to the live text would
                // make the block widen the moment the pointer touched a button — exactly
                // the jitter the fixed width existed to prevent. The hint elides into
                // whatever space the subtitle earned.
                //
                // Floor keeps the block from collapsing on a one-word call; ceiling stops
                // a long guild name from pushing the controls off-centre.
                readonly property int naturalWidth:
                    Math.ceil(Math.max(titleMetrics.advanceWidth, subtitleMetrics.advanceWidth))
                Layout.preferredWidth: Math.max(96, Math.min(220, naturalWidth))

                TextMetrics {
                    id: titleMetrics
                    font: titleText.font
                    text: titleText.text
                }
                TextMetrics {
                    id: subtitleMetrics
                    font: subtitleText.font
                    text: root.subtitle
                }

                StyledText {
                    id: titleText
                    Layout.fillWidth: true
                    text: root.title
                    variant: "body"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    id: subtitleText
                    Layout.fillWidth: true
                    text: root.hoverTip !== "" ? root.hoverTip : root.subtitle
                    variant: "caption"
                    color: root.hoverTip !== "" ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fgDim
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
            }
        }

        // Inset rather than full-bleed. Divider sets `Layout.fillHeight` itself when
        // vertical, which in a RowLayout stretches it to the tallest child — so the
        // fill has to be turned off explicitly for the hairline to stop short of the
        // bar's edges, which is what makes it read as a separator and not a seam.
        Divider {
            orientation: Qt.Vertical
            Layout.fillHeight: false
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
        }

        // ── Faces ─────────────────────────────────────────────────────────────
        Row {
            spacing: Tokens.spacingMd
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: root.shownUsers

                delegate: Item {
                    id: person
                    required property var modelData

                    readonly property bool speaking: person.modelData.speaking ?? false
                    readonly property bool isSelf:   person.modelData.isSelf   ?? false
                    readonly property bool muted:   (person.modelData.selfMute   ?? false)
                                                 || (person.modelData.serverMute ?? false)
                    readonly property bool deafened: person.modelData.selfDeaf ?? false

                    width:  root.avatarSize
                    height: root.avatarSize

                    // ── The halo ──────────────────────────────────────────────
                    // A second, translucent ring OUTSIDE the solid one. Discord's own
                    // speaking indicator is a single hairline, which at this size is easy
                    // to miss in peripheral vision on a busy page — the halo gives it
                    // presence without making the ring itself heavy enough to crowd the
                    // face. It's drawn first so the solid ring paints over its inner edge
                    // and the two read as one thick-to-thin falloff.
                    //
                    // Overflows the delegate by design; nothing here clips, and the Row's
                    // spacing is wider than the halo, so neighbours can't be overlapped.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -root.haloWidth
                        radius: width / 2
                        color: "transparent"
                        border.width: root.haloWidth
                        border.color: Colors.of(QsWindow.window).alpha(root.discordGreen, 0.32)

                        opacity: person.speaking ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }

                    // ── The speaking ring ─────────────────────────────────────
                    // Discord's green ring. Drawn as a border on the container so it can
                    // animate without relayout; the avatar inlays by the same amount so
                    // the ring never covers the face.
                    Rectangle {
                        id: ring
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

                        border.width: person.speaking ? root.ringWidth : 0
                        border.color: root.discordGreen

                        Behavior on border.width { NumberAnimation { duration: Motion.respond } }
                        Behavior on border.color { ColorAnimation  { duration: Motion.respond } }

                        // Whoever can't hear or be heard reads dimmer, so the row is
                        // legible at a glance without decoding the badge.
                        opacity: (person.muted || person.deafened) ? 0.5 : 1.0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                        // MASKED, not clipped. `clip` is rectangular — it knows nothing
                        // about `radius`, so a clipped avatar keeps its square corners
                        // and pokes out of the circle. Same fix as the album cover in
                        // OverviewNowPlaying, which carries the long-form warning.
                        Item {
                            anchors.fill: parent
                            anchors.margins: person.speaking ? root.ringWidth : 0

                            layer.enabled: true
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: faceMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }

                            Image {
                                id: face
                                anchors.fill: parent
                                source: person.modelData.avatar ?? ""
                                // 2× the drawn size for HiDPI, then mipmapped. Decoding
                                // at native resolution and point-sampling down is what
                                // makes a small avatar look soft.
                                sourceSize: Qt.size(root.avatarSize * 2, root.avatarSize * 2)
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                mipmap: true
                                visible: status === Image.Ready
                            }
                        }

                        Item {
                            id: faceMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "white"
                            }
                        }

                        // Initial, while the avatar loads or if it never does — a blank
                        // disc in a row of faces reads as a broken card.
                        StyledText {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: (person.modelData.name ?? "?").charAt(0).toUpperCase()
                            variant: "title"
                            color: Colors.of(QsWindow.window).fgDim
                        }
                    }

                    // ── Muted / deafened badge ────────────────────────────────
                    // Bottom-right, where Discord puts it. Deafened wins when both are
                    // true: it's the stronger statement of the two.
                    Rectangle {
                        visible: person.muted || person.deafened
                        anchors.right:  parent.right
                        anchors.bottom: parent.bottom
                        width:  20
                        height: 20
                        radius: height / 2
                        color: Colors.of(QsWindow.window).danger
                        // Rim in the card's own fill, so the badge reads as sitting on
                        // top of the avatar rather than punched out of it.
                        border.width: 2
                        border.color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard)

                        MaterialIcon {
                            anchors.centerIn: parent
                            glyph: person.deafened ? "󰟎" : "󰍭"
                            color: Colors.of(QsWindow.window).fgOnPrimary
                            variant: "caption"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.RightButton
                        cursorShape: person.isSelf ? Qt.ArrowCursor : Qt.PointingHandCursor

                        onEntered: root.setTip(true,  root.nameFor(person.modelData))
                        onExited:  root.setTip(false, root.nameFor(person.modelData))

                        // ── Per-user volume ───────────────────────────────────
                        // Presets rather than a slider: ContextMenu is a key-driven list
                        // and cannot host one. Discord's own control is a slider, so this
                        // is a deliberate reduction — the levels people actually use, one
                        // click each, rather than bending a component into a shape it
                        // doesn't have.
                        //
                        // Never on yourself: Discord has no per-user volume for your own
                        // account and SET_USER_VOICE_SETTINGS on it does nothing.
                        onClicked: function(mouse) {
                            if (!root.contextMenu || person.isSelf) return
                            const p = person.mapToItem(null, mouse.x, mouse.y)
                            root.menuUserId = person.modelData.id ?? ""
                            // A real per-person mute (SET_USER_VOICE_SETTINGS `mute`), not
                            // volume 0 — so unmuting brings back the level they had. The
                            // level they're at now carries a check.
                            const muted = person.modelData.mute ?? false
                            const vol = person.modelData.volume ?? 100
                            const level = v => ({ key: "u:" + v, label: v + "%",
                                                  glyph: vol === v ? "󰄬" : v < 100 ? "󰕿" : "󰕾" })
                            root.contextMenu.items = [
                                { key: "u:mute", glyph: muted ? "󰕾" : "󰝟",
                                  label: muted ? "Unmute for me" : "Mute for me" },
                                { separator: true },
                                level(50), level(100), level(150), level(200)
                            ]
                            root.contextMenu.openAt(p.x, p.y)
                        }
                    }
                }
            }

            // The ones that didn't fit, counted rather than dropped.
            Rectangle {
                visible: root.overflow > 0
                width:  root.avatarSize
                height: root.avatarSize
                radius: width / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

                StyledText {
                    anchors.centerIn: parent
                    text: "+" + root.overflow
                    variant: "body"
                    color: Colors.of(QsWindow.window).fgMuted
                }
            }
        }

        // Only reachable in the instant before the channel read lands — Discord's
        // participant list includes YOU, so an empty one is never "nobody else here".
        StyledText {
            visible: Discord.users.length === 0
            text: "…"
            variant: "title"
            color: Colors.of(QsWindow.window).fgDim
        }

        Divider {
            orientation: Qt.Vertical
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            Layout.alignment: Qt.AlignVCenter
        }

        // ══ CONTROLS ══════════════════════════════════════════════════════════
        // Grouped the way Discord groups them — audio, then video, then leave set apart
        // on its own. The gap between groups is what carries the resemblance; five
        // evenly spaced buttons read as a generic toolbar.
        Row {
            spacing: Tokens.spacingSm
            Layout.alignment: Qt.AlignVCenter

            CallButton {
                iconFill:   ico.micFill
                iconStroke: Discord.mute ? ico.micMutedStroke : ico.micStroke
                active: Discord.mute
                tip:    Discord.mute ? "Unmute" : "Mute"
                onActivated: Discord.toggleMute()
                onHoveredChanged: root.setTip(hovered, tip)
            }

            CallButton {
                iconFill:   ico.headphonesFill
                iconStroke: Discord.deaf ? ico.deafenedStroke : ""
                active: Discord.deaf
                tip:    Discord.deaf ? "Undeafen" : "Deafen"
                onActivated: Discord.toggleDeaf()
                onHoveredChanged: root.setTip(hovered, tip)
            }
        }

        Row {
            spacing: Tokens.spacingXs
            Layout.alignment: Qt.AlignVCenter

            CallButton {
                iconFill:   ico.screenShareFill
                iconStroke: ico.screenShareStroke
                enabled: root.canScreenShare
                // The blocker is computed by the service, which knows whether the tool
                // is missing, the window is missing, or the keybind is unset — three
                // different problems that used to collapse into "Discord isn't running".
                tip: root.shareBlocker !== "" ? root.shareBlocker
                                              : "Share screen — closes the overview"
                onActivated: root.press(Discord.screenShareKey)
                onHoveredChanged: root.setTip(hovered, tip)
            }

            CallButton {
                iconFill:   ico.cameraFill
                enabled: root.canCamera
                tip: root.cameraBlocker !== "" ? root.cameraBlocker
                                               : "Toggle camera — closes the overview"
                onActivated: root.press(Discord.cameraKey)
                onHoveredChanged: root.setTip(hovered, tip)
            }
        }

        // ── Leave ─────────────────────────────────────────────────────────────
        // Wider, filled, and set apart, like Discord's. It's the one irreversible
        // control here and it should not look like its neighbours.
        CallButton {
            Layout.leftMargin: Tokens.spacingSm
            Layout.alignment: Qt.AlignVCenter
            iconFill:     ico.hangupFill
            iconRotation: ico.hangupRotation
            active: true
            accent: root.discordRed
            fixedFg: root.discordRedFg
            wide:   true
            tip:    Translation.tr("Disconnect")
            onActivated: Discord.disconnect()
            onHoveredChanged: root.setTip(hovered, tip)
        }
    }

    // ── Derived ───────────────────────────────────────────────────────────────
    function nameFor(u) {
        return (u.name ?? "") + ((u.isSelf ?? false) ? "  (you)" : "")
    }

    readonly property color qualityColor: {
        switch (Discord.quality) {
        case "good":       return Colors.of(QsWindow.window).success
        case "bad":        return Colors.of(QsWindow.window).danger
        case "connecting": return Colors.of(QsWindow.window).warning
        default:           return Colors.of(QsWindow.window).fgMuted
        }
    }

    // What to call this call: Discord.callTitle (the voice panel says it too).
    readonly property string title: Discord.callTitle

    // ── The ticker ────────────────────────────────────────────────────────────
    // One second, and ONLY while there is a call to time — a clock nobody can see has
    // no business ticking, the same rule the overview's own clock follows.
    property double nowMs: Date.now()

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: Discord.inCall && Discord.callStartedAt > 0
        onTriggered: root.nowMs = Date.now()
    }

    readonly property string subtitle: {
        if (Discord.lastError !== "") return Discord.lastError

        const where = Discord.guildName !== "" ? Discord.guildName
                    : Discord.quality === "connecting" ? "Connecting…"
                    : "Direct call"

        const bits = [where]
        const dur = Discord.durationText(root.nowMs)
        if (dur !== "")        bits.push(dur)
        if (Discord.ping > 0)  bits.push(Discord.ping + "ms")
        return bits.join(" · ")
    }

    // The menu is shared with the dock, so this card must only answer for keys it
    // opened — hence the `u:` prefix and the menuUserId guard.
    Connections {
        target: root.contextMenu
        enabled: root.contextMenu !== null

        function onTriggered(key) {
            if (!key.startsWith("u:") || root.menuUserId === "") return
            if (key === "u:mute") {
                const u = Discord.userById(root.menuUserId)
                Discord.setUserMute(root.menuUserId, !(u?.mute ?? false))
            } else {
                Discord.setUserVolume(root.menuUserId, parseInt(key.substring(2), 10))
            }
            root.menuUserId = ""
        }
    }

    // ── The call button ───────────────────────────────────────────────────────
    // Discord's squircle, not the shell's pill. PanelButton is still the right base —
    // variants, hover colours and the disabled opacity ramp all come from it — but the
    // shape is Discord's: a rounded square, wider for leave.
    //
    // `tip` is surfaced by the subtitle line, not a tooltip: this shell contains zero
    // QtQuick.Controls (see Scrollbar.qml, which says so and explains why). `hovered`
    // is exported so the use site can drive that line — an inline component is its own
    // type and can't reach the enclosing file's ids.
    component CallButton: PanelButton {
        property bool active: false
        property bool wide: false
        property string tip: ""

        // SVG path data rather than PanelButton's `glyph`. Everything else about the
        // button — variants, hover colours, the disabled opacity ramp — is inherited;
        // only the mark inside it is drawn differently. PanelButton renders nothing
        // when both `glyph` and `label` are empty, so the icon simply sits in the
        // space its content would have occupied, and no shared component had to grow
        // a vector-icon mode for one caller.
        property string iconFill: ""
        property string iconStroke: ""
        property real iconRotation: 0

        // Set when the fill is a fixed colour rather than a palette one, so the mark on
        // top of it can't be derived from the palette either — `Colors.fgOnPrimary`
        // tracks the wallpaper and would eventually land dark-on-red.
        property color fixedFg: "transparent"
        readonly property bool hasFixedFg: fixedFg.a > 0

        readonly property bool hovered: hh.hovered

        implicitHeight: 46
        implicitWidth:  wide ? 72 : 48
        radius: Tokens.radiusPill

        variant: active ? "primary" : "normal"
        accent:  active ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
        glyphTint: hasFixedFg ? fixedFg
                 : active      ? Colors.of(QsWindow.window).fgOnPrimary
                               : Colors.of(QsWindow.window).fgMuted

        VectorIcon {
            anchors.centerIn: parent
            fillPath:   parent.iconFill
            strokePath: parent.iconStroke
            rotation:   parent.iconRotation
            color:      parent.glyphTint
            size:       22
        }

        HoverHandler { id: hh }
    }
}
