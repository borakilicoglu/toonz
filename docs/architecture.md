# Architecture Notes

## Project Direction

This codebase is intended to become a Zig implementation of TOON, not just a one-off converter. That means the design should optimize for:

- spec conformance first
- stable public API second
- performance third

Premature optimization is not useful until the official fixture suite passes.

## Module Split

- `src/lib.zig`: public API surface
- `src/errors.zig`: shared error set
- `src/encode.zig`: writer-oriented encoder
- `src/decode.zig`: parser-oriented decoder
- `src/tokenizer.zig`: line and token scanning helpers

## Implementation Strategy

### Phase 1

Bootstrap with a small supported subset so the API and ownership model settle early:

- scalars
- flat scalar arrays
- basic nested objects
- basic nested arrays

### Phase 2

Replace the subset parser/encoder with spec-aware behavior:

- header parsing
- row parsing
- delimiter detection and scoping
- quoted/unquoted scalar rules
- canonical normalization

### Phase 3

Conformance and ergonomics:

- strict mode
- fixture runner
- better diagnostics
- CLI

## Data Model

The current code uses `std.json.Value` as the interchange model. That keeps the first iteration small and maps directly onto the JSON data model required by TOON.

If allocation pressure or ownership ergonomics become a problem later, introduce an internal arena-backed value tree while keeping the public API stable.

