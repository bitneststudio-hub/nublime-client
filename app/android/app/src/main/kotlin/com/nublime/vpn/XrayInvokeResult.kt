package com.nublime.vpn

import org.json.JSONArray
import org.json.JSONObject

/**
 * Parsed result of a libXray `invoke(String) -> String` call.
 *
 * Contract basis (05_审核请求/response_samples_REDACTED.md):
 *   success: {"success":true,"data":{},"error":""}
 *   failure: {"success":false,"data":null,"error":"infra/conf/…"}
 *
 * v2 (Astra R01-commit1 review §3):
 *  - strict JSON syntax validation (no bare keys, no single quotes, no comments, no trailing junk)
 *  - decoded **top-level** duplicate-key detection (`succe\u0073s` ≡ `success`); nested payload untouched
 *  - explicit wrapper type contract for `success` / `error`
 *  - no exception may escape `parse`
 *  - **no core-provided text is ever surfaced** — messages are predefined per failure kind
 */
sealed class XrayInvokeResult {
    /** Wrapper parsed; `success` was an exact JSON boolean true. `data` exposed opaquely. */
    data class Accepted(val dataJson: String?, val hasDataField: Boolean) : XrayInvokeResult()

    /** Failure with a controlled code and a **predefined** (content-free) message. */
    data class Failed(val kind: FailureKind, val safeMessage: String) : XrayInvokeResult()
}

enum class FailureKind {
    EMPTY, MALFORMED, TRAILING_DATA, WRONG_TOP_TYPE, MISSING_FIELD,
    TYPE_ERROR, DUPLICATE_FIELD, EXPLICIT_FAILURE, CONFLICT, UNKNOWN
}

object XrayInvokeParser {

    fun safeMessageFor(kind: FailureKind): String = when (kind) {
        FailureKind.EMPTY -> "core returned an empty response"
        FailureKind.MALFORMED -> "core response was not valid JSON"
        FailureKind.TRAILING_DATA -> "core response contained trailing data"
        FailureKind.WRONG_TOP_TYPE -> "core response was not a JSON object"
        FailureKind.MISSING_FIELD -> "core response lacked the success field"
        FailureKind.TYPE_ERROR -> "core response field type was invalid"
        FailureKind.DUPLICATE_FIELD -> "core response repeated a control field"
        FailureKind.EXPLICIT_FAILURE -> "core reported a startup failure"
        FailureKind.CONFLICT -> "core response was self-contradictory"
        FailureKind.UNKNOWN -> "core response could not be interpreted"
    }

    fun parse(raw: String?): XrayInvokeResult = try {
        parseInternal(raw)
    } catch (t: Throwable) {
        failed(FailureKind.MALFORMED)   // contract: nothing escapes
    }

    private fun failed(kind: FailureKind) = XrayInvokeResult.Failed(kind, safeMessageFor(kind))

    private fun parseInternal(raw: String?): XrayInvokeResult {
        if (raw == null || raw.isBlank()) return failed(FailureKind.EMPTY)

        // 1) strict syntax + decoded top-level key collection
        when (val scan = StrictJson.scan(raw)) {
            is StrictJson.Result.Invalid -> return failed(FailureKind.MALFORMED)
            is StrictJson.Result.Trailing -> return failed(FailureKind.TRAILING_DATA)
            is StrictJson.Result.Ok -> {
                if (!scan.topIsObject) return failed(FailureKind.WRONG_TOP_TYPE)
                // §3.2: ALL control fields that decide success/failure must be unique after decoding.
                // (Duplicate `error` can otherwise overwrite a failure body and let a bad response pass
                // on lenient Android-side implementations.)
                if (scan.topLevelKeys.count { it == "success" } > 1) return failed(FailureKind.DUPLICATE_FIELD)
                if (scan.topLevelKeys.count { it == "error" } > 1) return failed(FailureKind.DUPLICATE_FIELD)
            }
        }

        // 2) structure access (input is proven strict JSON at this point)
        val top = JSONObject(raw)

        if (!top.has("success")) return failed(FailureKind.MISSING_FIELD)
        val successValue = top.opt("success")
        if (successValue !is Boolean) return failed(FailureKind.TYPE_ERROR)

        // 3) wrapper field contract for `error`
        val errorPresent = top.has("error")
        val errorValue = if (errorPresent) top.opt("error") else null
        // §3.3: distinguish missing / JSON null / empty string / non-empty string / wrong type.
        val errorIsJsonNull = errorValue == null || errorValue === JSONObject.NULL
        if (errorPresent && !errorIsJsonNull && errorValue !is String) {
            // object / array / number / boolean error is a contract violation — never success
            return failed(FailureKind.TYPE_ERROR)
        }
        val errorIsNonEmptyString = errorValue is String && errorValue.isNotEmpty()

        if (!successValue) return failed(FailureKind.EXPLICIT_FAILURE)
        if (errorIsNonEmptyString) return failed(FailureKind.CONFLICT)

        val hasData = top.has("data")
        return XrayInvokeResult.Accepted(if (hasData) normalizeData(top.opt("data")) else null, hasData)
    }

    /** Method payload rules stay isolated (§3.1): opaque passthrough, no validation. */
    private fun normalizeData(value: Any?): String? = when (value) {
        null -> null
        is JSONObject, is JSONArray, is String -> value.toString()
        else -> value.toString()
    }
}

/**
 * Minimal strict-JSON (RFC 8259) scanner.
 *
 * org.json's JSONTokener is lenient (bare keys, single quotes, comments); library acceptance is
 * therefore not proof of strict JSON. This scanner enforces strict syntax and, while walking the
 * **top level**, records decoded key names so escaped-equivalent duplicates are detected.
 */
internal object StrictJson {

    sealed class Result {
        object Invalid : Result()
        object Trailing : Result()
        data class Ok(val topIsObject: Boolean, val topLevelKeys: List<String>) : Result()
    }

    fun scan(text: String): Result {
        val s = Scanner(text)
        return try {
            s.skipWs()
            if (s.eof()) return Result.Invalid
            val topIsObject = s.peek() == '{'
            s.parseValue(0)
            s.skipWs()
            if (!s.eof()) return Result.Trailing
            Result.Ok(topIsObject, s.topLevelKeys.toList())
        } catch (e: Violation) {
            Result.Invalid
        }
    }

    private class Violation : Exception()

    private class Scanner(private val text: String) {
        private var i = 0
        private val n = text.length
        val topLevelKeys = mutableListOf<String>()

        fun eof() = i >= n
        fun peek(): Char = if (i < n) text[i] else throw Violation()

        fun skipWs() {
            while (i < n) {
                val c = text[i]
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') i++ else break
            }
        }

        private fun expect(c: Char) {
            if (eof() || text[i] != c) throw Violation()
            i++
        }

        fun parseValue(depth: Int) {
            skipWs()
            if (eof()) throw Violation()
            when (text[i]) {
                '{' -> parseObject(depth)
                '[' -> parseArray(depth)
                '"' -> decodeString()
                't' -> literal("true")
                'f' -> literal("false")
                'n' -> literal("null")
                '-' -> parseNumber()
                in '0'..'9' -> parseNumber()
                else -> throw Violation()
            }
        }

        private fun parseObject(depth: Int) {
            expect('{')
            skipWs()
            if (!eof() && text[i] == '}') { i++; return }
            while (true) {
                skipWs()
                if (eof() || text[i] != '"') throw Violation()   // strict: keys must be double-quoted strings
                val key = decodeString()
                if (depth == 0) topLevelKeys.add(key)
                skipWs()
                expect(':')
                parseValue(depth + 1)
                skipWs()
                if (eof()) throw Violation()
                when (text[i]) {
                    ',' -> { i++ }
                    '}' -> { i++; return }
                    else -> throw Violation()
                }
            }
        }

        private fun parseArray(depth: Int) {
            expect('[')
            skipWs()
            if (!eof() && text[i] == ']') { i++; return }
            while (true) {
                parseValue(depth + 1)
                skipWs()
                if (eof()) throw Violation()
                when (text[i]) {
                    ',' -> { i++ }
                    ']' -> { i++; return }
                    else -> throw Violation()
                }
            }
        }

        /** Decodes a JSON string (incl. \\uXXXX) and returns its decoded value. */
        private fun decodeString(): String {
            expect('"')
            val sb = StringBuilder()
            while (true) {
                if (eof()) throw Violation()
                val c = text[i++]
                when {
                    c == '"' -> return sb.toString()
                    c == '\\' -> {
                        if (eof()) throw Violation()
                        when (val e = text[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > n) throw Violation()
                                val hex = text.substring(i, i + 4)
                                for (ch in hex) {
                                    // ASCII-only hex (rejects full-width / non-ASCII digits)
                                    if (!(ch in '0'..'9' || ch in 'a'..'f' || ch in 'A'..'F')) throw Violation()
                                }
                                sb.append(hex.toInt(16).toChar())
                                i += 4
                            }
                            else -> throw Violation()
                        }
                    }
                    else -> {
                        if (c.code < 0x20) throw Violation()   // raw control chars must be escaped
                        sb.append(c)
                    }
                }
            }
        }

        private fun literal(lit: String) {
            if (i + lit.length > n || text.substring(i, i + lit.length) != lit) throw Violation()
            i += lit.length
        }

        private fun parseNumber() {
            if (!eof() && text[i] == '-') i++
            if (eof()) throw Violation()
            when {
                text[i] == '0' -> i++
                text[i] in '1'..'9' -> while (!eof() && text[i] in '0'..'9') i++
                else -> throw Violation()
            }
            if (!eof() && text[i] == '.') {
                i++
                if (eof() || text[i] !in '0'..'9') throw Violation()
                while (!eof() && text[i] in '0'..'9') i++
            }
            if (!eof() && (text[i] == 'e' || text[i] == 'E')) {
                i++
                if (!eof() && (text[i] == '+' || text[i] == '-')) i++
                if (eof() || text[i] !in '0'..'9') throw Violation()
                while (!eof() && text[i] in '0'..'9') i++
            }
        }
    }
}
