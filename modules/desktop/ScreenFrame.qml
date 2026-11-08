pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../state"

// ── ScreenFrame ───────────────────────────────────────────────────────────────
// A thin ring of the bar's material around the screen: strips down both sides and
// along the bottom, with concave corners where ring meets content — so the desktop
// reads as INSET into the shell. Toggled by Config.screenFrame (Settings → Bar).
//
// ── The top edge is drawn by the BAR, not here ────────────────────────────────
// Layer-shell surfaces on the same layer stack by MAP ORDER, so a top band toggled
// on at runtime would map after the bar and paint over its pills. BarFrameEdge
// draws the band, the top corners and the stubs that meet these strips — inside
// the bar's own window, where z-order is guaranteed.
//
// ── Reservation and drawing are SEPARATE windows ──────────────────────────────
// v2 drew each strip in its own reserving window plus two corner windows, and the
// seams between five surfaces (plus per-window stroke clipping) are what read as
// "unpolished". Now three invisible windows do nothing but hold the exclusive
// zones, and ONE full-screen click-through overlay draws every fill and a single
// continuous border path — no seams, no clipped stroke endpoints, one scene.
// The overlay reserves nothing and takes no input (empty mask), and its top area
// under the bar is empty, so overlapping the bar's surface is harmless in either
// map order.
//
// ── Colour ────────────────────────────────────────────────────────────────────
// Colors.frameFill / frameLine — the pills' Surface recipe at the bar's opacity,
// defined once in Colors so ring and pills cannot drift apart. For blur add a
// Hyprland layer rule for the "quickshell-frame" namespace, like the bar's.
// ─────────────────────────────────────────────────────────────────────────────
Scope {
    id: root

    required property var modelData     // the screen, from Variants

    // frameDepth, not frameThickness — the CLAMPED effective thickness. This is a
    // seam, not a detail: BarFrameEdge draws the stubs at frameDepth, and whenever
    // the clamp bites (a thin bar can't hold a deep band) the raw pref is wider than
    // the stubs. The strips would then be a couple of px wider than the stubs they
    // continue, putting a visible step in the ring at exactly the bar's boundary.
    readonly property int thickness: Config.frameDepth
    readonly property int cornerRadius: Config.frameCornerRadius
    readonly property int bw: Config.frameBorderWidth

    // ── Reservations ──────────────────────────────────────────────────────────
    // Mapped, transparent, empty: their exclusive zones are their entire job.
    // The side pair starts below the bar (the bar already reserves its own zone).
    component ReserveStrip: PanelWindow {
        screen: root.modelData
        visible: Config.screenFrame
        color: "transparent"
        mask: Region {}
    }

    ReserveStrip {
        anchors.left: true; anchors.top: true; anchors.bottom: true
        margins.top: Config.barThickness
        implicitWidth: root.thickness
    }
    ReserveStrip {
        anchors.right: true; anchors.top: true; anchors.bottom: true
        margins.top: Config.barThickness
        implicitWidth: root.thickness
    }
    ReserveStrip {
        anchors.bottom: true; anchors.left: true; anchors.right: true
        implicitHeight: root.thickness
    }

    // ── The overlay: every visible pixel of the ring below the bar ────────────
    PanelWindow {
        id: overlay

        screen: root.modelData
        visible: Config.screenFrame && !UiState.blobRingOwned
        anchors.left: true; anchors.right: true
        anchors.top: true; anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // Empty region: the whole surface is click-through — the corners overlap
        // desktop content by design and must never eat a click.
        mask: Region {}
        WlrLayershell.namespace: "quickshell-frame"

        readonly property int w: overlay.width
        readonly property int h: overlay.height
        // Where the BAR'S WINDOW actually ends, apron included — not where the bar
        // visually ends. This is the whole seam.
        //
        // The bar draws the band and the stubs down its own full window height, and
        // that window is `frameApron` px taller than the bar while fused. Starting
        // the strips at barThickness would overlap the stubs by exactly that much —
        // and these are two SEPARATE layer-shell surfaces, so an overlap isn't a
        // harmless redraw: the compositor blends both, and frameFill is translucent.
        // The overlap would composite twice and put a darker band across the ring at
        // precisely the junction that is supposed to be invisible. Butt-joined here
        // instead, so every pixel of the ring is painted by exactly one surface.
        readonly property int barBottom: Config.barExtent + Config.frameApron

        // Fills. The strips meet the corner slivers inside one scene, so there is
        // nothing to seam.
        Rectangle {
            x: 0; y: overlay.barBottom
            width: root.thickness; height: overlay.h - overlay.barBottom
            color: Colors.of(QsWindow.window).frameFill
        }
        Rectangle {
            x: overlay.w - root.thickness; y: overlay.barBottom
            width: root.thickness; height: overlay.h - overlay.barBottom
            color: Colors.of(QsWindow.window).frameFill
        }
        Rectangle {
            x: 0; y: overlay.h - root.thickness
            width: overlay.w; height: root.thickness
            color: Colors.of(QsWindow.window).frameFill
        }
        ConcaveCorner {
            which: 3
            x: root.thickness; y: overlay.h - root.thickness - root.cornerRadius
            width: root.cornerRadius; height: root.cornerRadius
            fill: Colors.of(QsWindow.window).frameFill
            visible: root.cornerRadius > 0
        }
        ConcaveCorner {
            which: 2
            x: overlay.w - root.thickness - root.cornerRadius
            y: overlay.h - root.thickness - root.cornerRadius
            width: root.cornerRadius; height: root.cornerRadius
            fill: Colors.of(QsWindow.window).frameFill
            visible: root.cornerRadius > 0
        }

        // The inner border, one continuous path: down the left strip, around the
        // bottom-left arc, across the bottom, around the bottom-right arc, up the
        // right strip. Straight runs sit on the innermost borderWidth of the
        // material; the arcs ride at r + bw/2, which lands them on exactly the
        // same line — the stroke never jogs at a junction.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Colors.of(QsWindow.window).frameLine
                strokeWidth: overlay.bwF
                // This path's two ENDS butt against BarFrameEdge's stubs at
                // `barBottom`, across a window boundary. SquareCap (the default)
                // would run each end half a line-width past that junction, into
                // pixels the stub already strokes — double-covering the seam the
                // butt-join exists to make invisible. See BarFrameEdge's own note.
                capStyle: ShapePath.FlatCap
                fillColor: "transparent"

                startX: root.thickness - overlay.bwF / 2
                startY: overlay.barBottom
                PathLine {
                    x: root.thickness - overlay.bwF / 2
                    y: overlay.h - root.thickness - root.cornerRadius
                }
                PathArc {
                    x: root.thickness + root.cornerRadius
                    y: overlay.h - root.thickness + overlay.bwF / 2
                    radiusX: root.cornerRadius + overlay.bwF / 2
                    radiusY: root.cornerRadius + overlay.bwF / 2
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: overlay.w - root.thickness - root.cornerRadius
                    y: overlay.h - root.thickness + overlay.bwF / 2
                }
                PathArc {
                    x: overlay.w - root.thickness + overlay.bwF / 2
                    y: overlay.h - root.thickness - root.cornerRadius
                    radiusX: root.cornerRadius + overlay.bwF / 2
                    radiusY: root.cornerRadius + overlay.bwF / 2
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: overlay.w - root.thickness + overlay.bwF / 2
                    y: overlay.barBottom
                }
            }
        }

        // The stroke geometry wants the half-width offset as a real, not the int.
        readonly property real bwF: root.bw

        // The entrance: the sides trace down from the bar on the same front as the bar
        // window's own stage (Bar.qml), so the ring arrives as one edge.
        IntroStage { front: Intro.front(overlay.barBottom, overlay.h) }

        // A wallpaper or colour change eats this ring's old look away on the same
        // front as the bar's (components/Infection.qml). Only while this overlay is
        // the ring — with the blob, the bar's window draws the frame and carries it.
        // Full-screen and ignoring every zone, so it sits at the screen's origin.
        Infection {
            host: overlay.contentItem
            screen: overlay.screen
            hostVisible: overlay.visible
        }
    }
}
