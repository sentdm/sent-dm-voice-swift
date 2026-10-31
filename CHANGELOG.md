# Changelog

## [0.2.1](https://github.com/sentdm/sent-dm-voice-swift/compare/v0.2.0...v0.2.1) (2026-10-31)


### Documentation

* this SDK places calls; receiving is the web client's ([f656ca1](https://github.com/sentdm/sent-dm-voice-swift/commit/f656ca12fc1777fffd1437fe2dfac2863e5a046b))

## [0.2.0](https://github.com/sentdm/sent-dm-voice-swift/compare/v0.1.1...v0.2.0) (2026-10-31)


### Features

* call quality warnings ([f4671dd](https://github.com/sentdm/sent-dm-voice-swift/commit/f4671dddc62f072b23beab559bdd9af66d669406))

## [0.1.1](https://github.com/sentdm/sent-dm-voice-swift/compare/v0.1.0...v0.1.1) (2026-10-31)


### Documentation

* install and quick start for the first release ([2eebc76](https://github.com/sentdm/sent-dm-voice-swift/commit/2eebc76cf64e908d59beda255c739ef596715a9d))
* security policy ([45371e7](https://github.com/sentdm/sent-dm-voice-swift/commit/45371e7e08c7013a49f719253ea13f3381921791))

## 0.1.0 (2026-10-31)


### Features

* the client: register, place calls, follow them, keep the token fresh ([d90a365](https://github.com/sentdm/sent-dm-voice-swift/commit/d90a365a1a0b065640459178485d31371d58ca82))
* the client: register, place calls, follow them, keep the token fresh ([87c2e3b](https://github.com/sentdm/sent-dm-voice-swift/commit/87c2e3bc475712f3bfbebf39d2d8ba4af85697dc))
* the iOS client over the provider's SDK ([c85d963](https://github.com/sentdm/sent-dm-voice-swift/commit/c85d9630d207b77562fff071d37644d82909c511))
* the iOS client over the provider's SDK ([add8c46](https://github.com/sentdm/sent-dm-voice-swift/commit/add8c464bb7944b3be30ab4a4f56e8dba7141cfe))
* the provider-free core: contract, errors, call states, token lifecycle, telemetry ([93d37a3](https://github.com/sentdm/sent-dm-voice-swift/commit/93d37a3f2dd7eed1c65410c77727fb2b5607ab0c))
* the provider-free core: contract, errors, call states, token lifecycle, telemetry ([22a9ac7](https://github.com/sentdm/sent-dm-voice-swift/commit/22a9ac7e26e85d34e3c4323f00bc76dcea24fef0))


### Bug Fixes

* a flush before the first token keeps the events; the telemetry test's clock ([5f2c6f8](https://github.com/sentdm/sent-dm-voice-swift/commit/5f2c6f877700496cea1a82a798ba3f5b1dcd704e))
* a listener stays until its token is cancelled, not until the token is dropped ([48fa1e1](https://github.com/sentdm/sent-dm-voice-swift/commit/48fa1e1003f7549603d07fdfafa0d4dfc9469044))
* the iOS target builds empty on a Mac and keeps its own lock helper ([6b05d21](https://github.com/sentdm/sent-dm-voice-swift/commit/6b05d21015a5324d7a5365a221f761cfd100684b))
* the provider's DTMF call takes its digits under a label ([e08fba2](https://github.com/sentdm/sent-dm-voice-swift/commit/e08fba276cd6de89b8c654f89cf3685d050ada75))
