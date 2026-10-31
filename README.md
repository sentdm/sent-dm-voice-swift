# Sent Voice Client for iOS

Calls for the people in your app: place phone and in-app calls from an iOS app, under the same contract as
the [web client](https://github.com/sentdm/sent-dm-voice-typescript).

This SDK places outbound calls: to a phone number, to a user of your app, or into a conference. Receiving
calls on a phone is not part of it; the web client receives calls.

Read the [Voice docs](https://docs.sent.dm/sdks/voice/ios) to get started.

## Install

A Swift package for iOS 15 or later. In Xcode, choose File → Add Package Dependencies and enter this
repository's URL, or add it to `Package.swift`:

```swift
.package(url: "https://github.com/sentdm/sent-dm-voice-swift.git", from: "0.1.0")
```

Add the `SentVoice` product to your app target. Calls use the microphone, so the app's `Info.plist` needs
`NSMicrophoneUsageDescription`; iOS asks the user on the first call.

## Quickstart

### 1. Mint voice tokens on your backend

Mint tokens on your server with your Sent API key, never in the app, for the user who is signed in:
`POST https://api.sent.dm/v3/voice/tokens` with `{ "identity": "<user>" }` answers with `data.token`.
Return it as text from an endpoint of your own, such as `/api/voice-token`. The
[web client](https://github.com/sentdm/sent-dm-voice-typescript/tree/main/packages/voice-client#1-mint-voice-tokens-on-your-backend)
shows the request and its options; they are the same for every platform.

### 2. Register and call

```swift
import SentVoice

let client = SentVoice.client(options: SentVoiceOptions(tokenProvider: {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://example.com/api/voice-token")!)
    return String(decoding: data, as: UTF8.self)
}))

try await client.register()

let call = try await client.connect(to: "+14155551234")
let listener = call.on { event in
    switch event {
    case .connected: print("Connected")
    case .disconnected(let state, _): print("The call ended as \(state)")
    default: break
    }
}
```

`connect(to:)` takes a phone number in E.164 format or the identity of another user of your app;
`joinConference(name:)` joins a conference. `hangup()`, `mute(_:)` and `sendDigits(_:)` on the call do
what they say. Keep one client for the life of the app: it refreshes the token before it expires, and
`destroy()` ends every call and releases it.

## Layout

| Path                      | What it is                                                                                     |
| ------------------------- | ---------------------------------------------------------------------------------------------- |
| `Sources/SentVoice`       | The iOS client: `SentVoice.client(options:)` and the adapter over the calling provider's SDK   |
| `Sources/SentVoiceCore`   | The provider-free core: the contract's vocabulary, errors, the call state machine, the token lifecycle and telemetry. Builds and tests on any Mac |
| `contract/`               | The pinned Voice Client contract and how to take a new version                                  |
| `scripts/`                | `generate-contract.py` writes `Contract.swift` from the contract; `check-contract` fails CI on a diff |

## Develop

```sh
python3 scripts/generate-contract.py   # after a contract change
swift build --target SentVoiceCore     # the core builds on any Mac
swift test                             # needs Xcode's toolchain for XCTest
```

`SentVoice` itself builds only for iOS: CI builds it against the simulator.

Releases are cut by release-please from `main` and published as a Swift package by tag.
