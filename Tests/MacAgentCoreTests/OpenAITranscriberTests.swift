import Foundation
import Testing
@testable import MacAgentCore

@Suite
struct OpenAITranscriberTests {
    @Test
    func transcribesFixtureResponse() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macagent-transcriber-test-\(UUID().uuidString).m4a")
        try Data("fake-audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        FixtureURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
            let body = try request.multipartBodyData()
            let bodyText = String(data: body, encoding: .utf8) ?? ""
            #expect(bodyText.contains("gpt-4o-mini-transcribe"))
            #expect(bodyText.contains("response_format"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"text":"Open Safari"}"#.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let transcriber = try OpenAITranscriber(
            apiKey: "test-key",
            endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            session: session
        )

        let result = try await transcriber.transcribe(audioFileURL: audioURL)

        #expect(result.text == "Open Safari")
    }
}

private final class FixtureURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: TranscriptionError.missingText)
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

private extension URLRequest {
    func multipartBodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            Issue.record("Expected multipart body data.")
            throw TranscriptionError.missingText
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? TranscriptionError.missingText
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
