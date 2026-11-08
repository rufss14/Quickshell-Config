import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── StatCard ──────────────────────────────────────────────────────────────────
// One gauge, one label, one line of detail. CPU, GPU and memory are the same readout
// of different silicon, so they are one component.
//
// ── Why this lives in components/ and the other three renderings do not ───────
// There are four places in this shell that draw SysInfo, and they are NOT all the
// same widget: About's GaugeTile is a 104px ring with a sparkline beside it and room
// for per-core bars, and the desktop's SysmonWidget is a configurable tile that
// cycles metrics on tap. Folding those together would mean a size mode, a sparkline
// mode and a cycle mode — more surface area than the code it would save.
//
// The lock screen and the greeter are the two that genuinely ARE the same widget:
// a fixed 78px ring in a card narrow enough that three fit across the top of a
// full-screen surface without reaching the clock. It was written inline in
// LockScreen and lifted here the moment the greeter needed the identical thing,
// rather than copied — two files drifting apart is how the corners of a shell stop
// matching each other.
//
// ── No service import, on purpose ─────────────────────────────────────────────
// `sampleInterval` is a property rather than a read of `SysInfo.interval`, so this
// file stays presentation-only. A component reaching into services/ for a timing
// constant is a layering inversion that costs nothing to avoid: the caller already
// knows which service it is feeding this from.
Surface {
    id: stat

    property real   value:   0        // 0..1
    property string label:   ""
    property string detail:  ""
    property color  tint:    Colors.of(QsWindow.window).primary

    // The sampling period of whatever is driving `value`. Set, the ring settles into
    // each sample (Motion.settle, capped at this) and rests; see RadialGauge.
    // 0 = a plain one-off ease.
    property int    sampleInterval: 0

    // ── Sized by its CONTENT, not by a guess ─────────────────────────────────
    // This was a flat 168×108 and the detail lines ran straight out of the card:
    // "68°C · 24 threads" and "11.4 / 24.0 GB" are simply wider than a number picked
    // by eye, and they change width with the machine, the load and the temperature.
    // Measuring the row is the only version that cannot be wrong — and the minimum
    // keeps the three cards the same size as each other when their text is short,
    // which is what stops the row looking ragged.
    implicitWidth:  Math.max(176, statRow.implicitWidth + Tokens.spacingLg * 2)
    implicitHeight: Math.max(104, statRow.implicitHeight + Tokens.spacingMd * 2)

    elevation:    Tokens.elevationCard
    squareMode:   Config.barShape
    cornerRadius: Tokens.radiusCard
    fillOpacity:  Config.surfaceOpacity

    RowLayout {
        id: statRow
        anchors.centerIn: parent
        spacing: Tokens.spacingMd

        RadialGauge {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  78
            implicitHeight: 78
            thickness: 7
            value:  stat.value
            accent: stat.tint
            sampleInterval: stat.sampleInterval

            StyledText {
                anchors.centerIn: parent
                // The hero figure in TEXT colour, not the accent — the ring around it
                // already carries the identity, and a number in the accent makes the
                // card read as two things saying the same word. About's tile makes
                // the same call.
                text: Math.round(stat.value * 100) + "%"
                variant: "title"
                font.bold: true
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                text: stat.label
                variant: "label"
                font.bold: true
                color: stat.tint
            }
            StyledText {
                visible: stat.detail !== ""
                text: stat.detail
                variant: "caption"
                emphasis: "dim"
                // Belt as well as braces. The card measures this text and grows to
                // fit it, so this should never trigger — but "should never" about a
                // string assembled from a temperature, a core count and two disk
                // figures is worth a cap rather than a clipped card.
                Layout.maximumWidth: 220
                elide: Text.ElideRight
            }
        }
    }
}
