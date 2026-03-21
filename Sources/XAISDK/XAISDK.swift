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

/// The base url for all xAI services.
public let baseURL = "api.x.ai"

/// Interceptor to add an xAI API key to the 'Authorization' header.
public struct AuthInterceptor: ClientInterceptor {
    public let apiKey: String

    /// Initializes the interceptor with the provided API key.
    ///
    /// - Parameter apiKey: The xAI API key to use for authentication.
    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Intercepts the outgoing request to inject the Authorization header.
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
        request.metadata.addString("Bearer \(apiKey)", forKey: "authorization")
        return try await next(request, context)
    }
}

/// Returns a gRPC client for xAI services.
///
/// - Parameter apiKey: The xAI API key to use for authentication.
/// - Returns: A configured `GRPCClient` instance.
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
///
/// - Parameters:
///   - apiKey: The xAI API key to use for authentication.
///   - body: A closure that takes the configured client and performs requests. The client is automatically shut down when this closure returns.
/// - Returns: The result of the closure.
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
