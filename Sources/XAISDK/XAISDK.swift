//
//  XAISDK.swift
//  XAISDK
//
//  Created by Alexey Demin on 2026-03-10.
//

import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

/// The base url for all xAI services.
public let baseURL = "api.x.ai"

/// Interceptor to add an xAI API key to the 'Authorization' header.
public struct AuthInterceptor: ClientInterceptor {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        var request = request
        request.metadata.addString("Bearer \(apiKey)", forKey: "authorization")
        return try await next(request, context)
    }
}

/// Returns a gRPC client for xAI services.
public func client(apiKey: String) throws -> GRPCClient<HTTP2ClientTransport.TransportServices> {
    try GRPCClient(
        transport: .http2NIOTS(
            target: .dns(host: baseURL),
            transportSecurity: .tls
        ),
        interceptors: [AuthInterceptor(apiKey: apiKey)]
    )
}

/// A convenience variant of 'withGRPCClient' for xAI services.
public func withClient<Result: Sendable>(
    apiKey: String,
    _ body: (GRPCClient<HTTP2ClientTransport.TransportServices>) async throws -> Result
) async throws -> Result {
    try await withGRPCClient(
        transport: .http2NIOTS(
            target: .dns(host: baseURL),
            transportSecurity: .tls
        ),
        interceptors: [AuthInterceptor(apiKey: apiKey)],
        handleClient: body
    )
}
