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

/// Verifies that the base URL for xAI services is correctly configured.
@Test func baseURLValue() {
    #expect(baseURL == "api.x.ai")
}

/// Verifies that the AuthInterceptor correctly appends the API key to the request metadata.
@Test func authInterceptor() async throws {
    let interceptor = AuthInterceptor(apiKey: "test-key")
    
    let request = StreamingClientRequest<String>(of: String.self, metadata: [:]) { _ in }
    let context = ClientContext(
        descriptor: MethodDescriptor(fullyQualifiedService: "test", method: "test"),
        remotePeer: "test",
        localPeer: "test"
    )
    
    let response = try await interceptor.intercept(request: request, context: context) { interceptedRequest, _ in
        // Assert that the 'authorization' header matches the expected 'Bearer <apiKey>' format.
        #expect(Array(interceptedRequest.metadata[stringValues: "authorization"]) == ["Bearer test-key"])
        return StreamingClientResponse<String>(of: String.self, error: RPCError(code: .unknown, message: ""))
    }
    
    switch response.accepted {
    case .success:
        Issue.record("Expected failure")
    case .failure(let error):
        #expect(error.code == .unknown)
    }
}

/// Verifies that the gRPC client is successfully initialized with the required configuration.
@Test func clientInit() throws {
    let clientInstance = try client(apiKey: "test-key")
    #expect(type(of: clientInstance) == GRPCClient<HTTP2ClientTransport.TransportServices>.self)
}

/// Verifies the behavior of the convenience 'withClient' wrapper.
@Test func withClientWrapper() async throws {
    let result = try await withClient(apiKey: "test-key") { client in
        // Small delay to ensure the client stays alive during the test block.
        try await Task.sleep(nanoseconds: 10_000_000)
        return "success"
    }
    #expect(result == "success")
}

/// Verifies the behavior of the start and close extension methods on GRPCClient.
@Test func clientStartAndClose() async throws {
    let clientInstance = try client(apiKey: "test-key")
    
    let connectionTask = clientInstance.start()
    
    // Give the background task a moment to actually start running connections.
    try await Task.sleep(nanoseconds: 10_000_000)
    
    try await clientInstance.close(connectionTask)
}
