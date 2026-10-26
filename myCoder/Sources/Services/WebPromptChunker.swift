import Foundation

/// Detection and handling of web-model session limits (Kimi/Qwen/ChatGPT often
/// cap conversation length). Plan Раздел 12 — extension: split large prompts and
/// restart the session with carried-over context when the model reports a limit.

enum WebSessionLimitLogic {
    /// Phrases various web models emit when a conversation is too long.
    /// Matched case-insensitively against the latest response text.
    static let limitMarkers: [String] = [
        "conversation with kimi is getting too long",
        "getting too long",
        "try starting a new session",
        "start a new chat",
        "conversation is too long",
        "maximum context length",
        "context length exceeded",
        "this chat has reached its limit",
        "会话过长",              // zh: conversation too long
        "対話が長すぎます",       // ja: conversation too long
        "대화가 너무 깁니다"      // ko: conversation too long
    ]

    /// True when a response indicates the session must be restarted.
    static func isSessionLimitReached(responseText: String) -> Bool {
        let haystack = responseText.lowercased()
        return limitMarkers.contains { haystack.contains($0.lowercased()) }
    }

    /// Build a compact carry-over context to seed a fresh session after a limit
    /// (plan Блок 2 п.21 reinjection). Keeps the tool preamble + a short summary
    /// of the goal and the last few exchanges — NOT the whole transcript (that's
    /// what overflowed). The summary is provided by the caller (e.g. from goal +
    /// recent tool results), never fabricated here.
    static func carryOverSeed(systemPreamble: String, goal: String?, recentSummary: String) -> String {
        var parts: [String] = [systemPreamble]
        if let goal = goal, !goal.isEmpty {
            parts.append("Current goal: \(goal)")
        }
        if !recentSummary.isEmpty {
            parts.append("Context so far (continue from here):\n\(recentSummary)")
        }
        return parts.joined(separator: "\n\n---\n\n")
    }
}

/// Splits a large PROMPT into several messages semantically (plan Раздел 12
/// extension). This is a prompt, not arbitrary text: we must not cut mid-token
/// or mid-structure. We split on safe semantic boundaries (paragraphs, then
/// sentences), never inside fenced code / tool blocks, and wrap parts with a
/// continuation protocol so the model waits for the final part before answering.
enum WebPromptChunker {
    /// Approx character budget per message (well under typical web limits).
    /// Audit 2026-09-08: byte-based (see `split`) so a Cyrillic prompt can not
    /// blow past Kimi's ~4000-byte paste limit (it silently converts larger
    /// pastes to a .txt attachment, breaking the tool-preamble contract).
    /// Audit 2026-09-09 (Qwen live): the fixed tool-protocol preamble alone
    /// is ~1800 bytes; with the first question a normal first turn lands
    /// at ~2000 bytes, which the old 1900 budget split into 2 messages —
    /// and the continuation-protocol part 1 (the tool contract itself!)
    /// was lost in transit, so the model answered "I have no list_dir tool".
    /// Raise the budget to 3800 bytes: a first turn stays ONE message with
    /// the full preamble inside it, still under Kimi's 4000-byte limit.
    static let defaultBudget = 3800

    /// Continuation markers the preamble teaches the model to honor.
    static let continuationHeader = "[PART %d/%d — do not answer yet, wait for the final part]"
    static let finalHeader = "[FINAL PART %d/%d — you may now respond]"

    /// Split a prompt into ordered message parts. If it fits the budget, returns
    /// a single element (unwrapped). Never splits inside a fenced block.
    /// The budget is enforced on UTF-8 BYTES, not characters: live Kimi
    /// (audit 2026-09-08) turns any paste over ~4000 bytes into a .txt
    /// attachment, and a 6000-character Cyrillic prompt is 12000 bytes.
    static func split(_ prompt: String, budget: Int = defaultBudget) -> [String] {
        guard prompt.data(using: .utf8)?.count ?? prompt.count > budget else { return [prompt] }
        let segments = semanticSegments(prompt)
        var chunks: [String] = []
        var current = ""
        func currentBytes() -> Int { current.data(using: .utf8)?.count ?? current.count }
        func segBytes(_ s: String) -> Int { s.data(using: .utf8)?.count ?? s.count }
        for seg in segments {
            if segBytes(seg) > budget {
                // A single oversized segment (e.g. a huge code block): flush
                // current, then hard-split the segment on line boundaries only
                // (still not mid-line/mid-token).
                if !current.isEmpty { chunks.append(current); current = "" }
                chunks.append(contentsOf: hardSplitByLines(seg, budget: budget))
                continue
            }
            if currentBytes() + segBytes(seg) + 2 > budget {
                chunks.append(current)
                current = seg
            } else {
                current = current.isEmpty ? seg : current + "\n\n" + seg
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Wrap chunks with the continuation protocol (headers), so the model knows
    /// to wait until the final part (plan: split prompt without normal text tools).
    static func wrapForContinuation(_ chunks: [String]) -> [String] {
        guard chunks.count > 1 else { return chunks }
        let total = chunks.count
        return chunks.enumerated().map { idx, chunk in
            let n = idx + 1
            let header = n == total ? String(format: finalHeader, n, total)
                                    : String(format: continuationHeader, n, total)
            return header + "\n" + chunk
        }
    }

    /// Convenience: split + wrap in one call. The continuation headers are
    /// added AFTER splitting, so the splitter reserves their byte overhead —
    /// otherwise a chunk at exactly the budget becomes over-budget once its
    /// "[PART 1/2 — do not answer yet…]" header is prepended (audit
    /// 2026-09-09: a 3800-byte chunk grew to 3858 bytes wrapped).
    static func chunkedMessages(_ prompt: String, budget: Int = defaultBudget) -> [String] {
        let headerOverhead = String(format: continuationHeader, 99, 99).utf8.count + 1
        return wrapForContinuation(split(prompt, budget: max(budget - headerOverhead, 256)))
    }

    // MARK: - Semantic segmentation

    /// Break text into segments on paragraph boundaries, keeping fenced code
    /// blocks (``` ... ```) intact as single segments.
    static func semanticSegments(_ text: String) -> [String] {
        var segments: [String] = []
        var buffer: [String] = []
        var inFence = false
        var fenceBuffer: [String] = []

        func flushBuffer() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                // Further split the paragraph buffer on blank lines.
                for para in joined.components(separatedBy: "\n\n") where !para.isEmpty {
                    segments.append(para)
                }
            }
            buffer.removeAll()
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inFence {
                    fenceBuffer.append(line)
                    segments.append(fenceBuffer.joined(separator: "\n"))  // whole fence = one segment
                    fenceBuffer.removeAll()
                    inFence = false
                } else {
                    flushBuffer()
                    fenceBuffer.append(line)
                    inFence = true
                }
            } else if inFence {
                fenceBuffer.append(line)
            } else {
                buffer.append(line)
            }
        }
        if inFence { segments.append(fenceBuffer.joined(separator: "\n")) }  // unterminated fence
        flushBuffer()
        return segments
    }

    /// Split an oversized segment on line boundaries only (never mid-line).
    /// Byte-aware like `split` (a Cyrillic line counts double in UTF-8).
    /// A single line longer than the budget is hard-cut by CHARACTERS — the
    /// paste budget is a hard vendor limit (Kimi .txt-attachment), and a
    /// mid-word cut is preferable over an over-budget message.
    static func hardSplitByLines(_ segment: String, budget: Int) -> [String] {
        var result: [String] = []
        var current = ""
        func bytes(_ s: String) -> Int { s.data(using: .utf8)?.count ?? s.count }
        for line in segment.components(separatedBy: "\n") {
            if bytes(line) > budget {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(contentsOf: hardSplitByBytes(line, budget: budget))
                continue
            }
            if bytes(current) + bytes(line) + 1 > budget && !current.isEmpty {
                result.append(current)
                current = line
            } else {
                current = current.isEmpty ? line : current + "\n" + line
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Cut one line into consecutive substrings each within the byte budget.
    /// Operates on UTF-8 scalars so multi-byte characters are never torn.
    private static func hardSplitByBytes(_ line: String, budget: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for scalar in line.unicodeScalars {
            var candidate = current
            candidate.unicodeScalars.append(scalar)
            if (candidate.data(using: .utf8)?.count ?? 0) > budget && !current.isEmpty {
                chunks.append(current)
                current = String(scalar)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
