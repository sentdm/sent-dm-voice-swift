#!/usr/bin/env python3
"""Generates Sources/SentVoiceCore/Contract.swift from contract/voice-client.json.

Every state, event name, error code, timing value and telemetry name the SDK uses
comes from here, so the Swift SDK cannot drift from the other Voice Client SDKs.
Run it after changing the contract; CI runs it and fails on a diff.
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "contract" / "voice-client.json"
OUT = ROOT / "Sources" / "SentVoiceCore" / "Contract.swift"

KEYWORDS = {"default", "in", "is", "as", "case", "class", "enum", "for", "if", "import", "init"}


def ident(name: str) -> str:
    """A Swift case name for a contract value: lowerCamel, dots and underscores folded."""
    parts = re.split(r"[._\-]", name)
    if name.isupper():
        parts = [p.lower() for p in parts]
    out = parts[0][0].lower() + parts[0][1:] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
    return f"`{out}`" if out in KEYWORDS else out


def enum(name: str, values, doc: str) -> str:
    lines = [f"/// {doc}", f"public enum {name}: String, CaseIterable, Sendable, Codable {{"]
    for value in values:
        case = ident(value)
        lines.append(f"    case {case}" + (f' = "{value}"' if case.strip("`") != value else ""))
    lines.append("}")
    return "\n".join(lines)


def main() -> None:
    c = json.loads(CONTRACT.read_text())
    version = c["version"]
    errors, client, call = c["errors"], c["client"], c["call"]
    out = [
        f"// Generated from contract/voice-client.json {version} by scripts/generate-contract.py. Do not edit.",
        "",
        "import Foundation",
        "",
        "/// The Voice Client contract this SDK implements: the vocabulary every Sent Voice Client SDK shares.",
        "public enum Contract {",
        f'    public static let version = "{version}"',
        "",
        "    /// Which call states a call may move to from each state.",
        "    public static let callTransitions: [CallState: [CallState]] = [",
    ]
    for state, nexts in call["transitions"].items():
        out.append(f"        .{ident(state)}: [{', '.join('.' + ident(n) for n in nexts)}],")
    out += [
        "    ]",
        "",
        "    /// The error classes the contract names, with the category and retriability of each.",
        "    public static let errorClasses: [ErrorClass] = [",
    ]
    for cls in errors["classes"]:
        out.append(
            f'        ErrorClass(name: "{cls["name"]}", code: .{ident(cls["code"])}, '
            f'category: .{ident(cls["category"])}, retriable: {str(cls["retriable"]).lower()}),'
        )
    out += [
        "    ]",
        "",
        "    /// The fields a telemetry payload may carry.",
        "    public static let telemetryPayloadFields: [String] = ["
        + ", ".join(f'"{f}"' for f in c["telemetry"]["payloadFields"])
        + "]",
        "}",
        "",
        enum("ClientState", client["states"], "The states a client moves through."),
        "",
        enum("ClientEventName", client["events"], "The events a client emits."),
        "",
        enum("CallState", call["states"], "The states a call moves through."),
        "",
        "extension CallState {",
        "    /// The state a call starts in, by direction.",
        "    public static func initial(for direction: CallDirection) -> CallState {",
        "        switch direction {",
        f"        case .inbound: return .{ident(call['initialState']['inbound'])}",
        f"        case .outbound: return .{ident(call['initialState']['outbound'])}",
        "        }",
        "    }",
        "",
        "    /// Whether the contract allows a call in this state to move to `next`.",
        "    public func canTransition(to next: CallState) -> Bool {",
        "        Contract.callTransitions[self]?.contains(next) ?? false",
        "    }",
        "",
        "    /// A state no call leaves.",
        "    public var isTerminal: Bool { Contract.callTransitions[self]?.isEmpty ?? true }",
        "}",
        "",
        "/// Who placed the call.",
        "public enum CallDirection: String, CaseIterable, Sendable, Codable {",
        "    case inbound",
        "    case outbound",
        "}",
        "",
        enum("CallEventName", call["events"], "The events a call emits."),
        "",
        enum("InviteEventName", c["invite"]["events"], "The events an incoming-call invite emits."),
        "",
        enum("AudioEventName", c["audio"]["events"], "The events the audio layer emits."),
        "",
        enum("ErrorCode", errors["codes"], "The error codes an SDK error carries."),
        "",
        enum("ErrorCategory", errors["categories"], "The categories an SDK error belongs to."),
        "",
        "/// An error class the contract names.",
        "public struct ErrorClass: Sendable, Equatable {",
        "    public let name: String",
        "    public let code: ErrorCode",
        "    public let category: ErrorCategory",
        "    public let retriable: Bool",
        "}",
        "",
        "/// When a voice token is refreshed and how failed fetches are retried, in seconds.",
        "public enum TokenTiming {",
        f"    public static let refreshShare: Double = {c['token']['refreshShare']}",
        f"    public static let refreshMargin: TimeInterval = {c['token']['refreshMarginMs'] / 1000}",
        f"    public static let initialRetryDelay: TimeInterval = {c['token']['initialRetryDelayMs'] / 1000}",
        f"    public static let maxRetryDelay: TimeInterval = {c['token']['maxRetryDelayMs'] / 1000}",
        f"    public static let offlineRetryInterval: TimeInterval = {c['token']['offlineRetryIntervalMs'] / 1000}",
        "}",
        "",
        enum("TelemetryEventName", c["telemetry"]["events"], "The events the SDK reports to Sent."),
        "",
    ]
    OUT.write_text("\n".join(out))
    print(f"wrote {OUT.relative_to(ROOT)} from contract {version}")


if __name__ == "__main__":
    main()
