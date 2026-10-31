import Foundation

/// A value a telemetry payload field may hold.
public enum TelemetryValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var json: Any {
        switch self {
        case .string(let value): return String(value.prefix(Telemetry.maxTextLength))
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        }
    }
}

/// One event the SDK reports.
public struct TelemetryEvent: Sendable, Equatable {
    public let type: TelemetryEventName
    public let callId: String?
    public let occurredAt: Date
    public let payload: [String: TelemetryValue]

    public init(type: TelemetryEventName, callId: String? = nil, occurredAt: Date, payload: [String: TelemetryValue] = [:]) {
        self.type = type
        self.callId = callId
        self.occurredAt = occurredAt
        self.payload = payload
    }

    var json: [String: Any] {
        var out: [String: Any] = [
            "type": type.rawValue,
            "occurred_at": Telemetry.iso8601.string(from: occurredAt),
            "payload": payload.mapValues(\.json),
        ]
        if let callId { out["call_id"] = callId }
        return out
    }
}

/// Best-effort reporting to Sent: events queue, leave in batches a few seconds after the first one, and a
/// batch the API refuses or that never arrives is retried once with the next batch and then dropped.
public final class Telemetry: @unchecked Sendable {
    public static let path = "/v3/voice/telemetry"
    /// A batch leaves this long after the first event queued for it.
    public static let flushDelay: TimeInterval = 3
    /// A failed batch is retried with the next batch or, if nothing else happens, when this interval passes.
    public static let flushInterval: TimeInterval = 30
    public static let maxEvents = 100
    /// The Sent API refuses a body over 64 KiB.
    public static let maxBodyBytes = 60_000
    public static let maxTextLength = 500

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    struct Entry: Equatable {
        let event: TelemetryEvent
        var retried: Bool
    }

    private let lock = NSLock()

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
    private let url: URL
    private let sdkVersion: String
    private let http: HTTPClient
    private let disabled: Bool
    private var token: String?
    private var queue: [Entry] = []
    private var flushTask: Task<Void, Never>?
    private var destroyed = false

    public init(baseURL: URL = SentAPI.defaultBaseURL, sdkVersion: String = SentVoiceVersion.current, http: HTTPClient, disabled: Bool = false) {
        self.url = SentAPI.url(baseURL, path: Telemetry.path)
        self.sdkVersion = sdkVersion
        self.http = http
        self.disabled = disabled
    }

    /// The voice token the reports are sent with. Events recorded before the first token wait for it.
    public func useToken(_ token: String) {
        locked { self.token = token }
        scheduleFlush(after: 0)
    }

    public func record(_ type: TelemetryEventName, callId: String? = nil, payload: [String: TelemetryValue] = [:], at date: Date = Date()) {
        guard !disabled else { return }
        let accepted: Bool = locked {
            guard !destroyed else { return false }
            queue.append(Entry(event: TelemetryEvent(type: type, callId: callId, occurredAt: date, payload: payload), retried: false))
            if queue.count > Telemetry.maxEvents { queue.removeFirst(queue.count - Telemetry.maxEvents) }
            return true
        }
        if accepted { scheduleFlush(after: Telemetry.flushDelay) }
    }

    /// The events waiting to be sent, oldest first.
    public var pending: [TelemetryEvent] {
        locked { queue.map(\.event) }
    }

    /// Sends every queued event now. Returns once every batch has been answered or has failed.
    public func flush() async {
        let (token, entries) = takeQueue()
        guard let token, !entries.isEmpty else { return }
        for batch in Telemetry.split(entries, sdkVersion: sdkVersion) {
            await send(token: token, batch: batch)
        }
    }

    /// Stops reporting; nothing queued after this is sent.
    public func destroy() {
        let task: Task<Void, Never>? = locked {
            destroyed = true
            token = nil
            queue = []
            defer { flushTask = nil }
            return flushTask
        }
        task?.cancel()
    }

    private func scheduleFlush(after delay: TimeInterval) {
        locked {
            guard !destroyed, token != nil, flushTask == nil, !queue.isEmpty else { return }
            flushTask = Task { [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard let self, !Task.isCancelled else { return }
                self.locked { self.flushTask = nil }
                await self.flush()
                // Whatever is left (a retry) goes with the interval if nothing else happens.
                self.scheduleFlush(after: Telemetry.flushInterval)
            }
        }
    }

    private func takeQueue() -> (String?, [Entry]) {
        locked {
            let entries = queue
            queue = []
            return (token, entries)
        }
    }

    private func send(token: String, batch: [Entry]) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Telemetry.body(batch, sdkVersion: sdkVersion)
        if let (_, response) = try? await http.send(request), (200..<300).contains(response.statusCode) { return }
        // Retried once, with the next batch; never after destroy.
        locked {
            guard !destroyed else { return }
            let retries = batch.filter { !$0.retried }.map { Entry(event: $0.event, retried: true) }
            queue = Array((retries + queue).suffix(Telemetry.maxEvents))
        }
    }

    static func body(_ entries: [Entry], sdkVersion: String) -> Data {
        let object: [String: Any] = ["sdk_version": sdkVersion, "events": entries.map(\.event.json)]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// Splits entries into batches that stay under the API's body limit.
    static func split(_ entries: [Entry], sdkVersion: String) -> [[Entry]] {
        var batches: [[Entry]] = []
        var current: [Entry] = []
        var size = 0
        for entry in entries {
            let entrySize = ((try? JSONSerialization.data(withJSONObject: entry.event.json))?.count ?? 0) + 1
            if !current.isEmpty, size + entrySize > maxBodyBytes {
                batches.append(current)
                current = []
                size = 0
            }
            current.append(entry)
            size += entrySize
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }
}
