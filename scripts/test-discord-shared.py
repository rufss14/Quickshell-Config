#!/usr/bin/env python3
"""The zero-setup Discord sign-in: which identity wins, and how its token is handled.

Fully mocked: no network, no Discord, no real config or token cache. Imports
discord-rpc.py with its paths pointed at a temp dir.
"""
import importlib.util, io, json, os, sys, tempfile, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp(prefix="discord-shared-")
cfg_dir, cache_dir = os.path.join(tmp, "cfg"), os.path.join(tmp, "cache")
for d in (os.path.join(cfg_dir, "quicktest"), os.path.join(cache_dir, "quicktest")):
    os.makedirs(d)
os.environ.update(XDG_CONFIG_HOME=cfg_dir, XDG_CACHE_HOME=cache_dir,
                  XDG_STATE_HOME=os.path.join(tmp, "state"))   # qspaths: keep it off the real one

spec = importlib.util.spec_from_file_location("rpc", os.path.join(ROOT, "scripts/discord-rpc.py"))
rpc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rpc)


def write_cfg(obj):
    with open(rpc.CONFIG_PATH, "w") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj))


def check(cond, msg):
    if not cond:
        sys.exit("FAIL: " + msg)
    print("  ok ", msg)


# ── which identity ────────────────────────────────────────────────────────────
check(rpc.load_config()["clientId"] == rpc.SHARED_CLIENT_ID and rpc.load_config()["shared"],
      "no config file → shared identity")
write_cfg({})
check(rpc.load_config().get("shared") is True, "empty config → shared identity")
write_cfg({"clientId": "123", "clientSecret": "s"})
c = rpc.load_config()
check(c["clientId"] == "123" and not c.get("shared"), "own app wins over the shared one")
write_cfg({"clientId": "123"})
check(rpc.load_config()["clientId"] == rpc.SHARED_CLIENT_ID,
      "own client id without its secret is not enough → shared")
write_cfg({"sharedApp": False})
check(rpc.load_config() is None, "sharedApp:false and no own app → no-credentials")
write_cfg({"sharedApp": False, "clientId": "123", "clientSecret": "s"})
check(rpc.load_config()["clientId"] == "123", "sharedApp:false does not touch an own app")
write_cfg("{not json")
check(rpc.load_config() is None, "unparseable config is not papered over with the shared id")
write_cfg({"keys": {"camera": "x"}})
check(rpc.load_config()["keys"] == {"camera": "x"}, "other keys survive in shared mode")

# ── token cache is per client id ──────────────────────────────────────────────
def put_token(tok):
    with open(rpc.TOKEN_PATH, "w") as f:
        json.dump(tok, f)


put_token({"access_token": "a", "client_id": "123"})
check(rpc.load_token("123")["access_token"] == "a", "token for the same client id is reused")
check(rpc.load_token(rpc.SHARED_CLIENT_ID) is None, "own-app token is not replayed to the shared app")
put_token({"access_token": "legacy"})
check(rpc.load_token("123")["access_token"] == "legacy", "unstamped (older) token is still tried")

# ── the proxy exchange ────────────────────────────────────────────────────────
seen = {}


class Resp(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *a): return False


def fake_urlopen(body):
    def f(req, timeout=None):
        seen["url"], seen["data"] = req.full_url, json.loads(req.data)
        seen["ct"], seen["ua"] = req.get_header("Content-type"), req.get_header("User-agent")
        return Resp(json.dumps(body).encode())
    return f


real = urllib.request.urlopen
urllib.request.urlopen = fake_urlopen({"access_token": "tok"})
shared = {"clientId": rpc.SHARED_CLIENT_ID, "shared": True}
t = rpc.exchange_token(shared, code="CODE")
check(t["access_token"] == "tok" and t["expires_at"] > time.time() + 86400, "exchange returns a token with an expiry")
check(seen["url"] == rpc.SHARED_TOKEN_URL and seen["data"] == {"code": "CODE"},
      "posts only the code to the proxy")
check("secret" not in json.dumps(seen["data"]), "no client secret is sent")
check(seen["ct"] == "application/json" and "Mozilla" in seen["ua"],
      "JSON body and a browser User-Agent (Cloudflare)")
check(rpc.exchange_token(shared, refresh_token="r") is None, "a refresh request just fails over (no refresh token exists)")
urllib.request.urlopen = fake_urlopen({"error": "nope"})
check(rpc.exchange_token(shared, code="CODE") is None, "a reply without access_token is a failure")
urllib.request.urlopen = real

print("\nPASSED")
