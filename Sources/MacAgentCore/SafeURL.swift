import Foundation

public enum SafeURLError: Error, LocalizedError, Equatable {
    case missingURL
    case invalidURL(String)
    case unsupportedScheme(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Opening a URL requires a URL."
        case .invalidURL(let rawURL):
            return "\(rawURL) is not a valid URL."
        case .unsupportedScheme(let scheme):
            return "Only http and https URLs can be opened, not \(scheme)."
        }
    }
}

public enum SafeURL {
    public static func validateWebURL(_ rawURL: String?) throws -> URL {
        guard let rawURL, !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SafeURLError.missingURL
        }

        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host != nil else {
            throw SafeURLError.invalidURL(trimmed)
        }

        guard scheme == "http" || scheme == "https" else {
            throw SafeURLError.unsupportedScheme(scheme)
        }

        return url
    }
}
