#if os(iOS)
import Foundation
import SentVoiceCore

/// The Sent Voice Client for iOS: a `SentVoiceClient` over the provider's SDK.
///
/// ```swift
/// let client = SentVoice.client(options: SentVoiceOptions(tokenProvider: { try await myBackend.voiceToken() }))
/// try await client.register()
/// let call = try await client.connect(to: "+14155551234")
/// ```
public enum SentVoice {
    /// A client that registers and places calls on this device. Keep one for the life of the app.
    public static func client(options: SentVoiceOptions) -> SentVoiceClient {
        SentVoiceClient(options: options, adapter: SinchAdapter())
    }
}
#endif
