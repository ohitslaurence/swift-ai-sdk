import Foundation

/// Built-in repair functions and retry prompt logic for structured output.
enum StructuredOutputRepair {

    /// The stable retry prompt template.
    static func retryPrompt(error: String) -> String {
        "Your previous response was not valid JSON matching the schema. "
            + "Error: \(error). Return only valid JSON that matches the schema exactly."
    }

    /// Attempt built-in repairs on raw text, in order:
    /// 1. Strip Markdown fences
    /// 2. Trim leading/trailing non-JSON characters
    /// 3. Extract the outermost JSON object or array
    static func attemptBuiltInRepair(_ text: String) -> String? {
        let repairs: [(String) -> String?] = [
            stripMarkdownFences,
            trimNonJSONCharacters,
            extractOutermostJSON,
        ]

        for repair in repairs {
            if let repaired = repair(text) {
                if isValidJSON(repaired) {
                    return repaired
                }
            }
        }

        return nil
    }

    /// Strip Markdown code fences (```json ... ``` or ``` ... ```).
    static func stripMarkdownFences(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let fencePattern = #"^```(?:\w+)?\s*\n?([\s\S]*?)\n?\s*```$"#
        guard let regex = try? NSRegularExpression(pattern: fencePattern, options: []) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
            let contentRange = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }

        let content = String(trimmed[contentRange]).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return content.isEmpty ? nil : content
    }

    /// Trim leading/trailing non-JSON characters.
    static func trimNonJSONCharacters(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstJSON = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }),
            let lastJSON = trimmed.lastIndex(where: { $0 == "}" || $0 == "]" })
        else {
            return nil
        }

        guard firstJSON <= lastJSON else { return nil }

        let extracted = String(trimmed[firstJSON...lastJSON])
        return extracted == trimmed ? nil : extracted
    }

    /// Extract the outermost JSON object or array from surrounding prose.
    static func extractOutermostJSON(_ text: String) -> String? {
        if let result = extractBalanced(from: text, open: "{", close: "}") {
            return result
        }
        return extractBalanced(from: text, open: "[", close: "]")
    }

    private static func extractBalanced(
        from text: String,
        open: Character,
        close: Character
    ) -> String? {
        guard let startIdx = text.firstIndex(of: open) else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var endIdx: String.Index?

        for idx in text.indices[startIdx...] {
            let char = text[idx]

            if escaped {
                escaped = false
                continue
            }

            if char == "\\" && inString {
                escaped = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                continue
            }

            if inString { continue }

            if char == open {
                depth += 1
            } else if char == close {
                depth -= 1
                if depth == 0 {
                    endIdx = idx
                    break
                }
            }
        }

        guard let end = endIdx else { return nil }
        let result = String(text[startIdx...end])
        return result == text.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : result
    }

    private static func isValidJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
