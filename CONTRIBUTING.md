# Contributing

This project is a spec-driven Zig implementation of TOON. Contributions should prioritize correctness against the official specification and upstream fixture behavior over premature refactors or micro-optimizations.

## Workflow

1. Read the relevant upstream fixture category before changing behavior.
2. Prefer extending `src/fixtures.zig` with official cases over adding ad hoc tests first.
3. Run:

```sh
zig build test
```

4. If behavior changes, update docs when the user-facing project state changes materially.

## Commit Standard

Use Conventional Commit style:

```text
type(scope): summary
```

Examples:

- `feat(encode): add safe key folding`
- `feat(decode): support path expansion conflicts`
- `fix(fixtures): isolate error-path cases with arena allocator`
- `docs(readme): update supported feature set`
- `refactor(tokenizer): preserve blank-line metadata`
- `test(numbers): add official decode number fixtures`

## Allowed Types

- `feat`
- `fix`
- `refactor`
- `test`
- `docs`
- `chore`

## Scope Guidance

Prefer a real subsystem name:

- `encode`
- `decode`
- `fixtures`
- `tokenizer`
- `docs`
- `build`
- `api`

## Commit Rules

- Keep the summary short and specific.
- Use imperative mood.
- One logical change per commit when practical.
- If a change is fixture-driven, mention the feature slice, not every file touched.
- Do not use vague messages like `update`, `changes`, `wip`, or `fix stuff`.

## Implementation Priorities

When choosing between multiple approaches:

1. Match the spec.
2. Match official fixture behavior.
3. Preserve deterministic output and stable parsing.
4. Optimize later.

## Testing Expectations

At minimum before committing:

```sh
zig build test
```

If you add support for a new upstream fixture category, wire it into `src/fixtures.zig` in the same change when possible.

## Continuity

If context is lost, read:

- `AGENTS.md`
- `README.md`
- `src/fixtures.zig`

