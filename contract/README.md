# Voice Client contract

`voice-client.json` is a pinned copy of the Voice Client contract every Sent Voice Client SDK agrees on,
taken from [`sent-dm-voice-typescript/contract`](https://github.com/sentdm/sent-dm-voice-typescript/tree/main/contract)
at the version its `version` field says. `scripts/generate-contract.py` turns it into
`Sources/SentVoiceCore/Contract.swift`; CI fails when the two disagree.

To take a new contract version: copy the file, run `python3 scripts/generate-contract.py`, make the code pass
the tests, and say in the PR which values moved. A removed or renamed value is a breaking change for apps.
