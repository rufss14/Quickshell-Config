#!/usr/bin/env python3
"""discordlog.py: the call's real connect time from Discord's renderer log. Pure, runs on fixture text."""
import os, sys, time, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import discordlog as d

def L(ts, ctx, chan, a, b):
    return "[%s] [info]  [RTCConnection(%s, %s)] RTC connection state: %s => %s" % (ts, chan, ctx, a, b)

def ms(ts):
    return int(time.mktime(time.strptime(ts[:19], "%Y-%m-%d %H:%M:%S")) * 1000) + int(ts[20:])

fails = 0
def check(name, got, want):
    global fails
    if got != want:
        fails += 1
        print("FAIL %s: got %r want %r" % (name, got, want))
    else:
        print("  ok  %s" % name)

T1, T2, T3 = "2026-11-15 18:32:24.290", "2026-11-15 19:19:23.503", "2026-11-15 19:20:43.181"
text = "\n".join([
    "[2026-11-15 18:00:00.000] [info]  [RPCServer:IPC] Socket Emit: 506 [object Object]",
    L(T1, "default", "100", "RTC_CONNECTING", "RTC_CONNECTED"),
    L("2026-11-15 18:40:00.000", "default", "100", "RTC_CONNECTED", "RTC_DISCONNECTED"),
    L("2026-11-15 18:40:00.100", "default", "100", "RTC_DISCONNECTED", "DISCONNECTED"),
    L(T2, "default", "100", "RTC_CONNECTING", "RTC_CONNECTED"),
    L("2026-11-15 19:20:00.000", "stream", "100", "RTC_CONNECTING", "RTC_CONNECTED"),
    L(T3, "default", "200", "RTC_CONNECTING", "RTC_CONNECTED"),
    "[2026-11-15 19:21:00.000] [info]  [RTCConnection(100, default)] Remote media sink wants: {}",
])
check("latest connect for the channel", d.parse_start(text, "100"), ms(T2))
check("other channel is its own call", d.parse_start(text, "200"), ms(T3))
check("a channel never joined", d.parse_start(text, "300"), 0)
check("a stream connection is not the call", d.parse_start(L(T1, "stream", "100", "RTC_CONNECTING", "RTC_CONNECTED"), "100"), 0)
check("left the call", d.parse_start(text + "\n" + L("2026-11-15 19:30:00.000", "default", "100", "RTC_DISCONNECTED", "DISCONNECTED"), "100"), 0)
check("rejoined after leaving", d.parse_start(text + "\n" + L("2026-11-15 19:30:00.000", "default", "100", "RTC_DISCONNECTED", "DISCONNECTED")
                                              + "\n" + L("2026-11-15 19:31:00.000", "default", "100", "RTC_CONNECTING", "RTC_CONNECTED"), "100"),
      ms("2026-11-15 19:31:00.000"))

with tempfile.TemporaryDirectory() as tmp:
    a, b = os.path.join(tmp, "a.log"), os.path.join(tmp, "b.log")
    open(a, "w").write("garbage half line\n" + L(T1, "default", "100", "RTC_CONNECTING", "RTC_CONNECTED") + "\n")
    open(b, "w").write(L(T2, "default", "100", "RTC_CONNECTING", "RTC_CONNECTED") + "\n")
    check("newest across clients", d.call_start("100", [a, b, os.path.join(tmp, "missing.log")]), ms(T2))
    check("no log at all", d.call_start("100", [os.path.join(tmp, "missing.log")]), 0)
    check("no channel", d.call_start("", [a]), 0)
    env = {"XDG_CONFIG_HOME": "/x"}
    check("paths honour XDG_CONFIG_HOME", d.log_paths(env)[0], "/x/discord/logs/renderer_js.log")

print("FAILED %d" % fails if fails else "all ok")
sys.exit(1 if fails else 0)
