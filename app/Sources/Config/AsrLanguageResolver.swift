import FluidAudio
import Foundation

struct AsrLanguageResolution {
    let preference: String
    let resolvedCode: String?
    let language: Language?

    var displayValue: String {
        switch preference {
        case AsrLanguageResolver.systemPreference:
            return "\(AsrLanguageResolver.systemPreference)/\(resolvedCode ?? AsrLanguageResolver.autoPreference)"
        default:
            return preference
        }
    }
}

enum AsrLanguageResolver {
    static let systemPreference = "system"
    static let autoPreference = "auto"

    static func normalizePreference(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidPreference(_ rawValue: String) -> Bool {
        let preference = normalizePreference(rawValue)
        return preference == systemPreference
            || preference == autoPreference
            || Language(rawValue: preference) != nil
    }

    static func resolve(_ rawValue: String) -> AsrLanguageResolution {
        let preference = normalizePreference(rawValue)
        switch preference {
        case systemPreference:
            let code = systemSupportedLanguageCode()
            return AsrLanguageResolution(
                preference: preference,
                resolvedCode: code,
                language: code.flatMap(Language.init(rawValue:))
            )
        case autoPreference:
            return AsrLanguageResolution(preference: preference, resolvedCode: nil, language: nil)
        default:
            return AsrLanguageResolution(
                preference: preference,
                resolvedCode: preference,
                language: Language(rawValue: preference)
            )
        }
    }

    static func systemSupportedLanguageCode() -> String? {
        for identifier in Locale.preferredLanguages {
            if let code = supportedLanguageCode(from: identifier) {
                return code
            }
        }
        return supportedLanguageCode(from: Locale.current.identifier)
    }

    static var supportedCodeList: String {
        Language.allCases.map(\.rawValue).sorted().joined(separator: ", ")
    }

    private static func supportedLanguageCode(from identifier: String) -> String? {
        guard let code = languageCode(from: identifier), Language(rawValue: code) != nil else {
            return nil
        }
        return code
    }

    private static func languageCode(from identifier: String) -> String? {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.split(separator: "-").first.map(String.init)
    }
}
