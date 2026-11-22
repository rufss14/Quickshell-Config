import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── ClockPill ─────────────────────────────────────────────────────────────────
// Digital time (with seconds) over the date, and — once a location is set in
// Config.weatherPlace/Lat/Lon — the current temperature beside it. Click opens
// the clock panel.
//
// ── Takes over for a notification ─────────────────────────────────────────────
// While an island or bar panel is open the toast deck would collide with it, so the
// notification comes here instead (Notifications.glance): the pill narrows or widens to the
// app's icon and the title, then returns to the clock. Click opens the notification centre.
// `monitorName` is the screen this bar is on; the service delivers to the focused one.
//
// Was an analog face + "ddd, MMM dd" + "HH:mm" in a row. Replaced on request
// with a bigger digital readout; the analog Canvas is gone with it rather than
// kept behind a toggle nobody asked for.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color accent: Colors.of(QsWindow.window).primary

    property bool active: false
    // The bar's hero (Config.moduleHero; BarGroupRow sets it): its chip is primaryContainer,
    // so the text goes to the colour made for that ground.
    property bool hero: false
    readonly property color _onHero: Colors.of(QsWindow.window).fgOnPrimaryContainer
    signal toggled()
    signal noticeClicked(string kind)

    property string monitorName: ""

    // The notification on this bar, if any. `held` outlives it so the pill fades the text out
    // instead of blanking it as the service clears it.
    readonly property var glance: Notifications.glance?.monitor === root.monitorName ? Notifications.glance : null
    readonly property bool noticeOn: root.glance !== null
    property var held: null
    readonly property string noticeKind: root.held?.kind ?? ""
    readonly property string noticeIconPath: root.held?.icon ?? ""
    readonly property string noticePreview: root.held?.preview ?? ""
    // Two lines in a pill's height: the line boxes sit closer than a paragraph's, so the lower line's
    // descenders stay inside the pill.
    readonly property real lineTight: 0.86
    readonly property int noticeExt: Math.round(Tokens.fontTitle * Config.barIconScale)
    // A copied picture: a little wider than tall, a pill's height less its gaps.
    readonly property int previewH: Config.barPillHeight - Tokens.spacingMd * 2
    readonly property int previewW: Math.round(root.previewH * 1.5)
    // The notice stays near the clock's own width, whatever it says: the text elides into what the
    // icon and the picture leave of that.
    readonly property int noticeCap: Math.ceil(content.implicitWidth * 1.15)
    readonly property int textCap: Math.max(Tokens.spacingXl * 4,
        root.noticeCap - root.noticeExt - Tokens.spacingSm
        - (root.noticePreview !== "" ? root.previewW + Tokens.spacingSm : 0))
    onGlanceChanged: if (root.glance) root.held = root.glance

    implicitWidth:  pill.width
    implicitHeight: Config.barPillHeight

    readonly property date now: Clock.now

    // Seconds tick, for the same reason the old analog face needed it: the
    // shell's shared clock only ticks once a minute unless something holds it
    // open for a face that shows seconds. Weather is refcounted the same way
    // (services/Weather.qml) — a no-op if Config.weatherPlace is unset.
    Component.onCompleted:   { Clock.acquireSeconds(); Weather.acquire(); root._rehold() }
    Component.onDestruction: { Clock.releaseSeconds(); Weather.release(); Notifications.releaseGlance(root._acquired) }

    // Offered to the notifications of the output the bar is on, and to another's if it moves.
    property string _acquired: ""
    function _rehold() {
        if (root._acquired === root.monitorName) return
        Notifications.releaseGlance(root._acquired)
        root._acquired = root.monitorName
        Notifications.acquireGlance(root._acquired)
    }
    onMonitorNameChanged: root._rehold()

    IconButton {
        id: pill
        container: false
        height: Config.barPillHeight
        width:  Math.ceil(root.noticeOn ? notice.implicitWidth : content.implicitWidth) + Tokens.pillPadding * 2
        clip:   true
        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        active:     root.active
        // Time over date fills the pill: an underline inside it struck through the date.
        markGap:    -(Tokens.borderChrome + Tokens.spacingXs)
        onClicked: {
            if (!root.noticeOn) { root.toggled(); return }
            const g = root.held
            Notifications.clearGlance()
            // A Claude event goes to its session's terminal, as the peek's "Go to it" does.
            if (g?.kind === "claude") ClaudeSessions.focus(g.pid)
            else root.noticeClicked(g?.kind ?? "notification")
        }

        // The notification: an icon, a small picture when there is one, the title and a short message.
        // Fades with the width, so the clock and the notice never overlap between the two sizes.
        RowLayout {
            id: notice
            anchors.centerIn: parent
            spacing: Tokens.spacingSm
            opacity: root.noticeOn ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }

            // Claude's own events carry its animated mark (a sprite sheet), warning-coloured when a session needs you.
            ClaudeBurst {
                Layout.alignment: Qt.AlignVCenter
                visible: root.noticeKind === "claude"
                Layout.preferredWidth: root.noticeExt
                Layout.preferredHeight: root.noticeExt
                playing: root.noticeOn && root.noticeKind === "claude"
                tint: root.held?.needs ? Colors.of(QsWindow.window).warning
                    : root.hero ? root._onHero : root.accent
            }
            // The app's icon, or the event's own symbol (a copy's clipboard), or the bell.
            Image {
                id: noticeIcon
                Layout.alignment: Qt.AlignVCenter
                visible: root.noticeKind === "notification" && root.noticeIconPath !== "" && status !== Image.Error
                source: root.noticeIconPath
                sourceSize: Qt.size(root.noticeExt, root.noticeExt)
                Layout.preferredWidth: root.noticeExt
                Layout.preferredHeight: root.noticeExt
                fillMode: Image.PreserveAspectFit
                smooth: true
                layer.enabled: Config.colorizeIcons
                layer.effect: MonoIconEffect {}
            }
            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                visible: root.noticeKind !== "claude"
                         && !(root.noticeKind === "notification" && root.noticeIconPath !== "" && noticeIcon.status !== Image.Error)
                name: root.held?.symbol || "notifications"
                color: root.hero ? root._onHero : root.accent
                font.pixelSize: root.noticeExt
            }
            // A copied picture, small. The slot is kept while it loads and the picture fades in.
            ClippingRectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: root.noticePreview !== ""
                Layout.preferredWidth: root.previewW
                Layout.preferredHeight: root.previewH
                radius: Tokens.radiusXs
                color: Colors.of(QsWindow.window).surfaceHigh
                Image {
                    anchors.fill: parent
                    source: root.noticePreview
                    sourceSize.width: root.previewW * 2
                    fillMode: Image.PreserveAspectCrop
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                }
            }
            // The title, and under it a short message when the notification has one: the clock's own two lines.
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: root.textCap
                spacing: 0
                BarLabel {
                    Layout.fillWidth: false
                    Layout.maximumWidth: root.textCap
                    lineHeight: root.lineTight
                    lineHeightMode: Text.ProportionalHeight
                    text: root.held?.title ?? ""
                    elide: Text.ElideRight
                    color: root.hero ? root._onHero : Colors.of(QsWindow.window).fg
                }
                StyledText {
                    Layout.fillWidth: false
                    Layout.maximumWidth: root.textCap
                    visible: (root.held?.detail ?? "") !== ""
                    lineHeight: root.lineTight
                    lineHeightMode: Text.ProportionalHeight
                    text: root.held?.detail ?? ""
                    variant: "micro"
                    sizeScale: Config.barFontScale
                    elide: Text.ElideRight
                    color: root.hero ? Colors.of(QsWindow.window).alpha(root._onHero, 0.78)
                                     : Colors.of(QsWindow.window).fgDim
                }
            }
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: Tokens.spacingMd
            opacity: root.noticeOn ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }

            Column {
                id: dateTimeColumn
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                BarLabel {
                    text: Qt.formatDateTime(root.now, "HH:mm:ss")
                    // "display" (Tokens.fontDisplay) was sized for a face on its
                    // own, not a line sharing the pill's fixed height with a date
                    // underneath it — that's what grew the whole pill. "label" is
                    // the biggest variant two stacked lines actually fit inside
                    // Config.barPillHeight at. BarLabel's tabular digits keep the
                    // seconds from shifting the chip's width every tick.
                    color: root.hero ? root._onHero : root.accent
                }
                StyledText {
                    text: Qt.formatDateTime(root.now, "dddd, MMMM d")
                    variant: "micro"
                    sizeScale: Config.barFontScale
                    color: root.hero ? Colors.of(QsWindow.window).alpha(root._onHero, 0.78)
                                     : Colors.of(QsWindow.window).fgDim
                }
            }

            // Hidden until a location is set — Weather.hasLocation is false by
            // default and there's no settings page wired up for it yet, so this
            // stays invisible on an untouched config rather than showing "—".
            //
            // A plain Item, sized to the full two-line block, with the actual row
            // CENTRED inside it — rather than anchoring the row itself straight to
            // `content`'s vertical centre. Both should land the same place, but the
            // row is shorter than the clock's two lines, and `anchors.verticalCenter`
            // on a direct child of a Row positioner sitting next to a taller sibling
            // wasn't actually landing on centre. Doing it one level down, inside an
            // ordinary Item, removes any question of how Row treats a sibling's own
            // cross-axis anchor.
            Item {
                width:  weatherRow.implicitWidth
                height: dateTimeColumn.height
                visible: Weather.ready && Weather.hasLocation

                Row {
                    id: weatherRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs

                    // Icon and text differ in font size ("title"+iconScale vs "body"), so
                    // top-aligning them (Row's default) left the shorter temperature text
                    // sitting high with dead space under it, out of line with the icon.
                    // Centering both against the row itself lines them up regardless of
                    // which one is taller.
                    // The font's weather symbol (Weather.symbol — drawn outlined, its note says
                    // why), in the same tint the Fluent icon wore — or, as the hero, the chip's own
                    // text colour: `info` on primaryContainer all but vanished (2026-10-31).
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name:  Weather.symbol(Weather.code)
                        fill:  0
                        font.pixelSize: Math.round(Tokens.fontTitle * Config.barIconScale)
                        color: root.hero ? root._onHero : Colors.of(QsWindow.window).info
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }
                    BarLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.temp(Weather.tempC) + Weather.unit
                        color: root.hero ? root._onHero : Colors.of(QsWindow.window).fg
                    }
                }
            }
        }
    }
}
