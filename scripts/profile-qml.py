# gdb script, run through scripts/profile-qml.sh — not directly.
#
# Samples the shell's main thread N times. At each stop it asks the QML engine for its OWN
# JavaScript stack (qt_v4StackTraceForEngine, which Qt exports for debuggers), so the answer
# is a QML file and line rather than a C++ frame. Prints which handlers/bindings were running
# most often.
#
# Reads from the environment: QSP_PID (attach) or QSP_RUN=1 (gdb launched the program), QSP_SAMPLES (default 60), QSP_GAP seconds (0.15).
#
# Safety: the call runs inside the stopped main thread, so it would deadlock if that thread was
# stopped holding the allocator's lock. Samples whose innermost frames are in the allocator or a
# lock are skipped (counted as "skipped"). It always detaches at the end.
import collections
import os
import re
import subprocess

import gdb

RUN = os.environ.get("QSP_RUN") == "1"      # started by gdb itself (gdb --args …): we are its parent
PID = int(os.environ.get("QSP_PID", "0"))
N = int(os.environ.get("QSP_SAMPLES", "60"))
GAP = os.environ.get("QSP_GAP", "0.15")

LOCKY = re.compile(r"malloc|calloc|realloc|free|^je_|jemalloc|_int_|arena|tcache|mutex|futex|"
                   r"pthread_cond|QMutex|QWaitCondition|QReadWriteLock|__lll|sem_wait", re.I)

# auto-solib-add off: do NOT read symbols (and so download debug info) for every library the
# process has loaded — Widgets alone is 167 MB. Only the three that the answer needs are loaded below.
for cmd in ("set pagination off", "set confirm off", "set print thread-events off",
            "set auto-solib-add off", "set debuginfod enabled on", "set verbose off",
            # The interrupt that ends each sample is a SIGINT. gdb must STOP on it and never hand it
            # to the process, or the sampled program would exit.
            "handle SIGINT stop print nopass",
            # If a call into the process is ever cut short by a signal, put the registers back
            # instead of leaving the process stranded inside the helper.
            "set unwind-on-signal on", "set unwind-on-terminating-exception on"):
    gdb.execute(cmd, to_string=True)


def load_symbols():
    for lib in (r"libc\.so", r"libQt6Core\.so", r"libQt6Qml\.so", r"libQt6Quick\.so", r"libQt6QuickShapes", r"libQt6Gui\.so",
                r"libQt6QuickEffects", r"libQt6ShaderTools"):
        try:
            gdb.execute("sharedlibrary " + lib, to_string=True)
        except gdb.error:
            pass

def interrupt_after(seconds):
    """A SIGINT to ourselves in `seconds` (what ^C does): ends a `continue`. Returns the timer."""
    return subprocess.Popen(["sh", "-c", "sleep %s; kill -INT %d" % (seconds, os.getpid())])


def disarm(timer):
    """Kill a pending interrupt and wait for it, so none can land in the middle of a call."""
    if timer is not None:
        try:
            timer.kill()
        except Exception:
            pass
        timer.wait()


if RUN:
    # Let the program start and settle for QSP_WARMUP seconds, then stop it with a self-sent SIGINT.
    timer = interrupt_after(os.environ.get("QSP_WARMUP", "4"))
    try:
        gdb.execute("run", to_string=True)
    except BaseException:
        pass
    disarm(timer)
    PID = gdb.selected_inferior().pid
else:
    gdb.execute("attach %d" % PID, to_string=True)
load_symbols()


def main_thread():
    for th in gdb.selected_inferior().threads():
        if th.ptid[1] == PID:
            return th
    return None


def find_engine():
    """A QV4::ExecutionEngine* from any frame that still has one in debug info, else 0."""
    f, depth = gdb.newest_frame(), 0
    while f is not None and depth < 80:
        try:
            f.select()
            b = f.block()
        except Exception:
            b = None
        while b is not None and not b.is_global and not b.is_static:
            for sym in b:
                if not (sym.is_variable or sym.is_argument):
                    continue
                try:
                    t = str(sym.type.strip_typedefs())
                except Exception:
                    continue
                if "ExecutionEngine" in t and t.endswith("*"):
                    try:
                        v = sym.value(f)
                        if not v.is_optimized_out and int(v) != 0:
                            return int(v)
                    except Exception:
                        pass
            b = b.superblock
        f, depth = f.older(), depth + 1
    return 0


def leaf_names(k=8):
    names, f = [], gdb.newest_frame()
    while f is not None and len(names) < k:
        # Symbols for the allocator may be missing (debuginfod unreachable, or its cache is root-owned),
        # leaving only "?" — so ALSO judge by the library the frame's pc is in. A call into the process
        # from inside jemalloc deadlocks it (measured 2026-11-02: the sampler hung for good).
        try:
            lib = gdb.solib_name(f.pc()) or ""
        except Exception:
            lib = ""
        names.append((f.name() or "?") + (" " + lib if "jemalloc" in lib else ""))
        f = f.older()
    return names


# qt_v4StackTraceForEngine answers in gdb/MI form:
#   stack=[frame={level="0",func="expression for onTriggered",file="…/X.qml",fullname="…",line="13",…},…]
FRAME = re.compile(r'frame=\{level="\d+",func="(.*?)",file="(.*?)",fullname=".*?",line="(\d+)"')


def label(m):
    func, path, line = m
    path = path.split("/quicktest/", 1)[-1]
    return "%s   %s:%s" % (func, path, line)


engine = 0
top = collections.Counter()      # innermost JS frame
whole = collections.Counter()    # any JS frame on the stack
idle = skipped = failed = 0
examples = []
cpp = collections.Counter()      # C++ function on the stack (exported symbols only), any sample


def cpp_stack(depth=60):
    seen, f, n = set(), gdb.newest_frame(), 0
    while f is not None and n < depth:
        nm = f.name()
        if nm and nm not in seen:
            seen.add(nm)
        f, n = f.older(), n + 1
    return seen

for i in range(N):
    th = main_thread()
    if th is not None:
        th.switch()
    try:
        for nm in cpp_stack():
            cpp[nm] += 1
    except Exception:
        pass
    if any(LOCKY.search(n) for n in leaf_names()):
        skipped += 1
    else:
        try:
            if not engine:
                engine = find_engine()
            if not engine:
                failed += 1
            else:
                v = gdb.parse_and_eval("(const char *) qt_v4StackTraceForEngine((void *) %d)" % engine)
                s = v.string() if int(v) else ""
                lines = [label(m) for m in FRAME.findall(s)]
                if not lines:
                    idle += 1
                else:
                    top[lines[0]] += 1
                    for l in set(lines):
                        whole[l] += 1
                    if len(examples) < 3:
                        examples.append(lines[:6])
        except Exception as e:
            failed += 1
            if failed <= 2:
                print("sample failed: %s" % e)
    # Let it run for GAP seconds, then interrupt it with a SIGINT sent to ourselves (what ^C does).
    timer = interrupt_after(GAP)
    try:
        gdb.execute("continue", to_string=True)
    except BaseException:
        pass
    disarm(timer)   # before the next sample's call, whatever stopped us

try:
    # A run we started ourselves (QSP_RUN) is a throwaway: leaving it running after the sampler exits
    # (a detach) strands a second shell on the desktop.
    gdb.execute("kill" if RUN else "detach", to_string=True)
except BaseException:
    pass

js = sum(top.values())
print("\n=== QSP RESULT ===")
print("%d samples: %d in JS, %d not in JS (idle/native), %d skipped (allocator/lock), %d failed"
      % (N, js, idle, skipped, failed))
print("engine at 0x%x" % engine if engine else "no engine pointer found (debug info missing?)")
print("\n── innermost JS frame (what was running) ──")
for k, c in top.most_common(15):
    print("%4d  %s" % (c, k))
print("\n── any JS frame on the stack ──")
for k, c in whole.most_common(15):
    print("%4d  %s" % (c, k))
print("\n── C++ functions on the stack, every sample (inclusive) ──")
for k, c in cpp.most_common(45):
    print("%4d  %s" % (c, k[:110]))
if examples:
    print("\n── example stacks ──")
    for ex in examples:
        print("\n".join("  " + x for x in ex))
        print()
