//
//  HTTPClient.swift
//  SwiftLocalize
//

import Foundation

// MARK: - HTTP Client

/// A minimal, thread-safe HTTP client using URLSession.
public actor HTTPClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Default timeout interval in seconds.
    public static let defaultTimeout: TimeInterval = 60

    public init(
        configuration: URLSessionConfiguration = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.session = URLSession(configuration: configuration)
        self.decoder = decoder
        self.encoder = encoder
    }

    /// Convenience initializer with timeout.
    public init(timeout: TimeInterval) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.init(configuration: config)
    }

    // MARK: - GET

    /// Perform a GET request and decode the response.
    public func get<Response: Decodable>(
        url: String,
        headers: [String: String] = [:]
    ) async throws(HTTPError) -> Response {
        guard let requestURL = URL(string: url) else {
            throw .invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        applyHeaders(headers, to: &request)

        return try await execute(request)
    }

    /// Perform a GET request and return raw data.
    public func getData(
        url: String,
        headers: [String: String] = [:]
    ) async throws(HTTPError) -> Data {
        guard let requestURL = URL(string: url) else {
            throw .invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        applyHeaders(headers, to: &request)

        return try await executeRaw(request)
    }

    // MARK: - POST

    /// Perform a POST request with a JSON body and decode the response.
    public func post<Request: Encodable, Response: Decodable>(
        url: String,
        body: Request,
        headers: [String: String] = [:]
    ) async throws(HTTPError) -> Response {
        guard let requestURL = URL(string: url) else {
            throw .invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(headers, to: &request)

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw .encodingFailed(error.localizedDescription)
        }

        return try await execute(request)
    }

    /// Perform a POST request with raw data body and decode the response.
    public func post<Response: Decodable>(
        url: String,
        data: Data,
        contentType: String = "application/json",
        headers: [String: String] = [:]
    ) async throws(HTTPError) -> Response {
        guard let requestURL = URL(string: url) else {
            throw .invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        applyHeaders(headers, to: &request)

        return try await execute(request)
    }

    // MARK: - Private Helpers

    private func applyHeaders(_ headers: [String: String], to request: inout URLRequest) {
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func execute<Response: Decodable>(
        _ request: URLRequest
    ) async throws(HTTPError) -> Response {
        let data = try await executeRaw(request)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw .decodingFailed(error.localizedDescription)
        }
    }

    private func executeRaw(_ request: URLRequest) async throws(HTTPError) -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
                throw .connectionFailed(urlError.localizedDescription)
            default:
                throw .connectionFailed(urlError.localizedDescription)
            }
        } catch {
            throw .connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw .invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw .statusCode(httpResponse.statusCode, data)
        }

        return data
    }
}

// MARK: - HTTPClient Extensions

extension HTTPClient {
    /// Extract error message from API error response data.
    public nonisolated func extractErrorMessage(from data: Data) -> String? {
        // Try common error response formats
        struct GenericError: Decodable {
            let error: ErrorDetail?
            let message: String?

            struct ErrorDetail: Decodable {
                let message: String?
                let type: String?
            }
        }

        guard let errorResponse = try? JSONDecoder().decode(GenericError.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }

        return errorResponse.error?.message ?? errorResponse.message
    }
}
