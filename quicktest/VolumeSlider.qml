import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import "." as Local

Scope {
	id: root

	// Pywal color integration matching WallpaperSelector
	property var pywalData: Local.PywalColors.data

	property color bg:     pywalData?.special?.background || "#1a1b26"
	property color fg:     pywalData?.colors?.color7      || "#a9b1d6"
	property color color9: pywalData?.colors?.color9      || "#7dcfff"
	property color color2: pywalData?.colors?.color2      || "#ff9e64"

	// Semi-transparent pill background (matches WallpaperSelector's `pill` color)
	property color pillBg: {
		if (!pywalData || !pywalData.colors) return Qt.rgba(1, 1, 1, 0.08);
		var hex = pywalData.colors.color7;
		var r = parseInt(hex.substring(1, 3), 16) / 255;
		var g = parseInt(hex.substring(3, 5), 16) / 255;
		var b = parseInt(hex.substring(5, 7), 16) / 255;
		return Qt.rgba(r, g, b, 0.08);
	}

	// Bind the pipewire node so its volume will be tracked
	PwObjectTracker {
		objects: [ Pipewire.defaultAudioSink ]
	}

	Connections {
		target: Pipewire.defaultAudioSink?.audio ?? null

		function onVolumeChanged() {
			root.shouldShowOsd = true;
			hideTimer.restart();
		}
	}

	property bool shouldShowOsd: false

	Timer {
		id: hideTimer
		interval: 2000
		onTriggered: root.shouldShowOsd = false
	}

	LazyLoader {
		active: root.shouldShowOsd

		PanelWindow {
			anchors.bottom: true
			margins.bottom: screen.height / 6
			exclusiveZone: 0

			implicitWidth: 340
			implicitHeight: 64
			color: "transparent"

			mask: Region {}

			// Slide-in + fade animation
			property real slideOffset: 0

			NumberAnimation on slideOffset {
				from: 20
				to: 0
				duration: 300
				easing.type: Easing.OutCubic
				running: true
			}

			// Outer container — matches WallpaperSelector's main Rectangle
			Rectangle {
				anchors.fill: parent
				anchors.bottomMargin: -slideOffset

				radius: 18
				color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.97)

				border.color: Qt.rgba(root.color9.r, root.color9.g, root.color9.b, 0.12)
				border.width: 1

				opacity: parent.slideOffset > 0 ? Math.max(0, 1 - parent.slideOffset / 20) : 1

				Behavior on opacity {
					NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
				}

				// Inner shadow ring (mirrors WallpaperSelector)
				Rectangle {
					anchors.fill: parent
					anchors.margins: 1
					radius: parent.radius
					color: "transparent"
					border.color: Qt.rgba(0, 0, 0, 0.10)
					border.width: 1
				}

				RowLayout {
					anchors {
						fill: parent
						leftMargin: 14
						rightMargin: 16
					}
					spacing: 12

					// Icon badge — gradient pill matching WallpaperSelector's header icon
					Rectangle {
						width: 36
						height: 36
						radius: 10
						gradient: Gradient {
							orientation: Gradient.Horizontal
							GradientStop { position: 0.0; color: Qt.rgba(root.color9.r, root.color9.g, root.color9.b, 0.25) }
							GradientStop { position: 1.0; color: Qt.rgba(root.color2.r, root.color2.g, root.color2.b, 0.20) }
						}
						border.color: Qt.rgba(root.color9.r, root.color9.g, root.color9.b, 0.30)
						border.width: 1

						Text {
							anchors.centerIn: parent
							text: {
								var vol = Pipewire.defaultAudioSink?.audio.volume ?? 0;
								if (vol === 0) return "󰸈";
								if (vol < 0.33) return "󰕿";
								if (vol < 0.66) return "󰖀";
								return "󰕾";
							}
							color: root.fg
							font.family: "CodeNewRoman Nerd Font Propo"
							font.pixelSize: 18
						}
					}

					// Right side: label + track
					ColumnLayout {
						Layout.fillWidth: true
						spacing: 6

						RowLayout {
							Layout.fillWidth: true
							spacing: 0

							Text {
								text: "Volume"
								color: root.fg
								font.pixelSize: 12
								font.family: "CodeNewRoman Nerd Font Propo"
								font.weight: Font.Medium
								opacity: 0.7
							}

							Item { Layout.fillWidth: true }

							Text {
								text: Math.round((Pipewire.defaultAudioSink?.audio.volume ?? 0) * 100) + "%"
								color: root.color9
								font.pixelSize: 12
								font.family: "CodeNewRoman Nerd Font Propo"
								font.weight: Font.Medium
							}
						}

						// Track background
						Rectangle {
							Layout.fillWidth: true
							implicitHeight: 6
							radius: 3
							color: root.pillBg

							// Filled portion with accent gradient
							Rectangle {
								anchors {
									left: parent.left
									top: parent.top
									bottom: parent.bottom
								}
								width: parent.width * (Pipewire.defaultAudioSink?.audio.volume ?? 0)
								radius: parent.radius

								gradient: Gradient {
									orientation: Gradient.Horizontal
									GradientStop { position: 0.0; color: Qt.rgba(root.color9.r, root.color9.g, root.color9.b, 0.85) }
									GradientStop { position: 1.0; color: Qt.rgba(root.color2.r, root.color2.g, root.color2.b, 0.75) }
								}

								Behavior on width {
									NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
								}
							}
						}
					}
				}
			}
		}
	}
}
