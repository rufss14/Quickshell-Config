import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── NetworkBrowser ────────────────────────────────────────────────────────────
// "Show me the networks and let me join one." Everything between the header and
// the edge of the card: connection status, the password prompt, the hidden-network
// form, the list itself, and the row that does the connecting and forgetting.
//
// ── Why it isn't just part of WifiPanel any more ──────────────────────────────
// The bar's panel and the settings page both need exactly this, and they need it to
// behave identically — a second copy of a network list is a second copy of the
// password flow, the connecting state, and the signal-bar maths, drifting apart one
// fix at a time. What the two surfaces genuinely differ on is what surrounds this:
// the panel is a quick "join something now", while the page also carries the durable
// settings a transient popup has no business holding.
//
// ── It owns the scan refcount, and that is deliberate ─────────────────────────
// Scanning is acquired for exactly as long as one of these exists. That works because
// this component's lifetime IS the "is anyone looking at a list of access points"
// signal — which is precisely the job WifiPanel's own lifetime used to do, back when
// the list could only appear in one place. Move the refcount up to the callers and
// every future caller has to remember to do it; leave it here and none of them can
// forget. Two browsers open at once is fine — that's what refcounting is for.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // How many rows before the list starts scrolling. The panel is a popup and wants
    // to stay small; a settings page has the room to show more.
    property int maxRows: 5

    // Hide the IP on the connected row. Lives here because NetworkRow renders it, but
    // it's the surrounding header that offers the eye toggle — so it's public.
    property bool ipBlurred: true

    Component.onCompleted:   Net.acquireScan()
    Component.onDestruction: Net.releaseScan()

    // The content column reports its height; the root just carries it. Same shape
    // the panel uses, and the reason is the same one written up there: this is
    // top-anchored rather than filled, so a card animating its height around it
    // doesn't re-lay-out every child on every frame of the animation.
    implicitHeight: col.implicitHeight

    // ── Local UI state ────────────────────────────────────────────────────────
    // Everything here is presentation-only. Network state lives in the service.
    property var  pendingNetwork: null
    property bool passwordMode:   false
    property bool hiddenMode:     false
    property bool showPassword:   false

    // The list sizes to its contents, up to `maxRows` rows, then scrolls.
    //
    // I briefly pinned this to a fixed 5 rows to stop the panel resizing as access
    // points streamed in — but that was treating a symptom, and it left the panel
    // mostly empty space when you only have two networks. The resize was never the
    // problem: resizing the WINDOW was (see PanelHost). The window is fixed now, so
    // the card can grow and shrink to fit its content freely and cheaply.
    readonly property int rowHeight: 62
    readonly property int listHeight:
        (!Net.wifiEnabled || Net.networks.length === 0)
            ? 88                                                     // empty state
            : Math.min(Net.networks.length, root.maxRows) * rowHeight

    function askPassword(network) {
        root.pendingNetwork = network
        root.passwordMode   = true
        Net.clearError()
    }

    function doConnect() {
        if (!root.passwordMode) return
        const psk = passField.text
        passField.text = ""
        root.passwordMode = false
        Net.connect(root.pendingNetwork, psk)
    }

    // Clicking a network: connect if it's known or open, otherwise ask.
    function activate(network) {
        if (network.connected) { network.disconnect(); return }
        if (Net.needsPassword(network)) root.askPassword(network)
        else                            Net.connect(network)
    }

    onPasswordModeChanged: if (root.passwordMode) Qt.callLater(() => passField.forceActiveFocus())
    onHiddenModeChanged:   if (root.hiddenMode)   Qt.callLater(() => hiddenSsidField.forceActiveFocus())

    function doHiddenConnect() {
        const ssid = hiddenSsidField.text.trim()
        if (ssid === "") return
        const psk = hiddenPassField.text
        hiddenSsidField.text = ""
        hiddenPassField.text = ""
        root.hiddenMode = false
        // A hidden network isn't in the scan list; Net creates the connection by name,
        // with the passphrase kept off the command line (Net.connectHidden).
        Net.connectHidden(ssid, psk)
    }

    ColumnLayout {
        id: col
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        spacing: Tokens.spacingMd + 2

        // ── Status (error / connecting) ───────────────────────────────────────────
        Rectangle {
            id: statusBar
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.sideCardUnit
            radius: Tokens.radiusCard
            visible: Net.lastError !== "" || Net.connecting !== null

            readonly property bool isError: Net.lastError !== ""

            color: statusBar.isError ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.16) : Colors.of(QsWindow.window).section

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingLg
                anchors.rightMargin: Tokens.spacingMd + 2
                spacing: Tokens.spacingMd

                MaterialIcon {
                    glyph:  statusBar.isError ? "󰅙" : "󰤨"
                    color: statusBar.isError ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).focus
                    variant: "body"
                }
                StyledText {
                    Layout.fillWidth: true
                    text: statusBar.isError
                        ? Net.lastError
                        : "Connecting to " + (Net.connecting?.name ?? "") + "…"
                    variant: "caption"
                    opacity: 0.85
                    elide: Text.ElideRight
                }
                PanelButton {
                    variant: "ghost"
                    visible: statusBar.isError
                    glyph:   "󰅖"
                    glyphTint: Colors.of(QsWindow.window).fgMuted
                    implicitHeight: 22
                    onActivated: Net.clearError()
                }
            }
        }

        // ── Password prompt ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: passLayout.implicitHeight + Tokens.spacingXxl
            radius: Tokens.radiusCard
            visible: root.passwordMode
            color: Colors.of(QsWindow.window).section

            ColumnLayout {
                id: passLayout
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd + 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd
                    MaterialIcon { glyph: "󰌾"; color: Colors.of(QsWindow.window).focus; opacity: 0.8; variant: "body" }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Connect to \"" + (root.pendingNetwork?.name ?? "") + "\""
                        variant: "label"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                TextField {
                    id: passField
                    Layout.fillWidth: true
                    placeholder: Translation.tr("Password…")
                    glyph: "󰌋"
                    secret: !root.showPassword
                    trailingGlyph: root.showPassword ? "󰈈" : "󰈉"
                    onTrailingActivated: root.showPassword = !root.showPassword
                    onAccepted: root.doConnect()
                    onCancelled: { root.passwordMode = false; passField.text = "" }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    PanelButton {
                        Layout.preferredWidth: 72
                        label: Translation.tr("Cancel")
                        onActivated: { root.passwordMode = false; passField.text = "" }
                    }
                    PanelButton {
                        Layout.fillWidth: true
                        variant: "primary"
                        glyph: "󰌹"
                        label: Translation.tr("Connect")
                        onActivated: root.doConnect()
                    }
                }
            }
        }

        // ── Hidden network ────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hiddenLayout.implicitHeight + Tokens.spacingXxl
            radius: Tokens.radiusCard
            visible: root.hiddenMode
            color: Colors.of(QsWindow.window).section

            ColumnLayout {
                id: hiddenLayout
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd + 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd
                    MaterialIcon { glyph: "󰀂"; color: Colors.of(QsWindow.window).info; opacity: 0.8; variant: "body" }
                    StyledText { text: "Connect to hidden network"; variant: "label"; font.weight: Font.DemiBold }
                }

                TextField {
                    id: hiddenSsidField
                    Layout.fillWidth: true
                    placeholder: Translation.tr("Network name…")
                    glyph: "󰀂"
                    accent: Colors.of(QsWindow.window).info
                    onAccepted: hiddenPassField.forceActiveFocus()
                    onCancelled: root.hiddenMode = false
                }

                TextField {
                    id: hiddenPassField
                    Layout.fillWidth: true
                    placeholder: Translation.tr("Password…")
                    glyph: "󰌋"
                    accent: Colors.of(QsWindow.window).info
                    secret: true
                    onAccepted: root.doHiddenConnect()
                    onCancelled: root.hiddenMode = false
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    PanelButton {
                        Layout.preferredWidth: 72
                        label: Translation.tr("Cancel")
                        onActivated: root.hiddenMode = false
                    }
                    PanelButton {
                        Layout.fillWidth: true
                        variant: "primary"
                        accent:  Colors.of(QsWindow.window).info
                        glyph:   "󰀂"
                        label:   Translation.tr("Connect")
                        onActivated: root.doHiddenConnect()
                    }
                }
            }
        }

        // ── Network list ──────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: root.listHeight

            EmptyState {
                visible: !Net.wifiEnabled
                glyph:   "󰤭"
                message: Translation.tr("Wi-Fi is turned off")
            }

            EmptyState {
                visible:  Net.wifiEnabled && Net.networks.length === 0
                glyph:    Net.scanning ? "󰑓" : "󰤞"
                message:  Net.scanning ? "Scanning for networks…" : "No networks found"
                spinning: Net.scanning
            }

            ListView {
                anchors.fill: parent
                visible: Net.wifiEnabled && Net.networks.length > 0
                model: Net.networks
                spacing: Tokens.spacingSm
                clip: true

                delegate: NetworkRow {
                    required property var modelData
                    width: ListView.view.width
                    network: modelData
                }
            }
        }

        // ── Footer ────────────────────────────────────────────────────────────────
        // The hidden-network button lives with the form it opens, rather than with the
        // surface around it — it toggles this component's own state, so a caller holding
        // the button would have to reach in for a boolean it doesn't otherwise care about.
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingMd

            Item { Layout.fillWidth: true }

            PanelButton {
                capsule: true
                symbol: "add"
                label: Translation.tr("Hidden network")
                enabled: Net.wifiEnabled
                onActivated: { root.hiddenMode = !root.hiddenMode; root.passwordMode = false }
            }
        }
    }


    // ══ Components ════════════════════════════════════════════════════════════

    component TextField: Rectangle {
        id: tf
        property string placeholder:   ""
        property string glyph:         ""
        property string trailingGlyph: ""
        property bool   secret:        false
        property color  accent:        Colors.of(QsWindow.window).primary
        property alias  text:          input.text

        signal accepted()
        signal cancelled()
        signal trailingActivated()

        function forceActiveFocus() { input.forceActiveFocus() }

        height: 28
        radius: Tokens.radiusSm
        color:        input.activeFocus ? Colors.of(QsWindow.window).alpha(tf.accent, 0.12) : Colors.of(QsWindow.window).surfaceContainer
        border.color: input.activeFocus ? Colors.of(QsWindow.window).alpha(tf.accent, 0.55) : Colors.of(QsWindow.window).outline
        border.width: Tokens.borderWidth
        Behavior on color        { ColorAnimation { duration: Motion.respond } }
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:  9
            anchors.rightMargin: 9
            spacing: Tokens.spacingSm + 2

            MaterialIcon { glyph: tf.glyph; variant: "label"; opacity: 0.35 }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 28

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tf.placeholder
                    variant: "label"
                    opacity: 0.28
                    visible: input.text === ""
                }

                TextInput {
                    id: input
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: tf.secret ? TextInput.Password : TextInput.Normal
                    color: Colors.of(QsWindow.window).fg
                    font.family:    Tokens.fontFamily
                    font.pixelSize: Tokens.fontLabel
                    cursorVisible: activeFocus
                    selectByMouse: true
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    Keys.onReturnPressed: tf.accepted()
                    Keys.onEscapePressed: tf.cancelled()
                }
            }

            PanelButton {
                variant: "ghost"
                visible: tf.trailingGlyph !== ""
                glyph:   tf.trailingGlyph
                implicitHeight: 22
                glyphTint: tf.secret ? Colors.of(QsWindow.window).fgDim : tf.accent
                onActivated: tf.trailingActivated()
            }
        }
    }

    component EmptyState: ColumnLayout {
        id: empty
        property string glyph:    ""
        property string message:  ""
        property bool   spinning: false

        anchors.centerIn: parent
        spacing: Tokens.spacingSm + 2

        // Breathes rather than spins. Scanning is continuous while the panel is
        // open, so a spinner would never stop — it would read as "stuck", not
        // "working".
        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            glyph: empty.glyph
            variant: "display"
            font.pixelSize: Tokens.fontDisplay
            opacity: 0.22

            SequentialAnimation on opacity {
                running: empty.spinning
                loops: Animation.Infinite
                NumberAnimation { to: 0.10; duration: Motion.pulse; easing.type: Motion.ambient }
                NumberAnimation { to: 0.30; duration: Motion.pulse; easing.type: Motion.ambient }
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: empty.message
            variant: "label"
            opacity: 0.35
        }
    }

    // ── NetworkRow ────────────────────────────────────────────────────────────
    component NetworkRow: Rectangle {
        id: netRow
        property var network: null

        readonly property bool isActive:     netRow.network?.connected ?? false
        readonly property bool isConnecting: Net.connecting === netRow.network
        readonly property bool isSaved:      netRow.network?.known ?? false
        readonly property int  strength:     Net.strengthOf(netRow.network)

        height: root.rowHeight - 4
        radius: Tokens.radiusCard

        // The connected network is the subject: the tonal container, its bars on the accent.
        readonly property color ink: netRow.isActive ? Colors.of(QsWindow.window).fgOnPrimaryContainer : Colors.of(QsWindow.window).fg
        readonly property color inkDim: netRow.isActive ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.78)
                                                        : Colors.of(QsWindow.window).fgDim

        color: netRow.isActive ? Colors.of(QsWindow.window).primaryContainer : Colors.of(QsWindow.window).section
        Behavior on color { ColorAnimation { duration: Motion.standard } }

        HoverHandler { id: rowHover }

        // State layer.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: netRow.ink
            opacity: rowHover.hovered ? Tokens.stateHover : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:  Tokens.spacingMd + 2
            anchors.rightMargin: Tokens.spacingMd + 2
            spacing: Tokens.spacingMd + 2

            // Signal bars, on the row's shape: a disc, a cookie while this is the connected one.
            Item {
                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd

                MorphShape {
                    anchors.fill: parent
                    shape: netRow.isActive ? "cookie9" : "circle"
                    fillColor: netRow.isActive ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).surfaceHigh
                }

                Item {
                    id: signalBars
                    anchors.centerIn: parent
                    width: 19
                    height: 17

                    readonly property int bars: Net.bars(netRow.strength)
                    readonly property color tint: netRow.isActive ? Colors.of(QsWindow.window).fgOnPrimary
                        : netRow.strength < 25 ? Colors.of(QsWindow.window).danger
                        : netRow.strength < 50 ? Colors.of(QsWindow.window).warning
                        : Colors.of(QsWindow.window).fg

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            width:  4
                            radius: 2
                            height: 5 + index * 4
                            anchors.bottom: parent.bottom
                            x: index * 5

                            // `signalBars`, not `parent`: a Repeater reparents its delegates to its own
                            // parent, so `parent.bars` resolves only by accident of that.
                            color: index < signalBars.bars ? signalBars.tint
                                                           : Colors.of(QsWindow.window).alpha(signalBars.tint, 0.25)

                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                    }
                }
            }

            // Name + meta.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                StyledText {
                    Layout.fillWidth: true
                    text: netRow.network?.name ?? ""
                    variant: "body"
                    font.weight: Font.DemiBold
                    color: netRow.ink
                    elide: Text.ElideRight
                }

                RowLayout {
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: Net.isSecured(netRow.network) ? "lock" : "lock_open"
                        variant: "micro"
                        color: netRow.inkDim
                    }
                    StyledText {
                        text: Net.isSecured(netRow.network)
                            ? Net.securityLabel(netRow.network)
                            : "Open"
                        variant: "micro"
                        color: netRow.inkDim
                    }
                    StyledText { text: "·"; variant: "micro"; color: netRow.inkDim }
                    StyledText {
                        text: netRow.strength + "%"
                        variant: "micro"
                        color: netRow.inkDim
                    }

                    Badge {
                        visible: netRow.isSaved && !netRow.isActive
                        label: "saved"
                        tint:  Colors.of(QsWindow.window).success
                    }
                    Badge {
                        visible: netRow.isActive && Net.address !== ""
                        label: root.ipBlurred ? "connected" : Net.address
                        tint:  netRow.ink
                    }
                }
            }

            // ── Actions ───────────────────────────────────────────────────────
            // The buttons FADE, they don't appear. Toggling `visible` would remove
            // them from the layout, so the SSID text would jump sideways every
            // time the pointer crossed a row — the list would squirm under the
            // mouse. Their space is reserved permanently; only opacity changes.
            PanelButton {
                capsule: true
                opacity: (rowHover.hovered && !netRow.isConnecting) ? 1.0 : 0.0
                enabled: rowHover.hovered && !netRow.isConnecting
                label:   netRow.isActive ? "Disconnect" : "Connect"
                variant: netRow.isActive ? "normal" : "primary"
                onActivated: root.activate(netRow.network)
            }

            PanelButton {
                capsule: true
                // Still collapses when the network was never saved — that isn't a
                // hover-driven change, so it can't squirm.
                visible: netRow.isSaved
                opacity: (rowHover.hovered && !netRow.isConnecting) ? 1.0 : 0.0
                enabled: rowHover.hovered && !netRow.isConnecting
                label:   Translation.tr("Forget")
                onActivated: Net.forget(netRow.network)
            }

            // Connecting: a breathing dot, matching the scan indicator above.
            Rectangle {
                Layout.preferredWidth:   6
                Layout.preferredHeight:  6
                radius:  3
                color:   netRow.ink
                visible: netRow.isConnecting
                Layout.alignment: Qt.AlignVCenter

                SequentialAnimation on opacity {
                    running: netRow.isConnecting
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.15; duration: Motion.pulse; easing.type: Motion.ambient }
                    NumberAnimation { to: 1.00; duration: Motion.pulse; easing.type: Motion.ambient }
                }
            }
        }
    }
}
