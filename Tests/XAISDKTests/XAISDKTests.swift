//
//  XAISDKTests.swift
//  XAISDK
//
//  Created by Alexey Demin on 2026-03-10.
//  Copyright © 2026 DnV1eX. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//

import Testing
import XAISDK
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

/// Verifies that the host for xAI services is correctly configured.
@Test func hostValue() {
    #expect(host == "api.x.ai")
}

/// Verifies the authHeader helper function.
@Test func testAuthHeader() {
    let header = authHeader(apiKey: "xai-TestKey")
    #expect(header == ["authorization": "Bearer xai-TestKey"])
}

/// Verifies that the MetadataInterceptor correctly appends the metadata to the request.
@Test func metadataInterceptor() async throws {
    let interceptor = MetadataInterceptor(metadata: ["test-header": "Test Value"])

    let request = StreamingClientRequest<String>(of: String.self, metadata: [:]) { _ in }
    let context = ClientContext(
        descriptor: MethodDescriptor(fullyQualifiedService: "test", method: "test"),
        remotePeer: "test",
        localPeer: "test"
    )
    
    let response = try await interceptor.intercept(request: request, context: context) { interceptedRequest, _ in
        // Assert that the headers match the expected format.
        #expect(Array(interceptedRequest.metadata[stringValues: "test-header"]) == ["Test Value"])
        return StreamingClientResponse<String>(of: String.self, error: RPCError(code: .unknown, message: ""))
    }
    
    switch response.accepted {
    case .success:
        Issue.record("Expected failure")
    case .failure(let error):
        #expect(error.code == .unknown)
    }
}

/// Verifies that the gRPC client is successfully initialized for direct access.
@Test func clientInitDirect() throws {
    let clientInstance = try client(apiKey: "xai-TestKey")
    #expect(type(of: clientInstance) == GRPCClient<HTTP2ClientTransport.TransportServices>.self)
}

/// Verifies that the gRPC client is successfully initialized for proxy access.
@Test func clientInitProxy() throws {
    let clientInstance = try client(proxy: "test.proxy.host", metadata: ["test-header": "Test Value"])
    #expect(type(of: clientInstance) == GRPCClient<HTTP2ClientTransport.TransportServices>.self)
}

/// Verifies the behavior of the convenience 'withClient' wrapper for direct access.
@Test func withClientWrapperDirect() async throws {
    let result = try await withClient(apiKey: "xai-TestKey") { client in
        // Small delay to ensure the client stays alive during the test block.
        try await Task.sleep(nanoseconds: 10_000_000)
        return "success"
    }
    #expect(result == "success")
}

/// Verifies the behavior of the convenience 'withClient' wrapper for proxy access.
@Test func withClientWrapperProxy() async throws {
    let result = try await withClient(proxy: "test.proxy.host", metadata: ["test-header": "Test Value"]) { client in
        // Small delay to ensure the client stays alive during the test block.
        try await Task.sleep(nanoseconds: 10_000_000)
        return "success"
    }
    #expect(result == "success")
}

/// Verifies the behavior of the start and close extension methods on GRPCClient.
@Test func clientStartAndClose() async throws {
    let clientInstance = try client(apiKey: "xai-TestKey")
    
    let connectionTask = clientInstance.start()
    
    // Give the background task a moment to actually start running connections.
    try await Task.sleep(nanoseconds: 10_000_000)
    
    try await clientInstance.close(connectionTask)
}
