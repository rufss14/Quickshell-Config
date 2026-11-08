import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── FeedNews ──────────────────────────────────────────────────────────────────
// The left face's News page (OverviewFeed): headlines from services/News — near you (your
// country's top stories) or the world, plus a few subjects. The first story is the hero, tinted
// and bigger; the rest are rows. A click opens the story in the browser and the overview leaves.
// Pictures (News.pictures, a second pass) fill in as they arrive: the hero becomes a photo card —
// the picture full-bleed, fading into the card at the bottom, the headline over it — and a row gets
// a thumbnail on its right. A story with none, or before its picture loads, is the text card.
// Asks News only while it is the page in view (`current`).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool current: false
    property color accent: Colors.of(QsWindow.window).primary
    // The page's scrolling list, for the face's wheel (OverviewFeed).
    readonly property Flickable flick: list

    onCurrentChanged: root.current ? News.want() : News.unwant()
    Component.onCompleted: if (root.current) News.want()
    Component.onDestruction: News.unwant()

    readonly property string where: News.topic === "local" ? News.country : News.topicLabel

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        FeedHeader {
            Layout.fillWidth: true
            Layout.fillHeight: false
            symbol: "newspaper"
            title: Translation.tr("The")
            tail: Translation.tr("news")
            accent: root.accent
            subtitle: News.busy && News.items.length === 0 ? Translation.tr("Fetching…")
                    : News.error !== "" && News.items.length === 0 ? Translation.tr("Offline")
                    : (News.topic === "local" ? Translation.tr("Near you") + " · " + News.country : News.topicLabel)
                      + (News.fetched > 0 ? " · " + (News.stale ? Translation.tr("from earlier") : News.ago(News.fetched)) : "")

            ChipTray {
                ChipButton {
                    id: refresh
                    symbol: "refresh"
                    tint: root.accent
                    iconAngle: refresh.spin
                    property real spin: 0
                    NumberAnimation on spin {
                        running: News.busy && Config.motionEnabled
                        from: 0; to: 360; duration: 900
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) refresh.spin = 0
                    }
                    onActivated: News.refresh(true)
                }
            }
        }

        // ── Near you, the world, a subject (SlidingTabs) ────────────────────────
        // The picked one carries its name; the lit pill slides to a new pick.
        SlidingTabs {
            Layout.alignment: Qt.AlignLeft
            Layout.fillHeight: false
            model: News.topics
            position: Math.max(0, News.topics.findIndex(t => t.id === News.topic))
            animate: true
            accent: root.accent
            onPicked: index => News.setTopic(News.topics[index].id)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: Tokens.spacingSm
                boundsBehavior: Flickable.StopAtBounds
                model: News.items
                // Scrolled by the face's wheel (OverviewFeed); a mouse drag here is the swipe.
                interactive: false
                // A new topic starts at its top story, and its stories rise in (`bornAt`); a row
                // built later, by scrolling, is simply there.
                property real bornAt: 0
                onModelChanged: { list.bornAt = Date.now(); list.positionViewAtBeginning() }

                delegate: Rectangle {
                    id: story
                    required property var modelData
                    required property int index
                    readonly property bool hero: story.index === 0
                    readonly property int pad: story.hero ? Tokens.spacingLg : Tokens.spacingMd
                    readonly property string picUrl: News.pictureOf(story.modelData.url)
                    readonly property bool picOn: story.picUrl !== "" && pic.status === Image.Ready
                    readonly property int thumb: Math.round(Tokens.sideCardUnit * 1.3)

                    width: ListView.view.width
                    height: story.hero && story.picOn
                            ? Math.max(Math.round(story.width * 0.8), storyCol.implicitHeight + story.pad * 2 + Math.round(story.width * 0.35))
                            : Math.max(storyCol.implicitHeight, story.picOn ? story.thumb : 0) + story.pad * 2
                    Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                    radius: story.hero ? Tokens.radiusCard : Tokens.radiusCard - Tokens.spacingXs
                    color: Colors.of(QsWindow.window).fade(
                               storyHover.hovered ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh, root.accent, story.hero ? 0.2 : 0.08)
                             : story.hero ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.accent, 0.14)
                             : Colors.of(QsWindow.window).surfaceContainer, 0.88)
                    border.width: story.hero ? Tokens.borderWidth : 0
                    border.color: Colors.of(QsWindow.window).alpha(root.accent, 0.35)
                    SpringValue { id: storyLean; target: storyTap.pressed ? 0.98 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
                    scale: storyLean.value
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    // Rises in, a beat after the one above it.
                    readonly property bool fresh: Date.now() - list.bornAt < 900
                    opacity: story.fresh ? 0 : 1
                    transform: Translate { id: rise; y: story.fresh ? Tokens.spacingLg : 0 }
                    SequentialAnimation {
                        running: story.fresh
                        PauseAnimation { duration: Math.min(story.index, 8) * Motion.stagger }
                        ParallelAnimation {
                            NumberAnimation { target: story; property: "opacity"; to: 1; duration: Motion.standard }
                            NumberAnimation { target: rise; property: "y"; to: 0; duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                        }
                    }

                    // ── The picture: the hero's whole card, a row's thumbnail ───────────
                    ClippingRectangle {
                        id: picBox
                        x: story.hero ? 0 : story.width - story.pad - story.thumb
                        y: story.hero ? 0 : story.pad
                        width: story.hero ? story.width : story.thumb
                        height: story.hero ? story.height : story.thumb
                        radius: story.hero ? story.radius : Tokens.radiusSm
                        color: "transparent"
                        opacity: story.picOn ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.emphasized } }
                        Image {
                            id: pic
                            anchors.fill: parent
                            source: story.picUrl
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: story.hero ? 720 : 192
                            // A slow lean in under the pointer.
                            scale: storyHover.hovered ? 1.06 : 1
                            Behavior on scale { NumberAnimation { duration: Motion.emphasized * 2; easing.type: Motion.travel } }
                        }
                        // The hero's headline sits on the picture: it fades into the card's own colour.
                        Rectangle {
                            anchors.fill: parent
                            visible: story.hero
                            gradient: Gradient {
                                GradientStop { position: 0.2; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0) }
                                GradientStop { position: 0.62; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.72) }
                                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.96) }
                            }
                        }
                    }

                    Column {
                        id: storyCol
                        x: story.pad
                        y: story.hero && story.picOn ? story.height - storyCol.implicitHeight - story.pad : story.pad
                        width: story.width - story.pad * 2 - (!story.hero && story.picOn ? story.thumb + Tokens.spacingMd : 0)
                        spacing: Tokens.spacingXs + 1

                        StyledText {
                            visible: story.hero
                            text: Translation.tr("Top story")
                            variant: "micro"
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1
                            color: root.accent
                        }
                        Row {
                            spacing: Tokens.spacingSm
                            // The source's own icon, or its initial when there's none.
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Tokens.iconSm
                                height: Tokens.iconSm
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Tokens.radiusXs
                                    visible: fav.status !== Image.Ready
                                    color: Colors.of(QsWindow.window).alpha(root.accent, 0.25)
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: (story.modelData.source || "?").charAt(0).toUpperCase()
                                        variant: "micro"
                                        font.weight: Font.DemiBold
                                        color: root.accent
                                    }
                                }
                                Image {
                                    id: fav
                                    anchors.fill: parent
                                    asynchronous: true
                                    sourceSize: Qt.size(32, 32)
                                    source: story.modelData.domain ? "https://www.google.com/s2/favicons?sz=64&domain=" + encodeURIComponent(story.modelData.domain) : ""
                                }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, storyCol.width - Tokens.iconSm - agoText.implicitWidth - Tokens.spacingSm * 3)
                                text: story.modelData.source || story.modelData.domain || ""
                                variant: "caption"
                                font.weight: Font.DemiBold
                                emphasis: "muted"
                                elide: Text.ElideRight
                            }
                            StyledText {
                                id: agoText
                                anchors.verticalCenter: parent.verticalCenter
                                text: News.ago(story.modelData.time)
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }
                        StyledText {
                            width: storyCol.width
                            text: story.modelData.title
                            variant: story.hero ? "title" : "body"
                            font.weight: story.hero ? Font.DemiBold : Font.Medium
                            wrapMode: Text.Wrap
                            maximumLineCount: story.hero ? 4 : 3
                            elide: Text.ElideRight
                            lineHeight: 1.05
                        }
                    }

                    HoverHandler { id: storyHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: storyTap
                        onTapped: {
                            News.open(story.modelData)
                            UiState.leaveOverview(-1)
                        }
                    }
                }
            }
            Scrollbar { flickable: list }

            // ── Waiting: a few rows breathing where the stories will be ─────────
            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Tokens.spacingSm
                visible: News.items.length === 0 && News.busy
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        width: parent.width
                        height: index === 0 ? Tokens.sideCardUnit * 2.4 : Tokens.sideCardUnit * 1.4
                        radius: Tokens.radiusCard - (index === 0 ? 0 : Tokens.spacingXs)
                        color: Colors.of(QsWindow.window).surfaceContainer
                        SequentialAnimation on opacity {
                            running: Config.motionEnabled && parent.visible
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * Motion.stagger * 2 }
                            NumberAnimation { from: 0.35; to: 0.8; duration: Motion.emphasized; easing.type: Motion.ambient }
                            NumberAnimation { from: 0.8; to: 0.35; duration: Motion.emphasized; easing.type: Motion.ambient }
                        }
                    }
                }
            }

            // ── Couldn't fetch, and nothing from before ─────────────────────────
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingXl * 2
                visible: News.items.length === 0 && !News.busy && News.error !== ""
                spacing: Tokens.spacingSm
                ScallopChip {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 56
                    implicitHeight: 56
                    symbol: "wifi_off"
                    tint: root.accent
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No news right now")
                    variant: "body"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: News.error
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.Wrap
                }
                ChipButton {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "refresh"
                    label: Translation.tr("Try again")
                    tint: root.accent
                    onActivated: News.refresh(true)
                }
            }
        }
    }
}
