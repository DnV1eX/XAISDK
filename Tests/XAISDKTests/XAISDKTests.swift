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

import Foundation
import Synchronization
import Testing
import XAISDK
import GRPCCore
import GRPCInProcessTransport
import SwiftProtobuf

/// API key for live tests. Absent skips those tests.
private let xaiAPIKey = ProcessInfo.processInfo.environment["XAI_API_KEY"]

/// Verifies that the host for xAI services is correctly configured.
@Test func hostValue() {
    #expect(host == "api.x.ai")
}

/// Verifies that watermark warnings are enabled unless turned off.
@Test func isWatermarkWarningEnabledByDefault() {
    #expect(isWatermarkWarningEnabled)
}

/// Verifies the authHeader helper function.
@Test func testAuthHeader() {
    let header = authHeader(apiKey: "xai-TestKey")
    #expect(header == ["authorization": "Bearer xai-TestKey"])
}

/// Verifies that the MetadataRequestInterceptor correctly appends the metadata to the request.
@Test func metadataRequestInterceptor() async throws {
    let interceptor = MetadataRequestInterceptor(metadata: ["test-header": "Test Value"])

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

/// Verifies that the WatermarkResponseInterceptor forwards the response and reads the watermark flag.
@Test func watermarkResponseInterceptor() async throws {
    let interceptor = WatermarkResponseInterceptor()
    let request = StreamingClientRequest<String>(of: String.self, metadata: [:]) { _ in }
    let context = ClientContext(
        descriptor: MethodDescriptor(fullyQualifiedService: "test", method: "test"),
        remotePeer: "test",
        localPeer: "test"
    )

    let plainResponse = try await interceptor.intercept(request: request, context: context) { _, _ in
        let parts = AsyncThrowingStream<StreamingClientResponse<String>.Contents.BodyPart, any Error> { $0.finish() }
        return StreamingClientResponse(
            metadata: [watermarkMetadataKey: .string("false")],
            bodyParts: RPCAsyncSequence(wrapping: parts)
        )
    }
    #expect(Array(plainResponse.metadata[stringValues: watermarkMetadataKey]) == ["false"])

    let isEnabled = isWatermarkWarningEnabled
    isWatermarkWarningEnabled = false
    defer { isWatermarkWarningEnabled = isEnabled }
    let watermarkedResponse = try await interceptor.intercept(request: request, context: context) { _, _ in
        let parts = AsyncThrowingStream<StreamingClientResponse<String>.Contents.BodyPart, any Error> { $0.finish() }
        return StreamingClientResponse(
            metadata: [watermarkMetadataKey: .string("true")],
            bodyParts: RPCAsyncSequence(wrapping: parts)
        )
    }
    #expect(Array(watermarkedResponse.metadata[stringValues: watermarkMetadataKey]) == ["true"])
}

/// Verifies that the gRPC client is successfully initialized for direct access.
@Test func clientInitDirect() throws {
    let clientInstance = try client(apiKey: "xai-TestKey")
    #expect(type(of: clientInstance) == GRPCClient<DefaultTransport>.self)
}

/// Verifies that the gRPC client is successfully initialized for proxy access.
@Test func clientInitProxy() throws {
    let clientInstance = try client(proxy: "test.proxy.host", metadata: ["test-header": "Test Value"])
    #expect(type(of: clientInstance) == GRPCClient<DefaultTransport>.self)
}

/// Verifies the behavior of the convenience 'withClient' wrapper for direct access.
@Test func withClientWrapperDirect() async throws {
    let result = try await withClient(apiKey: "xai-TestKey", transport: { _ in InProcessTransport().client }) { client in
        // Small delay to ensure the client stays alive during the test block.
        try await Task.sleep(nanoseconds: 10_000_000)
        return "success"
    }
    #expect(result == "success")
}

/// Verifies the behavior of the convenience 'withClient' wrapper for proxy access.
@Test func withClientWrapperProxy() async throws {
    let result = try await withClient(proxy: "test.proxy.host", metadata: ["test-header": "Test Value"], transport: { _ in InProcessTransport().client }) { client in
        // Small delay to ensure the client stays alive during the test block.
        try await Task.sleep(nanoseconds: 10_000_000)
        return "success"
    }
    #expect(result == "success")
}

/// Verifies the behavior of the start and close extension methods on GRPCClient.
@Test func clientStartAndClose() async throws {
    let clientInstance = try client(apiKey: "xai-TestKey", transport: { _ in InProcessTransport().client })
    
    let connectionTask = clientInstance.start()
    
    // Give the background task a moment to actually start running connections.
    try await Task.sleep(nanoseconds: 10_000_000)
    
    try await clientInstance.close(connectionTask)
}

/// Checks listed models against `Model`. Video models are absent from the list calls.
@Test(.enabled(if: xaiAPIKey != nil, "Set XAI_API_KEY to run this test"))
func liveListModels() async throws {
    let apiKey = try #require(xaiAPIKey)
    let names = try await withClient(apiKey: apiKey) { grpcClient in
        let models = XaiApi_Models.Client(wrapping: grpcClient)
        let language = try await models.listLanguageModels(Google_Protobuf_Empty())
        let embedding = try await models.listEmbeddingModels(Google_Protobuf_Empty())
        let image = try await models.listImageGenerationModels(Google_Protobuf_Empty())
        return language.models.map(\.name) + embedding.models.map(\.name) + image.models.map(\.name)
    }
    #expect(Set(names) == [
        Model.grok_4_20_0309NonReasoning,
        Model.grok_4_20_0309Reasoning,
        Model.grok_4_20MultiAgent_0309,
        Model.grok_4_3,
        Model.grok_4_5,
        Model.grok_4_6,
        Model.grok_4_7,
        Model.grokBuild_0_1,
        Model.grokImagineImage,
        Model.grokImagineImage_2_0,
    ])
}

/// Checks that a grok-4.7 response is not watermarked.
@Test(.enabled(if: xaiAPIKey != nil, "Set XAI_API_KEY to run this test"))
func languageModelWatermarkDisabled() async throws {
    let apiKey = try #require(xaiAPIKey)
    let calls = Mutex(0)
    try await withGRPCClient(
        transport: try transport(host: host),
        interceptors: [
            MetadataRequestInterceptor(metadata: authHeader(apiKey: apiKey)),
            WatermarkResponseInterceptor {
                calls.withLock { $0 += 1 }
            },
        ]
    ) { grpcClient in
        let chat = XaiApi_Chat.Client(wrapping: grpcClient)
        var request = XaiApi_GetCompletionsRequest()
        var content = XaiApi_Content()
        content.text = "Reply with the single word ok."
        var message = XaiApi_Message()
        message.content = [content]
        message.role = .roleUser
        request.messages = [message]
        request.model = Model.grok_4_7
        request.maxTokens = 16
        _ = try await chat.getCompletion(request)
    }
    #expect(calls.withLock { $0 } == 0)
}
