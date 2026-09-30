import Foundation

enum TodoAgentMention {
    struct Query {
        let range: NSRange
        let text: String
    }

    // Keep tags compatible with packages/domain/src/agentMentions.ts.
    static func tag(for name: String) -> String {
        let slug = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "@\(slug)"
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    static func query(in text: String, caret: Int) -> Query? {
        let value = text as NSString
        guard caret >= 0, caret <= value.length else { return nil }
        let prefix = value.substring(to: caret)
        guard let match = prefix.range(of: "(?:^|\\s)(@[a-zA-Z0-9_-]*)$", options: .regularExpression) else { return nil }
        let token = prefix[match].trimmingCharacters(in: .whitespacesAndNewlines)
        let start = caret - token.utf16.count
        let suffix = value.substring(from: caret)
        let remainder = suffix.range(of: "^[a-zA-Z0-9_-]*", options: .regularExpression)
            .map { suffix[$0].utf16.count } ?? 0
        return Query(range: NSRange(location: start, length: caret - start + remainder), text: String(token.dropFirst()))
    }

    static func query(in text: String, selection: Range<String.Index>) -> Query? {
        // TextField can publish its selection before the corresponding text update.
        guard selection.isEmpty, selection.lowerBound >= text.startIndex,
              selection.lowerBound <= text.endIndex else { return nil }
        return query(in: text, caret: selection.lowerBound.utf16Offset(in: text))
    }

    static func inserting(_ tag: String, into text: String, query: Query) -> (text: String, caret: Int) {
        let value = text as NSString
        let suffix = value.substring(from: NSMaxRange(query.range))
        let space = suffix.first?.isWhitespace == true ? "" : " "
        let replacement = tag + space
        let caret = query.range.location + replacement.utf16.count + (space.isEmpty ? suffix.prefix(1).utf16.count : 0)
        return (value.replacingCharacters(in: query.range, with: replacement), caret)
    }
}
