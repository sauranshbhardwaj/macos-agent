import Foundation
import Testing
@testable import MacAgentCore

@Suite(.serialized)
struct MediaPlaybackServiceTests {
    @Test
    func mediaPlaybackFailureDiagnosisReturnsNilWhenNothingBlocksPlayback() {
        #expect(MediaPlaybackFailureDiagnosis.diagnose(MediaPlaybackBlockers()) == nil)
    }

    @Test
    func mediaPlaybackFailureDiagnosisReportsAuthorizationFirstWhenAllBlockersApply() {
        let blockers = MediaPlaybackBlockers(
            authorizationBlocked: true,
            subscriptionBlocked: true,
            activeDeviceBlocked: true,
            catalogMatchBlocked: true,
            providerOutageBlocked: true
        )

        #expect(MediaPlaybackFailureDiagnosis.diagnose(blockers) == .authorization)
    }

    @Test
    func mediaPlaybackFailureDiagnosisUsesFixedPrecedenceOrder() {
        let expectations: [(MediaPlaybackBlockers, MediaPlaybackFailureReason)] = [
            (
                MediaPlaybackBlockers(authorizationBlocked: true),
                .authorization
            ),
            (
                MediaPlaybackBlockers(subscriptionBlocked: true),
                .subscriptionPremium
            ),
            (
                MediaPlaybackBlockers(activeDeviceBlocked: true),
                .activeDevice
            ),
            (
                MediaPlaybackBlockers(catalogMatchBlocked: true),
                .catalogMatch
            ),
            (
                MediaPlaybackBlockers(providerOutageBlocked: true),
                .providerOutage
            ),
            (
                MediaPlaybackBlockers(subscriptionBlocked: true, activeDeviceBlocked: true),
                .subscriptionPremium
            ),
            (
                MediaPlaybackBlockers(activeDeviceBlocked: true, catalogMatchBlocked: true),
                .activeDevice
            ),
            (
                MediaPlaybackBlockers(catalogMatchBlocked: true, providerOutageBlocked: true),
                .catalogMatch
            )
        ]

        for (blockers, expectedReason) in expectations {
            #expect(MediaPlaybackFailureDiagnosis.diagnose(blockers) == expectedReason)
        }
    }

    @Test
    func spotifyResolverStartsPlaybackForBestMatchingTrack() {
        let request = spotifyRequest()
        let result = SpotifyPlaybackResolver.resolve(
            request: request,
            state: spotifyState(
                candidates: [
                    spotifyTrack(
                        uri: "spotify:track:wrong-market",
                        title: "Jimmy Cooks",
                        artists: ["Drake"],
                        albumTitle: "Honestly, Nevermind",
                        durationMilliseconds: 218_365,
                        markets: ["GB"]
                    ),
                    spotifyTrack(
                        uri: "spotify:track:wrong-album-duration",
                        title: "Jimmy Cooks",
                        artists: ["Drake"],
                        albumTitle: "Scary Hours",
                        durationMilliseconds: 260_000,
                        markets: ["US"]
                    ),
                    spotifyTrack(
                        uri: "spotify:track:best",
                        title: "Jimmy Cooks (feat. 21 Savage)",
                        artists: ["Drake", "21 Savage"],
                        albumTitle: "Honestly, Nevermind",
                        durationMilliseconds: 218_365,
                        markets: ["US"]
                    )
                ]
            )
        )

        guard case .started(let start) = result else {
            Issue.record("Expected Spotify playback to start.")
            return
        }

        #expect(start.track.uri == "spotify:track:best")
        #expect(start.action == .play(uri: "spotify:track:best", deviceID: "mac"))
    }

    @Test
    func spotifyResolverTransfersPlaybackWhenNeeded() {
        let result = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(
                devices: [spotifyDevice(isActive: false, isTransferable: true)],
                candidates: [spotifyTrack()]
            )
        )

        guard case .started(let start) = result else {
            Issue.record("Expected Spotify playback to start after transfer.")
            return
        }

        #expect(start.action == .transferAndPlay(uri: "spotify:track:best", deviceID: "mac"))
    }

    @Test
    func unavailableSpotifyProviderFailsAsAuthorizationBlocker() async {
        let result = await UnavailableSpotifyPlaybackProvider().play(spotifyRequest())

        guard case .blocked(let failure) = result else {
            Issue.record("Expected unavailable Spotify provider to block playback.")
            return
        }

        #expect(failure.reason == .authorization)
        #expect(failure.detail == "Spotify playback provider not configured.")
        #expect(MediaPlaybackFailureDiagnosis.diagnose(failure.blockers) == failure.reason)
    }

    @Test
    func spotifyResolverDiagnosesMissingAuthorization() {
        let result = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(isAuthorized: false, candidates: [spotifyTrack()])
        )

        assertSpotifyBlocked(result, reason: .authorization)
    }

    @Test
    func spotifyResolverDiagnosesMissingPremium() {
        let result = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(hasPremium: false, candidates: [spotifyTrack()])
        )

        assertSpotifyBlocked(result, reason: .subscriptionPremium)
    }

    @Test
    func spotifyResolverDiagnosesMissingActiveDevice() {
        let result = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(devices: [], candidates: [spotifyTrack()])
        )

        assertSpotifyBlocked(result, reason: .activeDevice)
    }

    @Test
    func spotifyResolverDiagnosesCatalogMismatch() {
        let result = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(
                candidates: [
                    spotifyTrack(
                        uri: "spotify:track:wrong",
                        title: "Wrong Song",
                        artists: ["Drake"],
                        albumTitle: "Honestly, Nevermind",
                        durationMilliseconds: 218_365,
                        markets: ["US"]
                    )
                ]
            )
        )

        assertSpotifyBlocked(result, reason: .catalogMatch)
    }

    @Test
    func spotifyResolverDiagnosesProviderOutageAndRateLimit() {
        let outage = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(providerStatus: .outage, candidates: [spotifyTrack()])
        )
        let rateLimited = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(providerStatus: .rateLimited, candidates: [spotifyTrack()])
        )

        assertSpotifyBlocked(outage, reason: .providerOutage, detail: "Spotify playback is currently unavailable.")
        assertSpotifyBlocked(rateLimited, reason: .providerOutage, detail: "Spotify playback is currently rate-limited.")
    }

    @Test
    func spotifyResolverUsesFailureDiagnosisForMultiBlockerPrecedence() {
        let result = SpotifyPlaybackResolver.resolve(
            request: spotifyRequest(),
            state: spotifyState(
                isAuthorized: false,
                hasPremium: false,
                devices: [],
                providerStatus: .rateLimited,
                candidates: []
            )
        )

        guard case .blocked(let failure) = result else {
            Issue.record("Expected Spotify playback to be blocked.")
            return
        }

        #expect(failure.blockers == MediaPlaybackBlockers(
            authorizationBlocked: true,
            subscriptionBlocked: true,
            activeDeviceBlocked: true,
            catalogMatchBlocked: true,
            providerOutageBlocked: true
        ))
        #expect(MediaPlaybackFailureDiagnosis.diagnose(failure.blockers) == .authorization)
        #expect(failure.reason == .authorization)
    }

    @Test
    func appleMusicResolverQueuesBestMatchingTrackForPlayback() {
        let request = appleMusicRequest()
        let result = AppleMusicPlaybackResolver.resolve(
            request: request,
            state: appleMusicState(
                candidates: [
                    appleMusicTrack(
                        catalogID: "wrong-storefront",
                        title: "Good Days",
                        artist: "SZA",
                        albumTitle: "Good Days - Single",
                        durationMilliseconds: 279_204,
                        storefronts: ["gb"]
                    ),
                    appleMusicTrack(
                        catalogID: "wrong-album-duration",
                        title: "Good Days",
                        artist: "SZA",
                        albumTitle: "Ctrl",
                        durationMilliseconds: 240_000,
                        storefronts: ["us"]
                    ),
                    appleMusicTrack(
                        catalogID: "best",
                        title: "Good Days",
                        artist: "SZA",
                        albumTitle: "Good Days - Single",
                        durationMilliseconds: 279_204,
                        storefronts: ["us"]
                    )
                ]
            )
        )

        guard case .started(let start) = result else {
            Issue.record("Expected Apple Music playback to start.")
            return
        }

        #expect(start.track.catalogID == "best")
        #expect(start.action == .queueAndPlay(catalogID: "best"))
    }

    @Test
    func unavailableAppleMusicProviderFailsAsAuthorizationBlocker() async {
        let result = await UnavailableAppleMusicPlaybackProvider().play(appleMusicRequest())

        guard case .blocked(let failure) = result else {
            Issue.record("Expected unavailable Apple Music provider to block playback.")
            return
        }

        #expect(failure.reason == .authorization)
        #expect(failure.detail == "Apple Music playback provider not configured.")
        #expect(MediaPlaybackFailureDiagnosis.diagnose(failure.blockers) == failure.reason)
    }

    @Test
    func appleMusicResolverDiagnosesMissingAuthorization() {
        let result = AppleMusicPlaybackResolver.resolve(
            request: appleMusicRequest(),
            state: appleMusicState(isAuthorized: false, candidates: [appleMusicTrack()])
        )

        assertAppleMusicBlocked(result, reason: .authorization)
    }

    @Test
    func appleMusicResolverDiagnosesMissingSubscription() {
        let result = AppleMusicPlaybackResolver.resolve(
            request: appleMusicRequest(),
            state: appleMusicState(hasSubscription: false, candidates: [appleMusicTrack()])
        )

        assertAppleMusicBlocked(result, reason: .subscriptionPremium)
    }

    @Test
    func appleMusicResolverDiagnosesCatalogMismatch() {
        let result = AppleMusicPlaybackResolver.resolve(
            request: appleMusicRequest(),
            state: appleMusicState(
                candidates: [
                    appleMusicTrack(
                        catalogID: "wrong",
                        title: "Wrong Song",
                        artist: "SZA",
                        albumTitle: "Good Days - Single",
                        durationMilliseconds: 279_204,
                        storefronts: ["us"]
                    )
                ]
            )
        )

        assertAppleMusicBlocked(result, reason: .catalogMatch)
    }

    @Test
    func appleMusicResolverDiagnosesProviderOutage() {
        let result = AppleMusicPlaybackResolver.resolve(
            request: appleMusicRequest(),
            state: appleMusicState(providerStatus: .outage, candidates: [appleMusicTrack()])
        )

        assertAppleMusicBlocked(
            result,
            reason: .providerOutage,
            detail: "Apple Music playback is currently unavailable."
        )
    }

    @Test
    func appleMusicResolverUsesFailureDiagnosisForMultiBlockerPrecedence() {
        let result = AppleMusicPlaybackResolver.resolve(
            request: appleMusicRequest(),
            state: appleMusicState(
                isAuthorized: false,
                hasSubscription: false,
                providerStatus: .outage,
                candidates: []
            )
        )

        guard case .blocked(let failure) = result else {
            Issue.record("Expected Apple Music playback to be blocked.")
            return
        }

        #expect(failure.blockers == MediaPlaybackBlockers(
            authorizationBlocked: true,
            subscriptionBlocked: true,
            activeDeviceBlocked: false,
            catalogMatchBlocked: true,
            providerOutageBlocked: true
        ))
        #expect(MediaPlaybackFailureDiagnosis.diagnose(failure.blockers) == .authorization)
        #expect(failure.reason == .authorization)
    }

    @Test
    func iTunesSearchReturnsAppleMusicAlbumLink() async throws {
        AppleMusicFixtureURLProtocol.handler = { request in
            #expect(request.url?.path == "/search")
            #expect(request.url?.query?.contains("media=music") == true)
            #expect(request.url?.query?.contains("entity=song") == true)
            #expect(request.url?.query?.contains("limit=25") == true)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
              "resultCount": 1,
              "results": [
                {
                  "artistName": "Drake",
                  "trackId": 1628355395,
                  "trackName": "Jimmy Cooks (feat. 21 Savage)",
                  "trackViewUrl": "https://music.apple.com/us/album/jimmy-cooks-feat-21-savage/1628355391?i=1628355395&uo=4"
                }
              ]
            }
            """
            return (response, Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppleMusicFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = ITunesSearchAPIClient(
            session: session,
            baseURL: URL(string: "https://itunes.apple.com")!,
            countryCode: "us"
        )

        let track = try await client.bestTrack(
            for: MediaPlaybackRequest(provider: .appleMusic, title: "Jimmy Cooks", artist: "Drake")
        )

        #expect(track?.title == "Jimmy Cooks (feat. 21 Savage)")
        #expect(track?.artist == "Drake")
        #expect(track?.trackID == 1_628_355_395)
        #expect(track?.albumTrackAppURL.absoluteString.contains("/album/jimmy-cooks-feat-21-savage/1628355391") == true)
        #expect(track?.albumTrackAppURL.absoluteString.contains("i=1628355395") == true)
    }

    @Test
    func iTunesSearchReturnsNilWhenNoResults() async throws {
        AppleMusicFixtureURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"resultCount":0,"results":[]}"#.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppleMusicFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = ITunesSearchAPIClient(session: session, countryCode: "us")

        let track = try await client.bestTrack(
            for: MediaPlaybackRequest(provider: .appleMusic, title: "not a song")
        )

        #expect(track == nil)
    }

    @Test
    func iTunesSearchRanksExactArtistAndTitleAboveFirstResult() async throws {
        AppleMusicFixtureURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
              "resultCount": 3,
              "results": [
                {
                  "artistName": "Kanye West",
                  "trackId": 1,
                  "trackName": "Wrong Song",
                  "trackViewUrl": "https://music.apple.com/us/album/wrong-song/1?i=1"
                },
                {
                  "artistName": "Other Artist",
                  "trackId": 2,
                  "trackName": "Father",
                  "trackViewUrl": "https://music.apple.com/us/album/father/2?i=2"
                },
                {
                  "artistName": "Kanye West",
                  "trackId": 3,
                  "trackName": "Father Stretch My Hands Pt. 1",
                  "trackViewUrl": "https://music.apple.com/us/album/father-stretch-my-hands-pt-1/3?i=3"
                }
              ]
            }
            """
            return (response, Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppleMusicFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = ITunesSearchAPIClient(session: session, countryCode: "us")

        let track = try await client.bestTrack(
            for: MediaPlaybackRequest(provider: .appleMusic, title: "Father", artist: "Kanye West")
        )

        #expect(track?.title == "Father Stretch My Hands Pt. 1")
        #expect(track?.artist == "Kanye West")
        #expect(track?.trackID == 3)
    }

    private func spotifyRequest() -> MediaPlaybackRequest {
        MediaPlaybackRequest(
            provider: .spotify,
            title: "Jimmy Cooks",
            artist: "Drake",
            albumTitle: "Honestly, Nevermind",
            durationMilliseconds: 218_365,
            market: "US"
        )
    }

    private func spotifyState(
        isAuthorized: Bool = true,
        hasPremium: Bool = true,
        devices: [SpotifyPlaybackDevice]? = nil,
        providerStatus: SpotifyProviderStatus = .available,
        candidates: [SpotifyTrackCandidate]
    ) -> SpotifyPlaybackState {
        SpotifyPlaybackState(
            isAuthorized: isAuthorized,
            hasPremium: hasPremium,
            devices: devices ?? [spotifyDevice()],
            candidates: candidates,
            providerStatus: providerStatus
        )
    }

    private func spotifyDevice(
        id: String = "mac",
        name: String = "Sonny Mac",
        isActive: Bool = true,
        isTransferable: Bool = true
    ) -> SpotifyPlaybackDevice {
        SpotifyPlaybackDevice(
            id: id,
            name: name,
            isActive: isActive,
            isTransferable: isTransferable
        )
    }

    private func spotifyTrack(
        uri: String = "spotify:track:best",
        title: String = "Jimmy Cooks (feat. 21 Savage)",
        artists: [String] = ["Drake", "21 Savage"],
        albumTitle: String = "Honestly, Nevermind",
        durationMilliseconds: Int = 218_365,
        markets: [String] = ["US"]
    ) -> SpotifyTrackCandidate {
        SpotifyTrackCandidate(
            uri: uri,
            title: title,
            artists: artists,
            albumTitle: albumTitle,
            durationMilliseconds: durationMilliseconds,
            availableMarkets: markets
        )
    }

    private func assertSpotifyBlocked(
        _ result: SpotifyPlaybackResult,
        reason: MediaPlaybackFailureReason,
        detail: String = "Spotify playback requirements were not met."
    ) {
        guard case .blocked(let failure) = result else {
            Issue.record("Expected Spotify playback to be blocked.")
            return
        }

        #expect(failure.reason == reason)
        #expect(failure.detail == detail)
        #expect(MediaPlaybackFailureDiagnosis.diagnose(failure.blockers) == failure.reason)
    }

    private func appleMusicRequest() -> MediaPlaybackRequest {
        MediaPlaybackRequest(
            provider: .appleMusic,
            title: "Good Days",
            artist: "SZA",
            albumTitle: "Good Days - Single",
            durationMilliseconds: 279_204,
            market: "us"
        )
    }

    private func appleMusicState(
        isAuthorized: Bool = true,
        hasSubscription: Bool = true,
        providerStatus: AppleMusicProviderStatus = .available,
        candidates: [AppleMusicTrackCandidate]
    ) -> AppleMusicPlaybackState {
        AppleMusicPlaybackState(
            isAuthorized: isAuthorized,
            hasSubscription: hasSubscription,
            candidates: candidates,
            providerStatus: providerStatus
        )
    }

    private func appleMusicTrack(
        catalogID: String = "best",
        title: String = "Good Days",
        artist: String = "SZA",
        albumTitle: String = "Good Days - Single",
        durationMilliseconds: Int = 279_204,
        storefronts: [String] = ["us"]
    ) -> AppleMusicTrackCandidate {
        AppleMusicTrackCandidate(
            catalogID: catalogID,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            durationMilliseconds: durationMilliseconds,
            storefronts: storefronts,
            url: URL(string: "https://music.apple.com/us/song/good-days/\(catalogID)")
        )
    }

    private func assertAppleMusicBlocked(
        _ result: AppleMusicPlaybackResult,
        reason: MediaPlaybackFailureReason,
        detail: String = "Apple Music playback requirements were not met."
    ) {
        guard case .blocked(let failure) = result else {
            Issue.record("Expected Apple Music playback to be blocked.")
            return
        }

        #expect(failure.reason == reason)
        #expect(failure.detail == detail)
        #expect(MediaPlaybackFailureDiagnosis.diagnose(failure.blockers) == failure.reason)
    }
}

private final class AppleMusicFixtureURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: MediaPlaybackError.appleMusicCatalogError("missing fixture"))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
