# toonz

Zig implementation of TOON (Token-Oriented Object Notation).

This repo is a spec-driven encoder/decoder project built against the official TOON specification and upstream conformance fixtures.

## Current State

The project is no longer a bootstrap stub. It currently supports a substantial TOON surface:

- primitives
- objects
- inline primitive arrays
- tabular arrays
- nested arrays
- list-format mixed arrays
- root forms
- delimiter-aware parsing
- strict validation subset
- whitespace tolerance subset
- number decoding normalization subset
- path expansion (`expandPaths = safe | off`)
- key folding (`keyFolding = safe | off`)

`zig build test` currently passes.

## Reference Sources

- Spec: `https://github.com/toon-format/spec/blob/main/SPEC.md`
- Conformance tests: `https://github.com/toon-format/spec/tree/main/tests`
- Reference implementation: `https://github.com/toon-format/toon/tree/main/packages/toon`
- Initial seed doc reviewed for this project: `/Users/macbook/Desktop/implementations.md`

Observed upstream spec metadata during implementation:

- Version: `3.0`
- Status: `Working Draft`
- Date: `2025-11-24`

## Main Files

- `src/lib.zig`: public API
- `src/encode.zig`: encoder
- `src/decode.zig`: decoder
- `src/fixtures.zig`: official fixture runner
- `src/tokenizer.zig`: line scanner and indentation metadata
- `src/value.zig`: recursive cleanup helpers
- `AGENTS.md`: continuity notes for future agents

## Build

```sh
zig build test
```

## Contributing

Contribution and commit rules live in `CONTRIBUTING.md`.

## Notes

- The fixture runner is selective: it whitelists supported upstream fixture cases instead of pretending full-suite coverage.
- `AGENTS.md` contains the most current implementation summary and recommended next steps.
- The next likely work items are broader fixture coverage, stricter canonical number encoding, and CLI ergonomics.
