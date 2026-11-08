.pragma library

// ── objpack.js ────────────────────────────────────────────────────────────────
// Decoder for the packed payload the Spicy Lyrics API returns.
//
// Their endpoint does not answer with JSON. It answers with a dictionary-encoded pair:
//
//     [ valuesList, stream ]
//
//   valuesList — every distinct primitive in the document, once each
//   stream     — a flat run of integers describing the structure, where a NON-NEGATIVE
//                number is an index into valuesList and a negative number is an opcode
//
// Their client decodes it with an in-repo class (`SLObjPack`); this is an independent
// implementation of the same wire format, which is all we need to interoperate.
//
// ── The opcodes ───────────────────────────────────────────────────────────────
//   >= 0   a primitive — the value at that index of valuesList
//   -1     object      · keyCount, then keyCount key pointers, then keyCount values
//   -2     array       · length, then that many values
//   -3     schema array· length, keyCount, keyCount shared key pointers, then
//                        length × keyCount values. This is the compact form for a list
//                        of uniform records, and it is why a lyrics payload shrinks so
//                        far: every line repeats the same handful of field names, and
//                        this stores them once.
//   -4     []
//   -5     [x]         · exactly one value follows
//   -6     {}
//
// ── Why the hardening ─────────────────────────────────────────────────────────
// This parses a byte stream fetched from a third party over the network, so it is
// treated as hostile: bounded recursion (a crafted stream of nested opcodes would
// otherwise blow the JS stack), bounded counts, pointer range checks, `__proto__` and
// friends rejected as keys, and trailing data refused so nothing can be smuggled after a
// valid document. None of it costs anything on a well-formed payload.
//
// Tested by scripts/test-objpack.js — round-trip cases plus the malformed ones, which
// are the point.
// ─────────────────────────────────────────────────────────────────────────────

var MAX_DEPTH   = 64          // deeper than any real lyrics document
var MAX_COUNT   = 200000      // cap on any single length/keyCount
var MAX_DECODES = 2000000     // total values produced, so -3 cannot multiply out

// Assigning any of these as a plain key can corrupt the prototype chain of everything
// downstream. Never a legitimate field name in this payload.
var FORBIDDEN = ["__proto__", "constructor", "prototype"]

function _isInt(n) {
    return typeof n === "number" && isFinite(n) && Math.floor(n) === n
}

// ── unpack ────────────────────────────────────────────────────────────────────
// Returns the decoded document, or NULL on anything malformed. Null rather than a throw
// because every caller's response is the same — fall back to the shell's own lyrics
// lookup — and a service singleton is a bad place for an exception to escape from.
//
// `reason` is filled in on the object passed as the second argument, if given, so a
// failure can be reported without a second parse.
function unpack(packed, out) {
    function fail(why) {
        if (out) out.reason = why
        return null
    }

    if (!Array.isArray(packed) || packed.length !== 2)
        return fail("payload is not a [values, stream] pair")

    var values = packed[0]
    var stream = packed[1]

    if (!Array.isArray(values) || !Array.isArray(stream))
        return fail("values or stream is not an array")

    var valuesLen = values.length
    var streamLen = stream.length
    var cursor = 0
    var decodes = 0

    // Every entry must be a primitive. Anything else means the payload is not what we
    // think it is, and letting it through would put an object where a string belongs.
    for (var i = 0; i < valuesLen; i++) {
        var v = values[i]
        if (v === null) continue
        var t = typeof v
        if (t === "string" || t === "boolean") continue
        if (t === "number" && isFinite(v)) continue
        return fail("values[" + i + "] is " + t + ", not a primitive")
    }

    var error = null       // set by the helpers; checked after decode returns

    function read() {
        if (cursor >= streamLen) { error = "stream ended early"; return null }
        return stream[cursor++]
    }

    function resolve(ptr) {
        if (!_isInt(ptr) || ptr < 0 || ptr >= valuesLen) {
            error = "pointer " + ptr + " out of range"
            return null
        }
        return values[ptr]
    }

    function readKey() {
        var k = resolve(read())
        if (error) return null
        if (typeof k !== "string") { error = "key is not a string"; return null }
        if (FORBIDDEN.indexOf(k) >= 0) { error = "forbidden key " + k; return null }
        return k
    }

    function readCount(label) {
        var n = read()
        if (error) return -1
        if (!_isInt(n) || n < 0 || n > MAX_COUNT) {
            error = "bad " + label + " count " + n
            return -1
        }
        return n
    }

    function decode(depth) {
        if (error) return null
        if (depth > MAX_DEPTH) { error = "max depth exceeded"; return null }
        if (++decodes > MAX_DECODES) { error = "decode budget exceeded"; return null }

        var op = read()
        if (error) return null
        if (!_isInt(op)) { error = "opcode is not an integer: " + op; return null }
        if (op >= 0) return resolve(op)

        var n, k, keys, arr, obj, j

        switch (op) {
            case -1:                                   // object
                n = readCount("object key")
                if (error) return null
                keys = []
                for (j = 0; j < n; j++) {
                    keys.push(readKey())
                    if (error) return null
                }
                obj = {}
                for (j = 0; j < n; j++) {
                    obj[keys[j]] = decode(depth + 1)
                    if (error) return null
                }
                return obj

            case -2:                                   // array
                n = readCount("array length")
                if (error) return null
                arr = []
                for (j = 0; j < n; j++) {
                    arr.push(decode(depth + 1))
                    if (error) return null
                }
                return arr

            case -3:                                   // schema array
                n = readCount("schema array length")
                if (error) return null
                k = readCount("schema key")
                if (error) return null

                // The one place counts multiply, so it gets its own budget check before
                // any allocation happens.
                if (n * k > MAX_DECODES) { error = "schema array too large"; return null }

                keys = []
                for (j = 0; j < k; j++) {
                    keys.push(readKey())
                    if (error) return null
                }

                arr = []
                for (j = 0; j < n; j++) {
                    var rec = {}
                    for (var m = 0; m < k; m++) {
                        rec[keys[m]] = decode(depth + 1)
                        if (error) return null
                    }
                    arr.push(rec)
                }
                return arr

            case -4: return []
            case -5:
                var one = decode(depth + 1)
                return error ? null : [one]
            case -6: return {}

            default:
                error = "unknown opcode " + op
                return null
        }
    }

    var result = decode(0)
    if (error) return fail(error)

    // Anything after a complete document means the payload is not what it claims.
    if (cursor !== streamLen)
        return fail("trailing data: " + (streamLen - cursor) + " slots unread")

    return result
}
