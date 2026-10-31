# Working in this repository

Context for contributors, human or AI, on how this SDK is put together and
the things reviews come back to. [REVIEW.md](REVIEW.md) is the rubric a
reviewer applies.

## Overview

The Sent Voice Client for iOS, a Swift package: `SentVoiceCore` is the
provider-free core (the contract's vocabulary, errors, the call state
machine, the token lifecycle, telemetry) and `SentVoice` is the client over
the provider's native SDK. Hand-written, except `Contract.swift`, which
`scripts/generate-contract.py` writes from the pinned contract. It mirrors
the web client in `sent-dm-voice-typescript`: same contract, same token
exchange, same telemetry, same error and state vocabulary, so a fix in one
usually means a fix in the other.

### Who owns which files

- **`contract/voice-client.json`** is a pinned copy of the Voice Client
  contract. Taking a new version is a versioned change: copy the file, run
  the generator, make the tests pass, say in the PR which values moved. A
  removed or renamed value is a breaking change for apps.
- **`Sources/SentVoiceCore/Contract.swift` is generated.** Don't edit it;
  change the contract or the generator. CI fails on a diff.
- **release-please-owned**: `CHANGELOG.md`, `.release-please-manifest.json`
  and `Sources/SentVoiceCore/Version.swift`'s version line.
- Everything else is hand-written and reviewed as written.

### Branches

- PRs target `main`.
- Branches named `release-please--branches--main` belong to release-please.
  Don't push to them or merge into them. Merging the release PR tags the
  release, which is how a Swift package publishes.

## Build, test, lint

`swift build` and `swift test` from the package root; `scripts/check-contract`
before pushing a contract change. `SentVoiceCore` builds and tests on any
Mac; the `SentVoice` target needs the iOS SDK and builds for the simulator
in CI. Nothing in a default run calls Sent's servers: tests use a fake HTTP
client.

## Breaking changes

- **Anything a user can import or call without a private marker is public,**
  documented or not. New names start private and are made public on purpose.
- **Runtime behaviour is the contract.** A change only the compiler notices
  isn't breaking. A change in what the code does at runtime is, even when
  every signature stays the same, and so is a contract value removed or
  renamed.
- **Keep old code working.** A rename or a removal keeps an alias. A
  behaviour change users could depend on waits for a deprecation cycle or
  the next major version.
- **A major version is a maintainer's call.** Describe the compatibility
  impact in the PR instead of deciding it in the commit type.
- **A fix here is a fix in the web client and the Android client** when they
  expose the same thing; link the sibling PRs.

## Commits and pull requests

- **Conventional Commits drive release-please**: `feat:`, `fix:`,
  `chore:`, `docs:`. The subject becomes the changelog line customers read,
  so write it for them: what changed, and what to do about it. Never an
  internal cause.
- **`ci:` and `test:` are hidden from the changelog.** `chore:`, `docs:`,
  `feat:` and `fix:` are not, and any of them cuts a release when the
  release PR is merged.
- **One logical change per PR.**
- **The description says** what was wrong, with a before-and-after example,
  what changed, and how you know it works. Call out behaviour changes and
  anything that changes what the client sends or receives.
- **This repository is public.** Nothing in it, including PR text,
  changelogs and release notes, links to or names Sent's private
  repositories, internal systems or the providers behind a channel. One
  exception the package cannot avoid: the client depends on a provider's
  native SDK, so that provider's name is in the `SentVoice` target's adapter
  and in `Package.swift`. Keep it there and nowhere else: never in a public
  type or option name, the README, a changelog or a release note.
