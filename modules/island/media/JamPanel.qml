pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"

// ── JamPanel ──────────────────────────────────────────────────────────────────
// Spotify's Jam, as a plate of the queue (the mixer's and wallpaper page's plate: a section tone, a shape badge, a title
// and a note, folded away by default). The badge holds the host's picture; the note says who is listening. Opened: Invite
// (the link to copy), End or Leave, the host's two switches, and the listeners, each removable by the host. Every change is
// Spotify's own session call, sent by the extension (SpotifyBridge.queueJam / queueJamSet).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    property color accent: root.palette.primary
    property color ink: root.palette.fg
    property color muted: root.palette.fgMuted

    readonly property var jam: SpotifyBridge.queue ? SpotifyBridge.queue.jam : null
    readonly property bool inJam: root.jam !== null
    readonly property bool host: root.inJam && root.jam.youHost
    readonly property var members: root.inJam ? root.jam.members : []
    readonly property var owner: {
        for (let i = 0; i < root.members.length; i++) if (root.members[i].host) return root.members[i]
        return null
    }
    readonly property string link: root.jam ? root.jam.link : ""
    property bool inviting: false
    // Folded by default: the plate says who is listening; the controls are one tap away.
    property bool folded: true
    SpringValue { id: foldK; target: root.folded ? 0 : 1; spec: Motion.springSpatial; epsilon: 0.002 }

    visible: SpotifyBridge.queue !== null
    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusCard
    color: root.palette.section

    // A round picture, or the initial when there is none.
    component Avatar: Item {
        id: av
        property string src: ""
        property string letter: ""
        property int px: Tokens.iconLg
        property bool ring: false
        implicitWidth: av.px
        implicitHeight: av.px
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.palette.plate
            border.width: av.ring ? Tokens.borderWidth * 2 : 0
            border.color: root.accent
            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: av.ring ? Tokens.borderWidth * 2 : 0
                radius: width / 2
                color: "transparent"
                Image {
                    anchors.fill: parent
                    visible: av.src !== ""
                    source: av.src
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(av.px * 2, av.px * 2)
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: av.src === ""
                    text: av.letter
                    variant: "micro"
                    font.weight: Font.Bold
                    color: root.ink
                }
            }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingSm

        // ── The title row: badge, title and note, the listeners, the fold ─────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            Item {
                Layout.preferredWidth: Tokens.iconXl
                Layout.preferredHeight: Tokens.iconXl
                Layout.alignment: Qt.AlignVCenter
                MorphShape {
                    anchors.fill: parent
                    shape: root.inJam ? "sunny" : "cookie9"
                    spec: Motion.springSpatialFast
                    fillColor: root.inJam ? root.accent : root.palette.plate
                }
                Avatar {
                    anchors.centerIn: parent
                    visible: root.inJam
                    px: Tokens.iconLg
                    src: root.owner ? root.owner.image : ""
                    letter: root.owner ? root.owner.name.charAt(0).toUpperCase() : ""
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: !root.inJam
                    name: "group"
                    fill: 1
                    font.pixelSize: Tokens.iconMd
                    color: root.palette.fgOnPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: !root.inJam ? Translation.tr("Listen together")
                        : Translation.tr("%1's Jam").arg(root.owner ? root.owner.name : "")
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: root.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: !root.inJam ? Translation.tr("Friends can join from a link")
                        : root.host ? Translation.tr("You are hosting · %1 listening").arg(root.members.length)
                        : Translation.tr("%1 listening").arg(root.members.length)
                    variant: "micro"
                    color: root.muted
                    elide: Text.ElideRight
                }
            }

            // Who is listening, as small pictures, overlapping.
            Row {
                Layout.alignment: Qt.AlignVCenter
                visible: root.inJam
                spacing: -Tokens.spacingSm
                Repeater {
                    model: root.members
                    delegate: Avatar {
                        required property var modelData
                        required property int index
                        visible: index < 4
                        src: modelData.image
                        letter: modelData.name.charAt(0).toUpperCase()
                        ring: modelData.host
                        px: Tokens.iconLg
                        HoverTip { text: modelData.name + (modelData.host ? " · " + Translation.tr("host") : "") }
                    }
                }
            }

            ChipButton {
                visible: !root.inJam
                symbol: "group"
                label: Translation.tr("Start")
                labelWeight: Font.Bold
                tint: root.accent
                onActivated: SpotifyBridge.queueJam("start")
            }
            ChipButton {
                visible: root.inJam
                symbol: "keyboard_arrow_down"
                rotation: root.folded ? -90 : 0
                Behavior on rotation { NumberAnimation { duration: Motion.standard } }
                tint: root.accent
                Accessible.name: root.folded ? Translation.tr("Show the Jam") : Translation.tr("Fold the Jam")
                onActivated: root.folded = !root.folded
            }
        }

        // ── The body: folds on the spring ─────────────────────────────────────
        Item {
            id: bodyBox
            Layout.fillWidth: true
            Layout.preferredHeight: foldK.value * bodyCol.implicitHeight
            visible: root.inJam && foldK.value > 0.005
            clip: foldK.value < 0.995

            ColumnLayout {
                id: bodyCol
                width: bodyBox.width
                spacing: Tokens.spacingSm
                opacity: foldK.value

                // Invite and leave, as chips.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    ChipButton {
                        symbol: "add_link"
                        label: Translation.tr("Invite")
                        tint: root.accent
                        on: root.inviting
                        onActivated: root.inviting = !root.inviting
                    }
                    Item { Layout.fillWidth: true }
                    ChipButton {
                        symbol: "logout"
                        label: root.host ? Translation.tr("End") : Translation.tr("Leave")
                        tint: root.accent
                        onActivated: SpotifyBridge.queueJam(root.host ? "end" : "leave")
                    }
                }

                // The link, to copy. Wraps and elides; the copy chip keeps its place.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: root.inviting
                    spacing: Tokens.spacingSm
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.link !== "" ? root.link : Translation.tr("Getting the link…")
                        variant: "micro"
                        color: root.muted
                        elide: Text.ElideMiddle
                    }
                    ChipButton {
                        symbol: "content_copy"
                        label: Translation.tr("Copy")
                        tint: root.accent
                        enabled: root.link !== ""
                        onActivated: Quickshell.execDetached(["wl-copy", root.link])
                    }
                }

                // The host's two switches.
                Repeater {
                    model: root.host ? [
                        { key: "queueOnly", label: Translation.tr("Let others change what's playing"), on: root.jam ? !root.jam.queueOnly : false },
                        { key: "volume",    label: Translation.tr("Let others change the volume"),      on: root.jam ? root.jam.volumeControl : false }
                    ].filter(t => t.key !== "volume" || (root.jam && root.jam.volumeAvailable)) : []
                    delegate: RowLayout {
                        id: setting
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd
                        StyledText {
                            Layout.fillWidth: true
                            text: setting.modelData.label
                            variant: "caption"
                            color: root.ink
                            wrapMode: Text.WordWrap
                        }
                        Toggle {
                            accent: root.accent
                            checked: setting.modelData.on
                            onToggled: root.setting(setting.modelData.key)
                        }
                    }
                }

                // The listeners; the host can remove any but themselves.
                Repeater {
                    model: root.host ? root.members : []
                    delegate: RowLayout {
                        id: listener
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: !modelData.you
                        spacing: Tokens.spacingSm
                        Avatar {
                            src: listener.modelData.image
                            letter: listener.modelData.name.charAt(0).toUpperCase()
                            px: Tokens.iconLg
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: listener.modelData.name
                            variant: "caption"
                            color: root.ink
                            elide: Text.ElideRight
                        }
                        ChipButton {
                            symbol: "close"
                            tint: root.accent
                            Accessible.name: Translation.tr("Remove %1 from the Jam").arg(listener.modelData.name)
                            onActivated: SpotifyBridge.queueJamSet("remove", false, listener.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // The host's two switches. The value is the NEW "let others change it" state.
    function setting(key) {
        if (key === "queueOnly") SpotifyBridge.queueJamSet("queueOnly", root.jam ? root.jam.queueOnly : true)
        else SpotifyBridge.queueJamSet("volume", root.jam ? !root.jam.volumeControl : true)
    }
}
