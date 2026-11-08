import QtQuick
import QtQuick.Layouts
import "../config"

// ── SpectrumPicker ────────────────────────────────────────────────────────────
// SV square + smooth hue strip. Driven by `value` (hex string); dragging emits
// colorPicked(hex). Internal HSV state stays separate from `value` to avoid
// jitter while dragging.
//
// A colour that arrives from OUTSIDE (another swatch picked, a hex typed, the album cover
// changing) glides: the cursor and the hue thumb travel to it and the square's base hue
// crossfades. A DRAG never glides — the cursor is pinned to the pointer, since easing it would
// make it chase what it is already following (Motion's one rule).
// Rounded corners: the outer Item uses layer.enabled so Qt composites it as a
// flat texture; the masking Rectangle with radius clips it at the GPU level.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string value: "#ff0000"
    signal colorPicked(string hex)

    implicitHeight: 140

    property real h: 0
    property real s: 1
    property real v: 1
    property bool _internalUpdate: false

    property bool _drag:    false     // a press is down on the square or the strip
    property bool _settled: false     // set once the first layout is done, so nothing glides in from 0,0
    readonly property bool _glide: root._settled && !root._drag
    // A press is down on the square or the strip — for a caller that wants a drag as ONE step
    // (the colours panel's undo history snapshots when it starts).
    readonly property bool dragging: root._drag

    function hexToHsv(hex) {
        var c = hex.replace("#","")
        var r=parseInt(c.substring(0,2),16)/255
        var g=parseInt(c.substring(2,4),16)/255
        var b=parseInt(c.substring(4,6),16)/255
        var mx=Math.max(r,g,b), mn=Math.min(r,g,b), d=mx-mn
        var hh=0
        if(d!==0){
            if(mx===r)      hh=((g-b)/d)%6
            else if(mx===g) hh=(b-r)/d+2
            else            hh=(r-g)/d+4
        }
        hh=hh/6; if(hh<0) hh+=1
        return [hh, mx===0?0:d/mx, mx]
    }

    function hsvToHex(hh,ss,vv) {
        var i=Math.floor(hh*6), f=hh*6-i
        var p=vv*(1-ss), q=vv*(1-f*ss), t=vv*(1-(1-f)*ss)
        var r,g,b
        switch(i%6){
            case 0:r=vv;g=t;b=p;break
            case 1:r=q;g=vv;b=p;break
            case 2:r=p;g=vv;b=t;break
            case 3:r=p;g=q;b=vv;break
            case 4:r=t;g=p;b=vv;break
            default:r=vv;g=p;b=q;break
        }
        function c(x){ var s2=Math.round(x*255).toString(16); return s2.length<2?"0"+s2:s2 }
        return "#"+c(r)+c(g)+c(b)
    }

    function syncFromValue() {
        if(_internalUpdate) return
        var hsv=hexToHsv(root.value)
        h=hsv[0]; s=hsv[1]; v=hsv[2]
    }
    onValueChanged: syncFromValue()
    Component.onCompleted: { syncFromValue(); Qt.callLater(function () { root._settled = true }) }

    function emitCurrent() {
        _internalUpdate=true
        colorPicked(hsvToHex(h,s,v))
        _internalUpdate=false
    }

    // ── Outer container ───────────────────────────────────────────────────────
    // The corners are rounded on the CHILDREN, not here. `layer.enabled` was doing this
    // job before and could not: it renders children into a texture but does not mask that
    // texture to the parent's radius, so the gradients kept their square corners while the
    // comment claimed otherwise. Per-corner radius (Qt 6.7+, this is 6.11) rounds the top
    // of the square and the bottom of the hue strip, leaving the join between them flat so
    // the two still read as one control.
    Rectangle {
        id: outerFrame
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0   // no gap so the two sections look like one continuous widget

            // ── SV square ─────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    id: svSquare
                    anchors.fill: parent
                    color: "transparent"
                    clip: true
                    topLeftRadius: 10
                    topRightRadius: 10

                    Rectangle {
                        anchors.fill: parent
                        color: root.hsvToHex(root.h, 1, 1)
                        topLeftRadius: 10
                        topRightRadius: 10
                        Behavior on color { enabled: root._glide; ColorAnimation { duration: Motion.standard } }
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#ffffffff" }
                            GradientStop { position: 1.0; color: "#00ffffff" }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "#00000000" }
                            GradientStop { position: 1.0; color: "#ff000000" }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed:         function(mouse) { root._drag = true; updateSV(mouse.x, mouse.y) }
                        onReleased:        root._drag = false
                        onCanceled:        root._drag = false
                        onPositionChanged: function(mouse) { if(pressed) updateSV(mouse.x, mouse.y) }
                        function updateSV(px,py) {
                            root.s=Math.max(0,Math.min(1,px/width))
                            root.v=Math.max(0,Math.min(1,1-py/height))
                            root.emitCurrent()
                        }
                    }
                }

                // Cursor — shadow ring
                Rectangle {
                    x: root.s * svSquare.width  - width/2
                    y: (1-root.v) * svSquare.height - height/2
                    Behavior on x { enabled: root._glide; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    Behavior on y { enabled: root._glide; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    width: 16; height: 16; radius: 8
                    color: "transparent"
                    border.color: "#55000000"; border.width: 3
                }
                // Cursor — white ring
                Rectangle {
                    x: root.s * svSquare.width  - width/2
                    y: (1-root.v) * svSquare.height - height/2
                    Behavior on x { enabled: root._glide; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    Behavior on y { enabled: root._glide; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    width: 14; height: 14; radius: 7
                    color: "transparent"
                    border.color: "white"; border.width: 2
                }
                // Cursor — color fill
                Rectangle {
                    x: root.s * svSquare.width  - width/2
                    y: (1-root.v) * svSquare.height - height/2
                    Behavior on x { enabled: root._glide; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    Behavior on y { enabled: root._glide; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    width: 8; height: 8; radius: 4
                    color: root.hsvToHex(root.h, root.s, root.v)
                    Behavior on color { enabled: root._glide; ColorAnimation { duration: Motion.standard } }
                }
            }

            // ── Thin separator ─────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                color: "#22000000"
            }

            // ── Hue strip ──────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                id: hueItem

                Rectangle {
                    id: hueStrip
                    anchors.fill: parent
                    color: "transparent"
                    clip: true
                    bottomLeftRadius: 10
                    bottomRightRadius: 10

                    Rectangle {
                        anchors.fill: parent
                        bottomLeftRadius: 10
                        bottomRightRadius: 10
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0/6;  color: "#ff0000" }
                            GradientStop { position: 1/6;  color: "#ffff00" }
                            GradientStop { position: 2/6;  color: "#00ff00" }
                            GradientStop { position: 3/6;  color: "#00ffff" }
                            GradientStop { position: 4/6;  color: "#0000ff" }
                            GradientStop { position: 5/6;  color: "#ff00ff" }
                            GradientStop { position: 6/6;  color: "#ff0000" }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed:         function(mouse) { root._drag = true; updateH(mouse.x) }
                        onReleased:        root._drag = false
                        onCanceled:        root._drag = false
                        onPositionChanged: function(mouse) { if(pressed) updateH(mouse.x) }
                        function updateH(px) {
                            root.h=Math.max(0,Math.min(0.9999,px/width))
                            root.emitCurrent()
                        }
                    }
                }

                // Hue thumb — white pill with shadow
                Rectangle {
                    x: root.h * hueStrip.width - width/2
                    y: 1
                    Behavior on x { enabled: root._glide; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    width: 6; height: hueStrip.height - 2; radius: 3
                    color: "white"
                    border.color: "#55000000"; border.width: 1
                }
            }
        }
    }
}
