# Review instructions

Apply these to every pull request.

## Report these as Important, as well as functional bugs

- A violation of this repository's `CLAUDE.md`. Quote the rule.
- A new public type, method, option, event or error code that the PR
  description does not list.
- A hand edit to `Sources/SentVoiceCore/Contract.swift`, or a change to
  `contract/voice-client.json` without the regenerated file and a PR
  description that says which values moved.
- A behaviour change with no test that fails before it and passes after.
- A path that calls Sent's servers or the provider in a default test run.
- A fix made to one copy of logic that exists more than once: this client
  and the web client, a method and its async twin.
- A commit subject that would read wrong in the changelog: an internal
  cause, a link customers can't open, or a type that cuts a release for a
  change customers don't see.
- A link to, or the name of, a private Sent repository, an internal system
  or a provider, anywhere in the diff other than the adapter and
  `Package.swift`.
- A comment that restates the code.

## Don't report these

- Formatting.
- Missing client-side validation of values the Sent API already validates.
