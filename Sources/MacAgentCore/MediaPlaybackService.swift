import AppKit
import Foundation

public struct MediaPlaybackRequest: Equatable, Sendable {
    public var provider: MediaProvider
    public var title: String
    public var artist: String?
    public var mediaURI: String?

    public init(
        provider: MediaProvider,
        title: String,
        artist: String? = nil,
        mediaURI: String? = nil
    ) {
        self.provider = provider
        self.title = title
        self.artist = artist
        self.mediaURI = mediaURI
    }

    public var query: String {
        [title, artist]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " ")
    }

    public var displayTitle: String {
        if let artist, !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(title) by \(artist)"
        }
        return title
    }
}

@MainActor
public protocol MediaOpening {
    func open(_ request: MediaPlaybackRequest) async throws -> String
}

public struct AppleMusicCatalogTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var trackID: Int64
    public var trackViewURL: URL
    public var countryCode: String

    public init(
        title: String,
        artist: String,
        trackID: Int64,
        trackViewURL: URL,
        countryCode: String
    ) {
        self.title = title
        self.artist = artist
        self.trackID = trackID
        self.trackViewURL = trackViewURL
        self.countryCode = countryCode
    }

    public var albumTrackAppURL: URL {
        guard var components = URLComponents(url: trackViewURL, resolvingAgainstBaseURL: false),
              components.host == "music.apple.com" else {
            return trackViewURL
        }

        components.scheme = "music"
        return components.url ?? trackViewURL
    }
}

public protocol AppleMusicCatalogSearching: Sendable {
    func bestTrack(for request: MediaPlaybackRequest) async throws -> AppleMusicCatalogTrack?
}

public enum MediaPlaybackError: Error, LocalizedError, Equatable {
    case missingProvider
    case missingTitle
    case invalidProviderURI(String)
    case appleMusicCatalogError(String)
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingProvider:
            return "Opening music requires Apple Music or Spotify."
        case .missingTitle:
            return "Opening music requires a song or album title."
        case .invalidProviderURI(let uri):
            return "\(uri) is not a supported Apple Music or Spotify URL."
        case .appleMusicCatalogError(let detail):
            return "Apple Music catalog search failed: \(detail)"
        case .openFailed(let detail):
            return "Opening music result failed: \(detail)"
        }
    }
}

public struct ITunesSearchAPIClient: AppleMusicCatalogSearching {
    private let session: URLSession
    private let baseURL: URL
    private let countryCode: String

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://itunes.apple.com")!,
        countryCode: String = Locale.current.region?.identifier.lowercased() ?? "us"
    ) {
        self.session = session
        self.baseURL = baseURL
        self.countryCode = countryCode
    }

    public func bestTrack(for request: MediaPlaybackRequest) async throws -> AppleMusicCatalogTrack? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "term", value: request.query),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "25")
        ]

        guard let url = components.url else {
            throw MediaPlaybackError.appleMusicCatalogError("Could not build Apple Music search URL.")
        }

        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable response>"
            throw MediaPlaybackError.appleMusicCatalogError(body)
        }

        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        guard let result = MediaSearchMatcher.best(
            in: decoded.results,
            request: request,
            title: \.trackName,
            artist: \.artistName
        ),
            let url = URL(string: result.trackViewURL) else {
            return nil
        }

        return AppleMusicCatalogTrack(
            title: result.trackName,
            artist: result.artistName,
            trackID: result.trackID,
            trackViewURL: url,
            countryCode: countryCode
        )
    }

    private struct ITunesSearchResponse: Decodable {
        var results: [Result]

        struct Result: Decodable {
            var artistName: String
            var trackID: Int64
            var trackName: String
            var trackViewURL: String

            enum CodingKeys: String, CodingKey {
                case artistName
                case trackID = "trackId"
                case trackName
                case trackViewURL = "trackViewUrl"
            }
        }
    }
}

private enum MediaSearchMatcher {
    static func best<Candidate>(
        in candidates: [Candidate],
        request: MediaPlaybackRequest,
        title: (Candidate) -> String,
        artist: (Candidate) -> String
    ) -> Candidate? {
        candidates
            .compactMap { candidate -> (candidate: Candidate, score: Int)? in
                guard let score = score(
                    candidateTitle: title(candidate),
                    candidateArtist: artist(candidate),
                    request: request
                ) else {
                    return nil
                }
                return (candidate, score)
            }
            .sorted { $0.score > $1.score }
            .first?
            .candidate
    }

    private static func score(
        candidateTitle: String,
        candidateArtist: String,
        request: MediaPlaybackRequest
    ) -> Int? {
        guard let titleScore = titleScore(candidateTitle: candidateTitle, requestedTitle: request.title) else {
            return nil
        }

        let matchedArtistScore: Int
        if let requestedArtist = request.artist?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedArtist.isEmpty {
            guard let score = artistScore(candidateArtist: candidateArtist, requestedArtist: requestedArtist) else {
                return nil
            }
            matchedArtistScore = score
        } else {
            matchedArtistScore = 0
        }

        return titleScore + matchedArtistScore
    }

    private static func titleScore(candidateTitle: String, requestedTitle: String) -> Int? {
        let candidate = normalize(candidateTitle)
        let requested = normalize(requestedTitle)
        guard !candidate.isEmpty, !requested.isEmpty else {
            return nil
        }

        if candidate == requested {
            return 100
        }
        if candidate.hasPrefix(requested + " ") {
            return 92
        }
        if candidate.contains(" " + requested + " ") ||
            candidate.hasSuffix(" " + requested) {
            return 86
        }

        let requestedTokens = tokens(requested)
        let candidateTokens = Set(tokens(candidate))
        guard !requestedTokens.isEmpty,
              requestedTokens.allSatisfy({ candidateTokens.contains($0) }) else {
            return nil
        }

        return requestedTokens.count == 1 ? 68 : 76
    }

    private static func artistScore(candidateArtist: String, requestedArtist: String) -> Int? {
        let candidate = normalize(candidateArtist)
        let requested = normalize(requestedArtist)
        guard !candidate.isEmpty, !requested.isEmpty else {
            return nil
        }

        if candidate == requested {
            return 60
        }
        if candidate.contains(requested) || requested.contains(candidate) {
            return 46
        }

        let requestedTokens = tokens(requested)
        let candidateTokens = Set(tokens(candidate))
        guard !requestedTokens.isEmpty,
              requestedTokens.allSatisfy({ candidateTokens.contains($0) }) else {
            return nil
        }
        return 34
    }

    private static func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        var scalars: [UnicodeScalar] = []
        var previousWasSeparator = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append(" ")
                previousWasSeparator = true
            }
        }

        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(_ normalizedValue: String) -> [String] {
        normalizedValue
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

public struct NativeMediaOpener: MediaOpening {
    private let appleMusicSearcher: AppleMusicCatalogSearching

    public init(appleMusicSearcher: AppleMusicCatalogSearching = ITunesSearchAPIClient()) {
        self.appleMusicSearcher = appleMusicSearcher
    }

    @MainActor
    public func open(_ request: MediaPlaybackRequest) async throws -> String {
        switch request.provider {
        case .appleMusic:
            return try await openAppleMusic(request)
        case .spotify:
            return try openSpotify(request)
        }
    }

    @MainActor
    private func openAppleMusic(_ request: MediaPlaybackRequest) async throws -> String {
        if let url = try providerURL(from: request.mediaURI, provider: .appleMusic) {
            try openURL(url, failureMessage: "Could not open Apple Music URL.")
            return "Opened Apple Music result for \(request.displayTitle)."
        }

        do {
            if let track = try await appleMusicSearcher.bestTrack(for: request) {
                try openURL(track.albumTrackAppURL, failureMessage: "Could not open Apple Music catalog result.")
                return "Opened Apple Music album result for \(track.title) by \(track.artist)."
            }
        } catch {
            let searchURL = appleMusicSearchURL(query: request.query)
            try openURL(searchURL, failureMessage: "Could not open Apple Music search.")
            return "Apple Music catalog lookup failed, so Sonny opened search for \(request.displayTitle)."
        }

        let searchURL = appleMusicSearchURL(query: request.query)
        try openURL(searchURL, failureMessage: "Could not open Apple Music search.")
        return "Opened Apple Music search for \(request.displayTitle)."
    }

    @MainActor
    private func openSpotify(_ request: MediaPlaybackRequest) throws -> String {
        if let url = try providerURL(from: request.mediaURI, provider: .spotify) {
            try openURL(url, failureMessage: "Could not open Spotify URL.")
            return "Opened Spotify result for \(request.displayTitle)."
        }

        let url = spotifySearchURL(query: request.query)
        try openURL(url, failureMessage: "Could not open Spotify search.")
        return "Opened Spotify search for \(request.displayTitle)."
    }

    private func providerURL(from rawURI: String?, provider: MediaProvider) throws -> URL? {
        guard let rawURI = rawURI?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURI.isEmpty else {
            return nil
        }

        guard let url = URL(string: rawURI) else {
            throw MediaPlaybackError.invalidProviderURI(rawURI)
        }

        switch provider {
        case .appleMusic:
            guard rawURI.hasPrefix("music://music.apple.com/") ||
                rawURI.hasPrefix("https://music.apple.com/") else {
                throw MediaPlaybackError.invalidProviderURI(rawURI)
            }
        case .spotify:
            guard rawURI.hasPrefix("spotify:track:") ||
                rawURI.hasPrefix("spotify:album:") ||
                rawURI.hasPrefix("https://open.spotify.com/track/") ||
                rawURI.hasPrefix("https://open.spotify.com/album/") else {
                throw MediaPlaybackError.invalidProviderURI(rawURI)
            }
        }

        return url
    }

    @MainActor
    private func openURL(_ url: URL, failureMessage: String) throws {
        guard NSWorkspace.shared.open(url) else {
            throw MediaPlaybackError.openFailed(failureMessage)
        }
    }

    private func spotifySearchURL(query: String) -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "spotify:search:\(encoded)")!
    }

    private func appleMusicSearchURL(query: String) -> URL {
        let countryCode = Locale.current.region?.identifier.lowercased() ?? "us"
        var components = URLComponents()
        components.scheme = "music"
        components.host = "music.apple.com"
        components.path = "/\(countryCode)/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: query)
        ]
        return components.url!
    }
}
