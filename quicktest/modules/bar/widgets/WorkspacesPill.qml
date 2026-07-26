import QtQuick
import Quickshell.Hyprland
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── WorkspacesPill ────────────────────────────────────────────────────────────
// Five workspace dots, paging between 1–5 and 6–10 as the focused workspace
// crosses the boundary. The focused dot stretches into a numbered lozenge.
//
// Colors follow the accent contract: the focused workspace is `primary`, because
// it is the active/interactive one. A workspace occupied on ANOTHER monitor is
// `focus` — you're being pointed at where something is, not offered an action.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var monitor: null

    // ── accent ────────────────────────────────────────────────────────────────
    // The dots are a RAMP of one colour, not four colours: focused is the accent at
    // full strength, occupied at 30%, empty at 10%. Colors.ws* encode exactly that ramp
    // over `primary`, so taking the accent and re-deriving the ramp from it keeps the
    // relationship intact at any accent — which is why this doesn't just repoint
    // wsFocused and leave the other two pointing at primary.
    //
    // `isOnOther` deliberately stays `focus` and is NOT part of the ramp. It means
    // "this workspace is live on your other monitor" — a different fact, not a
    // different intensity of the same one.
    property color accent: Colors.primary

    readonly property int currentWs: monitor?.activeWorkspace?.id ?? 1
    readonly property int wsStart:   currentWs <= 5 ? 1 : 6

    implicitWidth:  dots.implicitWidth + Tokens.pillPadding * 2
    implicitHeight: Tokens.pillHeight

    // The inset pill every bar control now sits in. Nested elevation: its border
    // has to hold its own against the GROUP pill's fill behind it, not against a
    // wallpaper.
    Surface {
        anchors.fill: parent
        elevation:    Tokens.elevationNested
        squareMode:   Config.barShape
        cornerRadius: Config.barRoundness
    }

    Row {
        id: dots
        anchors.centerIn: parent
        spacing: Tokens.spacingMd

        Repeater {
            model: 5

            Rectangle {
                id: dot
                required property int index

                readonly property int  wsId:       root.wsStart + dot.index
                readonly property var  ws:         Hyprland.workspaces.values.find(w => w.id === dot.wsId)
                readonly property bool isFocused:  root.currentWs === dot.wsId
                readonly property bool isOccupied: dot.ws !== undefined && !dot.isFocused
                readonly property bool isOnOther:  dot.isOccupied && dot.ws.monitor !== root.monitor

                // The dot is a graphic, so it follows the ICON scale — and it has to,
                // because the numeral inside it scales too. Scaling the digit alone would
                // push it straight out of a 10px circle at anything above 1.2×.
                width:  Math.round((isFocused ? 26 : 10) * Config.barIconScale)
                height: Math.round(10 * Config.barIconScale)
                radius: Config.barShape ? 2 : height / 2

                color: dot.isFocused  ? root.accent
                     : dot.isOnOther  ? Colors.alpha(Colors.focus, 0.90)
                     : dot.isOccupied ? Colors.alpha(root.accent, 0.30)
                     :                  Colors.alpha(root.accent, 0.10)

                Behavior on width  { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on color  { ColorAnimation  { duration: Motion.fast } }

                // Was a raw `font.pixelSize: 7` on a bare Text — the type scale had
                // nothing this small, so it invented a size and skipped StyledText
                // entirely. Scales with the dot, not with the clock: this is part of the
                // graphic.
                StyledText {
                    anchors.centerIn: parent
                    text:      dot.wsId
                    visible:   dot.isFocused || dot.isOccupied
                    color:     Colors.fgOnPrimary
                    variant:   "micro"
                    sizeScale: Config.barIconScale
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // Through the service, not a hand-rolled dispatch string. Hyprland
                    // silently drops a dispatch with an unrecognised key, so a second
                    // copy of this syntax is a second thing that can rot without ever
                    // saying so.
                    onClicked: Hypr.focusWorkspace(dot.wsId)
                }
            }
        }
    }
}
