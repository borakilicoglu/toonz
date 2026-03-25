![TOON](https://raw.githubusercontent.com/toon-format/toon/main/.github/og.png)

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
- Initial seed doc reviewed for this project: `https://toonformat.dev/ecosystem/implementations.html`

## Main Files

- `src/lib.zig`: public API
- `src/encode.zig`: encoder
- `src/decode.zig`: decoder
- `src/fixtures.zig`: official fixture runner
- `src/tokenizer.zig`: line scanner and indentation metadata
- `src/value.zig`: recursive cleanup helpers

## Build

```sh
zig build test
```

## Installation

This project is currently consumed as a source dependency from the repository.

Add `toonz` to your `build.zig.zon` dependencies, then import the module in `build.zig`:

```zig
const toonz = b.dependency("toonz", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("toonz", toonz.module("toonz"));
```

## Example

**JSON**

```json
{"users":[{"id":1,"name":"Ada"},{"id":2,"name":"Bob"}]}
```

**TOON**

```toon
users[2]{id,name}:
  1,Ada
  2,Bob
```

## API Matrix

| Function | Input | Output | Notes |
|----------|-------|--------|-------|
| `encodeAlloc` | `std.json.Value` | TOON text | Encoder options include delimiter, indentation, trailing newline, and key folding |
| `decodeAlloc` | TOON text | `std.json.Value` | Decoder options include strict validation and path expansion |
| `transcodeJsonToToonAlloc` | JSON text | TOON text | Parses JSON, then encodes TOON |
| `transcodeToonToJsonAlloc` | TOON text | JSON text | Decodes TOON, then serializes JSON |

## Usage

Encode a `std.json.Value` into TOON:

```zig
const std = @import("std");
const toonz = @import("toonz");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

var user = std.json.ObjectMap.init(allocator);
try user.put("name", .{ .string = "Bora" });
try user.put("active", .{ .bool = true });

const value = std.json.Value{ .object = user };
const output = try toonz.encodeAlloc(allocator, value, .{
    .trailing_newline = false,
});

std.debug.print("{s}\n", .{output});
```

Decode TOON into `std.json.Value`:

```zig
const std = @import("std");
const toonz = @import("toonz");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

var value = try toonz.decodeAlloc(
    allocator,
    "user.name: Bora\nuser.active: true\n",
    .{
        .expand_paths = .safe,
        .strict = true,
    },
);
defer toonz.deinitValue(allocator, &value);
```

Transcode raw JSON text to TOON:

```zig
const std = @import("std");
const toonz = @import("toonz");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

const output = try toonz.transcodeJsonToToonAlloc(
    allocator,
    "{\"name\":\"Bora\",\"active\":true}",
    .{ .trailing_newline = false },
);

std.debug.print("{s}\n", .{output});
```

Transcode TOON text to raw JSON text:

```zig
const std = @import("std");
const toonz = @import("toonz");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

const output = try toonz.transcodeToonToJsonAlloc(
    allocator,
    "user.name: Bora\nuser.active: true\n",
    .{ .expand_paths = .safe },
);

std.debug.print("{s}\n", .{output});
```

## Contributing

Contribution and commit rules live in `CONTRIBUTING.md`.

## Credit

TOON was created by [Johann Schopplich](https://johannschopplich.com/).
