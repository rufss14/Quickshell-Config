import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickScreenTime ───────────────────────────────────────────────────────────
// The screen time pill's card: today so far, the three apps that took the most of the week, and a pause
// for tracking (`ScreenTime.pause` / `resume`). Charts and goals are the panel's.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    symbol: "timer"
    shape: "cookie6"
    title: Translation.tr("Screen time")
    value: !Config.screenTime ? Translation.tr("Off")
         : ScreenTime.paused ? Translation.tr("Paused, %1 today").arg(ScreenTime.duration(ScreenTime.todayTotal))
         : Translation.tr("%1 today").arg(ScreenTime.duration(ScreenTime.todayTotal))

    trailing: ChipButton {
        symbol: ScreenTime.paused ? "play_arrow" : "pause"
        tint: root.palette.primary
        solid: true
        visible: Config.screenTime
        onActivated: ScreenTime.paused ? ScreenTime.resume() : ScreenTime.pause(30)
    }

    StyledText {
        visible: Config.screenTime && ScreenTime.weekApps.length > 0
        variant: "caption"
        emphasis: "dim"
        text: Translation.tr("This week")
    }
    Repeater {
        model: Config.screenTime ? ScreenTime.weekApps : []
        Row {
            required property var modelData
            width: parent.width
            StyledText { width: parent.width - t.width; text: modelData.app; elide: Text.ElideRight }
            StyledText { id: t; text: ScreenTime.short(modelData.seconds); emphasis: "dim"; font.features: { "tnum": 1 } }
        }
    }
    StyledText {
        visible: !Config.screenTime || ScreenTime.weekApps.length === 0
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: Config.screenTime ? Translation.tr("Nothing counted yet.") : Translation.tr("Tracking is off in Settings.")
    }
    ChipButton {
        symbol: "timer"
        label: Translation.tr("Details")
        tint: root.palette.primary
        onActivated: root.openPanel("screentime")
    }
}
