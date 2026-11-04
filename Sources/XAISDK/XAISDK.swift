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

import Foundation
import GRPCCore
import Synchronization
#if canImport(Network)
import GRPCNIOTransportHTTP2TransportServices
/// The default transport type for the current platform.
public typealias DefaultTransport = HTTP2ClientTransport.TransportServices
#else
import GRPCNIOTransportHTTP2Posix
/// The default transport type for the current platform.
public typealias DefaultTransport = HTTP2ClientTransport.Posix
#endif

/// The host for all xAI services.
public let host = "api.x.ai"

/// Response header set to `true` when the output was watermarked.
public let watermarkMetadataKey = "x-watermark"

private let _isWatermarkWarningEnabled = Mutex(true)

/// Enables a warning when a response is watermarked.
///
/// The default is `true`. Set this to `false` to hide the warnings.
public var isWatermarkWarningEnabled: Bool {
    get { _isWatermarkWarningEnabled.withLock { $0 } }
    set { _isWatermarkWarningEnabled.withLock { $0 = newValue } }
}

/// Helper function to create an authorization header dictionary.
///
/// - Parameter apiKey: The xAI API key.
/// - Returns: A dictionary containing the Authorization header.
public func authHeader(apiKey: String) -> [String: String] {
    ["authorization": "Bearer \(apiKey)"]
}

/// Returns the default transport for the given host.
///
/// - Parameter host: The host to connect to.
/// - Returns: A configured `DefaultTransport` instance.
public func transport(host: String) throws -> DefaultTransport {
#if canImport(Network)
    try .http2NIOTS(target: .dns(host: host), transportSecurity: .tls)
#else
    try .http2NIOPosix(target: .dns(host: host), transportSecurity: .tls)
#endif
}

/// Adds metadata to the request headers.
public struct MetadataRequestInterceptor: ClientInterceptor {
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

/// Warns when response headers include the watermark flag.
public struct WatermarkResponseInterceptor: ClientInterceptor {
    /// Called when a response is watermarked.
    public let onReadWatermark: @Sendable () -> Void

    /// Creates an interceptor that calls `onReadWatermark` when a response is watermarked.
    ///
    /// - Parameter onReadWatermark: A closure called when the watermark flag is `true`. The default writes a warning to standard error.
    public init(onReadWatermark: @escaping @Sendable () -> Void = {
        guard isWatermarkWarningEnabled else { return }
        let line = "warning: xAI watermarked this response. Disable watermarking at https://console.x.ai/team/default/settings/team or hide warnings with isWatermarkWarningEnabled = false.\n"
        try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }) {
        self.onReadWatermark = onReadWatermark
    }

    /// Intercepts the response to read the watermark flag and warn when it is set.
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
        let response = try await next(request, context)
        let isWatermarked = response.metadata[stringValues: watermarkMetadataKey].contains { $0.lowercased() == "true" }
        if isWatermarked {
            onReadWatermark()
        }
        return response
    }
}

/// Returns a gRPC client for xAI services through a proxy.
///
/// - Parameters:
///   - proxy: The proxy host to use for the connection.
///   - metadata: The metadata dictionary to use for the request headers.
///   - transport: A closure that returns the transport to use for the connection. Defaults to `transport(host:)`.
/// - Returns: A configured `GRPCClient` instance.
public func client<Transport: ClientTransport>(
    proxy: String,
    metadata: [String: String],
    transport: (String) throws -> Transport = transport(host:)
) throws -> GRPCClient<Transport> {
    GRPCClient(
        transport: try transport(proxy),
        interceptors: [
            MetadataRequestInterceptor(metadata: metadata),
            WatermarkResponseInterceptor(),
        ]
    )
}

/// Returns a gRPC client for direct access to xAI services.
///
/// - Parameters:
///   - apiKey: The xAI API key to use for authentication.
///   - transport: A closure that returns the transport to use for the connection. Defaults to `transport(host:)`.
/// - Returns: A configured `GRPCClient` instance.
public func client<Transport: ClientTransport>(
    apiKey: String,
    transport: (String) throws -> Transport = transport(host:)
) throws -> GRPCClient<Transport> {
    try client(proxy: host, metadata: authHeader(apiKey: apiKey), transport: transport)
}

/// A convenience variant of 'withGRPCClient' for xAI services through a proxy.
///
/// - Parameters:
///   - proxy: The proxy host to use for the connection.
///   - metadata: The metadata dictionary to use for the request headers.
///   - transport: A closure that returns the transport to use for the connection. Defaults to `transport(host:)`.
///   - body: A closure that takes the configured client and performs requests. The client is automatically shut down when this closure returns.
/// - Returns: The result of the closure.
public func withClient<Result: Sendable, Transport: ClientTransport>(
    proxy: String,
    metadata: [String: String],
    transport: (String) throws -> Transport,
    _ body: (GRPCClient<Transport>) async throws -> Result
) async throws -> Result {
    try await withGRPCClient(
        transport: try transport(proxy),
        interceptors: [
            MetadataRequestInterceptor(metadata: metadata),
            WatermarkResponseInterceptor(),
        ],
        handleClient: body
    )
}

/// A convenience variant of 'withGRPCClient' for xAI services through a proxy using the default transport.
///
/// - Parameters:
///   - proxy: The proxy host to use for the connection.
///   - metadata: The metadata dictionary to use for the request headers.
///   - body: A closure that takes the configured client and performs requests. The client is automatically shut down when this closure returns.
/// - Returns: The result of the closure.
public func withClient<Result: Sendable>(
    proxy: String,
    metadata: [String: String],
    _ body: (GRPCClient<DefaultTransport>) async throws -> Result
) async throws -> Result {
    try await withClient(proxy: proxy, metadata: metadata, transport: transport(host:), body)
}

/// A convenience variant of 'withGRPCClient' for direct access to xAI services.
///
/// - Parameters:
///   - apiKey: The xAI API key to use for authentication.
///   - transport: A closure that returns the transport to use for the connection. Defaults to `transport(host:)`.
///   - body: A closure that takes the configured client and performs requests. The client is automatically shut down when this closure returns.
/// - Returns: The result of the closure.
public func withClient<Result: Sendable, Transport: ClientTransport>(
    apiKey: String,
    transport: (String) throws -> Transport,
    _ body: (GRPCClient<Transport>) async throws -> Result
) async throws -> Result {
    try await withClient(proxy: host, metadata: authHeader(apiKey: apiKey), transport: transport, body)
}

/// A convenience variant of 'withGRPCClient' for direct access to xAI services using the default transport.
///
/// - Parameters:
///   - apiKey: The xAI API key to use for authentication.
///   - body: A closure that takes the configured client and performs requests. The client is automatically shut down when this closure returns.
/// - Returns: The result of the closure.
public func withClient<Result: Sendable>(
    apiKey: String,
    _ body: (GRPCClient<DefaultTransport>) async throws -> Result
) async throws -> Result {
    try await withClient(apiKey: apiKey, transport: transport(host:), body)
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

/// Names of models available from the xAI API.
public enum Model {
    public static let grok_4_20_0309NonReasoning = "grok-4.20-0309-non-reasoning"
    public static let grok_4_20_0309Reasoning = "grok-4.20-0309-reasoning"
    public static let grok_4_20MultiAgent_0309 = "grok-4.20-multi-agent-0309"
    public static let grok_4_3 = "grok-4.3"
    public static let grok_4_5 = "grok-4.5"
    public static let grok_4_6 = "grok-4.6"
    public static let grok_4_7 = "grok-4.7"
    public static let grok_4_8 = "grok-4.8"
    public static let grok_4_9 = "grok-4.9"
    public static let grokBuild_0_1 = "grok-build-0.1"
    public static let grokImagineImage = "grok-imagine-image"
    public static let grokImagineImage_2_0 = "grok-imagine-image-2.0"
    public static let grokImagineImageQuality = "grok-imagine-image-quality"
    public static let grokImagineVideo = "grok-imagine-video"
    public static let grokImagineVideo_1_5 = "grok-imagine-video-1.5"
    public static let grokImagineVideo_1_5Lite = "grok-imagine-video-1.5-lite"
}
