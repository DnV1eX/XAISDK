//
//  XAISDK.swift
//  XAISDK
//
//  Created by Alexey Demin on 2026-03-10.
//  Copyright © 2026 DnV1eX. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//

import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

/// The host for all xAI services.
public let host = "api.x.ai"

/// Helper function to create an authorization header dictionary.
///
/// - Parameter apiKey: The xAI API key.
/// - Returns: A dictionary containing the Authorization header.
public func authHeader(apiKey: String) -> [String: String] {
    ["authorization": "Bearer \(apiKey)"]
}

/// Interceptor to add metadata to the request headers.
public struct MetadataInterceptor: ClientInterceptor {
    public let metadata: [String: String]

    /// Initializes the interceptor with the provided metadata.
    ///
    /// - Parameter metadata: The metadata dictionary to use for the request headers.
    public init(metadata: [String: String]) {
        self.metadata = metadata
    }

    /// Intercepts the outgoing request to inject the metadata.
    ///
    /// - Parameters:
    ///   - request: The outgoing client request.
    ///   - context: The client context.
    ///   - next: The closure to pass the request to the next interceptor in the pipeline.
    /// - Returns: The response from the server.
    public func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        var request = request
        for (key, value) in metadata {
            request.metadata.addString(value, forKey: key)
        }
        return try await next(request, context)
    }
}

/// Returns a gRPC client for xAI services through a proxy.
///
/// - Parameters:
///   - proxy: The proxy host to use for the connection.
///   - metadata: The metadata dictionary to use for the request headers.
/// - Returns: A configured `GRPCClient` instance.
public func client(proxy: String, metadata: [String: String]) throws -> GRPCClient<HTTP2ClientTransport.TransportServices> {
    try GRPCClient(
        transport: .http2NIOTS(
            target: .dns(host: proxy),
            transportSecurity: .tls
        ),
        interceptors: [MetadataInterceptor(metadata: metadata)]
    )
}

/// Returns a gRPC client for direct access to xAI services.
///
/// - Parameter apiKey: The xAI API key to use for authentication.
/// - Returns: A configured `GRPCClient` instance.
public func client(apiKey: String) throws -> GRPCClient<HTTP2ClientTransport.TransportServices> {
    try client(proxy: host, metadata: authHeader(apiKey: apiKey))
}

/// A convenience variant of 'withGRPCClient' for xAI services through a proxy.
///
/// - Parameters:
///   - proxy: The proxy host to use for the connection.
///   - metadata: The metadata dictionary to use for the request headers.
///   - body: A closure that takes the configured client and performs requests. The client is automatically shut down when this closure returns.
/// - Returns: The result of the closure.
public func withClient<Result: Sendable>(
    proxy: String,
    metadata: [String: String],
    _ body: (GRPCClient<HTTP2ClientTransport.TransportServices>) async throws -> Result
) async throws -> Result {
    try await withGRPCClient(
        transport: .http2NIOTS(
            target: .dns(host: proxy),
            transportSecurity: .tls
        ),
        interceptors: [MetadataInterceptor(metadata: metadata)],
        handleClient: body
    )
}

/// A convenience variant of 'withGRPCClient' for direct access to xAI services.
///
/// - Parameters:
///   - apiKey: The xAI API key to use for authentication.
///   - body: A closure that takes the configured client and performs requests. The client is automatically shut down when this closure returns.
/// - Returns: The result of the closure.
public func withClient<Result: Sendable>(
    apiKey: String,
    _ body: (GRPCClient<HTTP2ClientTransport.TransportServices>) async throws -> Result
) async throws -> Result {
    try await withClient(proxy: host, metadata: authHeader(apiKey: apiKey), body)
}

extension GRPCClient {
    /// Starts the client connection in a background task.
    ///
    /// - Returns: A `Task` representing the connection lifecycle. You can await this task's value after calling `close()` to ensure the connection has fully terminated.
    @discardableResult
    public func start() -> Task<Void, Error> {
        Task {
            try await runConnections()
        }
    }

    /// Gracefully shuts down the client and optionally waits for the connection task to finish.
    ///
    /// - Parameter connectionTask: The task returned by `start()`. If provided, this function will wait for the task to complete its shutdown process.
    public func close(_ connectionTask: Task<Void, Error>? = nil) async throws {
        beginGracefulShutdown()
        try await connectionTask?.value
    }
}
