pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── MicTest ───────────────────────────────────────────────────────────────────
// Hear your own microphone: routes the default source straight to the default sink.
//
// ── Why a loopback and not a level meter ──────────────────────────────────────
// The Sound page already meters the mic, and a meter answers "is the input device
// receiving signal". It cannot answer the questions people actually have — is it picking
// up the fan, is it clipping, does it sound distant, is it the wrong mic — because those
// are judgements only your ears can make. So the test plays it back.
//
// ── pw-loopback, not a recording ──────────────────────────────────────────────
// No file is written and nothing is stored: audio goes source → sink and is gone. That
// also means the test needs no permission beyond what the shell already has, and there
// is no artefact to clean up afterwards.
//
// ── The argument shapes are measured, not guessed ─────────────────────────────
// `-n` truncates at the first whitespace: `-n "Quickshell Mic Test"` produced nodes named
// `input.Quickshell` / `output.Quickshell`, so the name is a single hyphenated token.
// The identity that shows in the UI is set through the stream props instead, which is
// what makes the row read "Microphone test" rather than "Pw-loopback" — with no props,
// the nodes carry no application identity at all and Audio.labelFor falls back to
// resolving the pw-loopback client.
//
// ── It appears in the Recording list, on purpose ──────────────────────────────
// The capture side is a genuine `Stream/Input/Audio` on your microphone, so it shows up
// under Recording while the test runs. That is correct and worth keeping: something IS
// listening to you, and it would be a strange shell that hid its own microphone access
// from the list it publishes for exactly that question.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool running: proc.running

    // ── The auto-stop is a safety feature, not a convenience ──────────────────
    // A loopback on SPEAKERS is a feedback loop: the mic hears the playback, plays it
    // back louder, and howls. Headphones make it harmless, which is exactly why it's easy
    // to forget it running and then plug into speakers later. It stops itself.
    readonly property int limitSeconds: 60
    readonly property int remaining: root._remaining
    property int _remaining: 0

    function start() {
        if (proc.running) return
        root._remaining = root.limitSeconds
        proc.running = true
    }
    function stop() {
        proc.running = false
        root._remaining = 0
    }
    function toggle() { root.running ? root.stop() : root.start() }

    Process {
        id: proc
        running: false

        // No -C/-P: both ends follow the DEFAULT source and sink, so the test always
        // exercises whatever the page is showing as selected. Pinning them would let the
        // test quietly measure a device you'd since switched away from.
        readonly property string ident: "application.name=\"Microphone test\" "
                                      + "media.name=\"Microphone test\""
        command: ["pw-loopback", "-n", "quickshell-mic-test",
                  "-i", proc.ident,
                  "-o", proc.ident]

        // The process dying on its own (PipeWire restarting, pw-loopback missing) must
        // put the countdown back, or the UI would keep showing a test that isn't running.
        onRunningChanged: if (!proc.running) root._remaining = 0
    }

    Timer {
        running: root.running
        interval: 1000
        repeat: true
        onTriggered: {
            root._remaining--
            if (root._remaining <= 0) root.stop()
        }
    }
}
