pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── HudVoice ──────────────────────────────────────────────────────────────────
// Over a game: who is in your Discord call, as faces that ring while they talk, and the
// name of whoever is talking. Compact on purpose — the overview's voice card is where you
// mute, deafen and leave. services/Discord.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root
    spacing: Tokens.spacingSm

    readonly property bool live: Discord.enabled && Discord.inCall
    readonly property var talking: Discord.users.filter(u => u.speaking).map(u => u.name)

    Row {
        visible: root.live
        spacing: Tokens.spacingSm
        Repeater {
            model: ScriptModel {
                values: Discord.users.slice(0, 8)
                objectProp: "id"
            }
            HudFace {
                required property var modelData
                person: modelData
                size: Tokens.iconXl
            }
        }
    }
    StyledText {
        Layout.maximumWidth: Tokens.sideCardUnit * 5
        text: !root.live ? Translation.tr("Not in a call")
            : root.talking.length > 0 ? root.talking.join(", ")
            : Discord.channelName
        variant: "caption"
        emphasis: root.talking.length > 0 ? "normal" : "dim"
        elide: Text.ElideRight
    }
}
