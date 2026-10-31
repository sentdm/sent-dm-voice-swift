# Sent Voice Client for iOS

Calls for the people in your app: place phone and in-app calls from an iOS app, under the same contract as
the [web client](https://github.com/sentdm/sent-dm-voice-typescript).

Status: in development, not yet published. The first release places outbound calls (to a phone number, a
user of your app, or a conference). Receiving calls on a phone needs push credentials registered with Sent,
which is platform work scheduled separately; it arrives as a minor version with no change to this SDK's shape.

Read the [Voice docs](https://docs.sent.dm) to get started.

## Layout

| Path                      | What it is                                                                                     |
| ------------------------- | ---------------------------------------------------------------------------------------------- |
| `Sources/SentVoiceCore`   | The provider-free core: the contract's vocabulary, errors, the call state machine, the token lifecycle and telemetry. Builds and tests on any Mac |
| `contract/`               | The pinned Voice Client contract and how to take a new version                                  |
| `scripts/`                | `generate-contract.py` writes `Contract.swift` from the contract; `check-contract` fails CI on a diff |

The iOS client over the provider's SDK is the next target to land, as `SentVoice`.

## Develop

```sh
python3 scripts/generate-contract.py   # after a contract change
swift build
swift test                             # needs Xcode's toolchain for XCTest
```

Releases are cut by release-please from `main` and published as a Swift package by tag.
