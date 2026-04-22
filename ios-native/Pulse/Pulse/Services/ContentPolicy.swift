import Foundation

enum ContentPolicyError: LocalizedError {
    case blockedText

    var errorDescription: String? {
        switch self {
        case .blockedText:
            return "Please edit this before posting. It includes language we don't allow on Spilltop."
        }
    }
}

enum ContentPolicy {
    private static let blockedPatterns: [String] = [
        #"\b(kill\s+yourself|kys)\b"#,
        #"\b(rape|rapist)\b"#,
        #"\b(nazi|white\s+power)\b"#,
        #"\b(faggot|fag)\b"#,
        #"\b(nigger|nigga)\b"#,
        #"\b(chink|spic|coon|tranny)\b"#,
        #"\b(onlyfans|escort|prostitute|hooker)\b"#,
        #"\b(cocaine|meth|mdma|ecstasy|ketamine|xanax|oxy)\b"#,
    ]

    static func validateUserText(_ values: String?...) throws {
        for value in values {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if containsBlockedPattern(value) {
                throw ContentPolicyError.blockedText
            }
        }
    }

    static func isAllowed(_ value: String) -> Bool {
        !containsBlockedPattern(value)
    }

    private static func containsBlockedPattern(_ value: String) -> Bool {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        return blockedPatterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
