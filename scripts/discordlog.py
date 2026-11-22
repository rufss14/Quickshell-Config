"""When did the Discord call actually connect? Discord's RPC never says, but its own renderer log does.

The desktop client logs every voice connection's state changes, with a local timestamp:

    [2026-11-15 19:20:43.181] [info]  [RTCConnection(<channel id>, default)] RTC connection state: RTC_CONNECTING => RTC_CONNECTED
    [2026-11-15 19:25:01.002] [info]  [RTCConnection(<channel id>, default)] RTC connection state: RTC_DISCONNECTED => DISCONNECTED

`default` is the voice call; Go Live and watching a stream are separate `stream` connections and are ignored.
The channel id is the same id the RPC reports as the selected voice channel (a DM call's channel is the DM).

Start of the call = the last RTC_CONNECTED for that channel that no later DISCONNECTED ended. Only the tail of the
log is read (it is rotated at about 10 MB and a call that long is the exception). A client that does not write this
log (Vesktop, WebCord, ...) simply yields 0, and the shell falls back to when it first saw the call.
"""
import os, re, time

# Official client and its release channels; each keeps its logs under <config>/<name>/logs/.
CLIENT_DIRS = ("discord", "discordptb", "discordcanary", "discorddevelopment")
LOG_NAME = "renderer_js.log"
TAIL_BYTES = 3_000_000

_LINE = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.(\d{3})\]\s+\[\w+\]\s+"
                   r"\[RTCConnection\((\d+), default\)\] RTC connection state: \w+ => (\w+)")


def log_paths(env=None):
    env = os.environ if env is None else env
    base = env.get("XDG_CONFIG_HOME") or os.path.join(env.get("HOME", ""), ".config")
    return [os.path.join(base, d, "logs", LOG_NAME) for d in CLIENT_DIRS]


def parse_start(text, channel_id):
    """ms since the epoch of the connected state that is still current for channel_id, or 0."""
    start = 0
    for line in text.splitlines():
        if "RTC connection state" not in line:
            continue
        m = _LINE.match(line)
        if not m or m.group(3) != channel_id:
            continue
        state = m.group(4)
        if state == "RTC_CONNECTED":
            # The log is local time, naive; mktime reads it as such (isdst -1: let the system decide).
            t = time.mktime(time.strptime(m.group(1), "%Y-%m-%d %H:%M:%S"))
            start = int(t * 1000) + int(m.group(2))
        elif state == "DISCONNECTED":
            start = 0
    return start


def call_start(channel_id, paths=None):
    """The newest call start across the installed clients' logs, or 0 when none says."""
    if not channel_id:
        return 0
    best = 0
    for path in (paths if paths is not None else log_paths()):
        try:
            with open(path, "rb") as f:
                f.seek(0, os.SEEK_END)
                f.seek(max(0, f.tell() - TAIL_BYTES))
                text = f.read().decode("utf-8", "replace")
        except OSError:
            continue
        best = max(best, parse_start(text, str(channel_id)))
    return best
