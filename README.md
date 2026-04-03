# xAI Swift SDK

The xAI Swift SDK is a gRPC-based Swift library for interacting with xAI's APIs. It provides a native, high-performance interface to interact with xAI APIs from Swift code, allowing you to easily generate text, images, and utilize other xAI services directly within your Apple ecosystem applications, as well as in Swift client and server applications on other platforms.

For more details on the underlying API, see the [xAI gRPC API Reference](https://docs.x.ai/developers/grpc-api-reference).

## Installation

Add the xAI Swift SDK to your project using Swift Package Manager.

In Xcode, go to **File > Add Package Dependencies...** and enter the repository URL:
```text
https://github.com/DnV1eX/XAISDK.git
```

Or add it directly to your `Package.swift` file:
```swift
dependencies: [
    .package(url: "https://github.com/DnV1eX/XAISDK.git", from: "1.0.0")
]
```

## Usage

The SDK provides two primary variants of usage: direct connection to xAI services and connection through an API proxy. For both variants, you can interact with the API using a managed `client` for multiple requests, or a convenience `withClient` wrapper for one-time requests.

### Direct Connection

Direct connection to xAI services using your API key is the primary method for use on a server or during development.

#### 1. Using `client` (Recommended for multiple requests)

If you need to make multiple requests over time (e.g., in a long-lived application or a chat interface), you should create a single client instance and manage its connection manually using the `start()` and `close(_:)` functions. This avoids the overhead of establishing a new HTTP/2 connection for every request.

```swift
import XAISDK

let apiKey = "XAI_API_KEY"

// 1. Initialize the client.
guard let xaiClient = try? client(apiKey: apiKey) else {
    return
}

// 2. Start the connection in a background task.
let connectionTask = xaiClient.start()

// 3. Make your requests using the client.
let chatClient = XaiApi_Chat.Client(wrapping: xaiClient)
var getCompletionsRequest = XaiApi_GetCompletionsRequest()
var content1 = XaiApi_Content()
content1.text = "You are Grok, a highly intelligent, helpful AI assistant."
var message1 = XaiApi_Message()
message1.content = [content1]
message1.role = .roleSystem
var content2 = XaiApi_Content()
content2.text = "What is the meaning of life, the universe, and everything?"
var message2 = XaiApi_Message()
message2.content = [content2]
message2.role = .roleUser
getCompletionsRequest.messages = [message1, message2]
getCompletionsRequest.model = "grok-4.20-beta-latest-non-reasoning"
do {
    let getChatCompletionResponse = try await chatClient.getCompletion(getCompletionsRequest)
    print(getChatCompletionResponse.outputs.first?.message.content ?? "No response content")
} catch {
    print("Error: \(error)")
}

// 4. When you are completely done with the client, shut it down gracefully.
try? await xaiClient.close(connectionTask)
```

#### 2. Using `withClient` (Recommended for one-time requests)

The `withClient(apiKey:)` function automatically manages the lifecycle of the gRPC connection. It opens the connection, executes your closure, and gracefully shuts down the connection when the closure completes. This is ideal for single, isolated requests.

```swift
import XAISDK

let apiKey = "XAI_API_KEY"

do {
    let imageResponse = try await withClient(apiKey: apiKey) { client in
        let imageClient = XaiApi_Image.Client(wrapping: client)
        var generateImageRequest = XaiApi_GenerateImageRequest()
        generateImageRequest.prompt = "A collage of London landmarks in a stenciled street‑art style"
        generateImageRequest.model = "grok-imagine-image"
        generateImageRequest.format = .imgFormatURL
        return try await imageClient.generateImage(generateImageRequest)
    }
    print(imageResponse.images.first?.url)
} catch {
    print("Error: \(error)")
}
```

### Connection Through an API Proxy

When the SDK is used in a production client app, connecting through an API proxy is a safer option that prevents your xAI API key from leaking. Instead of embedding the API key in your app, you connect to your own proxy server, which then securely attaches the API key and forwards the request to xAI.

You can use the `metadata` parameter to send time-based tokens, Apple's App Attest signatures, or other custom authorization headers to authenticate the client with your proxy server.

```swift
import XAISDK

let proxyHost = "proxy.yourdomain.com"

// Generate your App Attest signature or time-based token.
let appAttestSignature = "..."

// Initialize the client with the proxy host and custom metadata for your proxy's auth.
guard let xaiClient = try? client(proxy: proxyHost, metadata: ["x-app-attest": appAttestSignature]) else {
    return
}

// Start the client, use it as normal, and then close it. Alternatively, use `withClient(proxy:metadata:)`.
```

## Supported Platforms

**Apple Platforms (using Network framework transport):**
The SDK requires the following minimum platform versions:
- macOS 15.0+
- iOS 18.0+
- watchOS 11.0+
- tvOS 18.0+
- visionOS 2.0+

> [!TIP]
> If you need to support earlier platform versions, you can build the SDK by changing the major versions of the gRPC dependencies in `Package.swift` from `2.0.0` down to `1.0.0` (and adjusting the code to match the `grpc-swift` v1 API).

**Non-Apple Platforms (using POSIX transport):**
- Linux
- Windows
- Android
- WASI
- OpenBSD

## Advanced: Updating the SDK

For library maintainers, if the upstream xAI protobuf definitions change, you can regenerate the Swift source files using the Swift Package Manager plugin.

Run the following commands from the root of the repository:

1. Update the git submodule containing the protobuf definitions:
```bash
git submodule update --remote xai-proto
```

2. Regenerate the Swift source files:
```bash
swift package --allow-writing-to-package-directory generate-grpc-code-from-protos --output-path Sources/XAISDK --no-servers --access-level public -- googleapis xai-proto/proto
```

> [!NOTE]
> This command requires the `protoc` compiler to be installed on your system. 
> - On macOS, you can install it using Homebrew: `brew install protobuf`
> - Alternatively, you can download the pre-compiled binary directly from the [Protocol Buffers Releases page](https://github.com/protocolbuffers/protobuf/releases).

## License
Copyright © 2026 DnV1eX. All rights reserved. Licensed under the Apache License, Version 2.0.

> [!IMPORTANT]
> I appreciate your interest in this project and hope you find it useful. Please bookmark it with a ⭐️ for further reference and updates. I welcome your feedback and thank you for your support!
