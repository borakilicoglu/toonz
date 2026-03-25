const std = @import("std");
const encode_mod = @import("encode.zig");
const decode_mod = @import("decode.zig");
const value_util = @import("value.zig");

const FixtureDoc = struct {
    category: []const u8,
    tests: []const TestCase,
};

const TestCase = struct {
    name: []const u8,
    input: std.json.Value,
    expected: std.json.Value,
    shouldError: ?bool = null,
    options: ?std.json.Value = null,
};

test "official fixtures subset" {
    const allocator = std.testing.allocator;
    const fixture_root = try resolveFixtureRoot(allocator);
    defer allocator.free(fixture_root);

    if (!(try fixtureRootExists(fixture_root))) {
        std.debug.print("skipping official fixtures subset; fixture root not found: {s}\n", .{fixture_root});
        return;
    }

    try runEncodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "encode/primitives.json"),
        &.{
            "encodes safe strings without quotes",
            "quotes empty string",
            "quotes string that looks like true",
            "quotes string that looks like integer",
            "quotes string that looks like scientific notation",
            "escapes newline in string",
            "escapes tab in string",
            "escapes backslash in string",
            "quotes single hyphen as object value",
            "quotes leading-hyphen string in array",
            "encodes positive integer",
            "encodes decimal number",
            "encodes true",
            "encodes false",
            "encodes null",
        },
    );

    try runEncodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "encode/arrays-primitive.json"),
        &.{
            "encodes string arrays inline",
            "encodes number arrays inline",
            "encodes mixed primitive arrays inline",
            "encodes empty arrays",
            "encodes empty string keys for inline arrays",
            "encodes empty string in multi-item array",
            "quotes array strings with comma",
            "quotes strings that look like booleans in arrays",
        },
    );

    try runEncodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "encode/objects.json"),
        &.{
            "encodes null values in objects",
            "encodes empty objects as empty string",
            "quotes string value with colon",
            "quotes string value with comma",
            "quotes string value with newline",
            "quotes key with colon",
            "quotes key with spaces",
            "quotes empty string key",
            "encodes deeply nested objects",
            "encodes empty nested object",
        },
    );

    try runEncodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "encode/arrays-tabular.json"),
        &.{
            "encodes arrays of uniform objects in tabular format",
            "encodes null values in tabular format",
            "quotes strings containing delimiters in tabular rows",
            "quotes ambiguous strings in tabular rows",
            "encodes tabular arrays with keys needing quotes",
            "encodes tabular arrays with empty string keys",
        },
    );

    try runEncodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "encode/arrays-nested.json"),
        &.{
            "encodes nested arrays of primitives",
            "quotes strings containing delimiters in nested arrays",
            "encodes empty inner arrays",
            "encodes mixed-length inner arrays",
            "encodes root-level primitive array",
            "encodes root-level array of uniform objects in tabular format",
            "encodes root-level array of non-uniform objects in list format",
            "encodes root-level array mixing primitive, object, and array of objects in list format",
            "encodes root-level arrays of arrays",
            "encodes empty root-level array",
            "encodes complex nested structure",
            "uses list format for arrays mixing primitives and objects",
            "uses list format for arrays mixing objects and arrays",
        },
    );

    try runEncodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "encode/key-folding.json"),
        &.{
            "encodes folded chain to primitive (safe mode)",
            "encodes folded chain with inline array",
            "encodes folded chain with tabular array",
            "skips folding when segment requires quotes (safe mode)",
            "skips folding on sibling literal-key collision (safe mode)",
            "encodes partial folding with flattenDepth=2",
            "encodes full chain with flattenDepth=Infinity (default)",
            "encodes standard nesting with flattenDepth=0 (no folding)",
            "encodes standard nesting with flattenDepth=1 (no practical effect)",
            "encodes standard nesting with keyFolding=off (baseline)",
            "encodes folded chain ending with empty object",
            "stops folding at array boundary (not single-key object)",
            "encodes folded chains preserving sibling field order",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/primitives.json"),
        &.{
            "parses safe unquoted string",
            "parses empty quoted string",
            "parses quoted string with newline escape",
            "parses positive integer",
            "parses decimal number",
            "parses true",
            "parses false",
            "parses null",
            "respects ambiguity quoting for true",
            "respects ambiguity quoting for integer",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/arrays-tabular.json"),
        &.{
            "parses tabular arrays of uniform objects",
            "parses nulls and quoted values in tabular rows",
            "parses quoted colon in tabular row as data",
            "parses quoted header keys in tabular arrays",
            "parses quoted key with tabular array format",
            "parses quoted empty string key with tabular array format",
            "treats unquoted colon as terminator for tabular rows and start of key-value pair",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/delimiters.json"),
        &.{
            "parses primitive arrays with tab delimiter",
            "parses primitive arrays with pipe delimiter",
            "parses primitive arrays with comma delimiter",
            "parses tabular arrays with tab delimiter",
            "parses tabular arrays with pipe delimiter",
            "parses root-level array with tab delimiter",
            "parses root-level array with pipe delimiter",
            "parses root-level array of objects with tab delimiter",
            "parses root-level array of objects with pipe delimiter",
            "parses values containing tab delimiter when quoted",
            "parses values containing pipe delimiter when quoted",
            "does not split on commas when using tab delimiter",
            "does not split on commas when using pipe delimiter",
            "parses tabular values containing comma with comma delimiter",
            "does not require quoting commas with tab delimiter",
            "does not require quoting commas in object values",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/arrays-nested.json"),
        &.{
            "parses list arrays for non-uniform objects",
            "parses list arrays with empty items",
            "parses list arrays with deeply nested objects",
            "parses list arrays containing objects with nested properties",
            "parses list items whose first field is a tabular array",
            "parses single-field list-item object with tabular array",
            "parses objects containing arrays (including empty arrays) in list format",
            "parses arrays of arrays within objects",
            "parses nested arrays of primitives",
            "parses quoted strings and mixed lengths in nested arrays",
            "parses empty inner arrays",
            "parses mixed-length inner arrays",
            "parses root-level primitive array inline",
            "parses root-level array of uniform objects in tabular format",
            "parses root-level array of non-uniform objects in list format",
            "parses root-level array mixing primitive, object, and array of objects in list format",
            "parses root-level array of arrays",
            "parses empty root-level array",
            "parses complex mixed object with arrays and nested objects",
            "parses arrays mixing primitives, objects, and strings in list format",
            "parses arrays mixing objects and arrays",
            "parses quoted key with list array format",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/root-form.json"),
        &.{
            "parses empty document as empty object",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/validation-errors.json"),
        &.{
            "throws on array length mismatch (inline primitives - too many)",
            "throws on array length mismatch (list format - too many)",
            "throws on tabular row value count mismatch with header field count",
            "throws on tabular row count mismatch with header length",
            "throws on invalid escape sequence",
            "throws on unterminated string",
            "throws on missing colon in key-value context",
            "throws on two primitives at root depth in strict mode",
            "throws on delimiter mismatch (header declares tab, row uses comma)",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/indentation-errors.json"),
        &.{
            "throws on object field with non-multiple indentation (3 spaces with indent=2)",
            "throws on list item with non-multiple indentation (3 spaces with indent=2)",
            "throws on non-multiple indentation with custom indent=4 (3 spaces)",
            "accepts correct indentation with custom indent size (4 spaces with indent=4)",
            "throws on tab character used in indentation",
            "throws on mixed tabs and spaces in indentation",
            "throws on tab at start of line",
            "accepts tabs in quoted string values",
            "accepts tabs in quoted keys",
            "accepts tabs in quoted array elements",
            "accepts non-multiple indentation when strict=false",
            "parses empty lines without validation errors",
            "parses root-level content (0 indentation) as always valid",
            "parses lines with only spaces without validation if empty",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/blank-lines.json"),
        &.{
            "throws on blank line inside list array",
            "throws on blank line inside tabular array",
            "throws on multiple blank lines inside array",
            "throws on blank line with spaces inside array",
            "throws on blank line in nested list array",
            "accepts blank line between root-level fields",
            "accepts trailing newline at end of file",
            "accepts multiple trailing newlines",
            "accepts blank line after array ends",
            "accepts blank line between nested object fields",
            "ignores blank lines inside list array when strict=false",
            "ignores blank lines inside tabular array when strict=false",
            "ignores multiple blank lines in arrays when strict=false",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/whitespace.json"),
        &.{
            "tolerates spaces around commas in inline arrays",
            "tolerates spaces around pipes in inline arrays",
            "tolerates spaces around tabs in inline arrays",
            "tolerates leading and trailing spaces in tabular row values",
            "tolerates spaces around delimiters with quoted values",
            "parses empty tokens as empty string",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/objects.json"),
        &.{
            "parses objects with primitive values",
            "parses null values in objects",
            "parses empty nested object header",
            "parses quoted object value with colon",
            "parses quoted object value with comma",
            "parses quoted object value with newline escape",
            "parses quoted object value with escaped quotes",
            "parses quoted object value with leading/trailing spaces",
            "parses quoted object value that looks like true",
            "parses quoted key with colon",
            "parses quoted key with brackets",
            "treats extra brackets after valid array segment as literal key",
            "treats non-integer bracket content as literal key",
            "treats text between bracket segment and colon as literal key",
            "parses quoted key with spaces",
            "parses quoted empty string key",
            "parses dotted keys as identifiers",
            "unescapes tab in key",
            "parses deeply nested objects with indentation",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/numbers.json"),
        &.{
            "parses number with trailing zeros in fractional part",
            "parses negative number with positive exponent",
            "parses lowercase exponent",
            "parses uppercase exponent with negative sign",
            "parses negative zero as zero",
            "parses negative zero with fractional part",
            "parses array with mixed numeric forms",
            "treats leading zero as string not number",
            "parses very small exponent",
            "parses integer with positive exponent",
            "parses zero with exponent as number",
            "parses negative zero with exponent as number",
            "parses exponent notation",
            "parses exponent notation with uppercase E",
            "parses negative exponent notation",
            "treats unquoted leading-zero number as string",
            "treats unquoted multi-leading-zero as string",
            "treats unquoted octal-like as string",
            "treats leading-zero in object value as string",
            "treats leading-zeros in array as strings",
            "treats unquoted negative leading-zero number as string",
            "treats negative leading-zeros in array as strings",
        },
    );

    try runDecodeFixtureFile(
        allocator,
        try fixturePath(allocator, fixture_root, "decode/path-expansion.json"),
        &.{
            "expands dotted key to nested object in safe mode",
            "expands dotted key with inline array",
            "expands dotted key with tabular array",
            "preserves literal dotted keys when expansion is off",
            "expands and deep-merges preserving document-order insertion",
            "throws on expansion conflict (object vs primitive) when strict=true",
            "throws on expansion conflict (object vs array) when strict=true",
            "applies LWW when strict=false (primitive overwrites expanded object)",
            "applies LWW when strict=false (expanded object overwrites primitive)",
            "preserves quoted dotted key as literal when expandPaths=safe",
            "preserves non-IdentifierSegment keys as literals",
            "expands keys creating empty nested objects",
        },
    );
}

fn resolveFixtureRoot(allocator: std.mem.Allocator) ![]u8 {
    const env_path = std.process.getEnvVarOwned(allocator, "TOON_SPEC_ROOT") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_path) |path| return path;

    return allocator.dupe(u8, "/tmp/toon-spec/tests/fixtures");
}

fn fixtureRootExists(root: []const u8) !bool {
    std.fs.cwd().access(root, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn fixturePath(allocator: std.mem.Allocator, root: []const u8, relative: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ root, relative });
}

fn runEncodeFixtureFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    supported_names: []const []const u8,
) !void {
    defer allocator.free(path);
    var parsed = try loadFixtureFile(allocator, path);
    defer parsed.deinit();

    for (parsed.value.tests) |test_case| {
        if (!nameSupported(test_case.name, supported_names)) continue;

        const options = parseEncodeOptions(test_case.options);
        const actual = try encode_mod.encodeAlloc(allocator, test_case.input, options);
        defer allocator.free(actual);

        switch (test_case.expected) {
            .string => |expected_text| try std.testing.expectEqualStrings(expected_text, actual),
            else => return error.InvalidFixtureShape,
        }
    }
}

fn runDecodeFixtureFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    supported_names: []const []const u8,
) !void {
    defer allocator.free(path);
    var parsed = try loadFixtureFile(allocator, path);
    defer parsed.deinit();

    for (parsed.value.tests) |test_case| {
        if (!nameSupported(test_case.name, supported_names)) continue;

        const input = switch (test_case.input) {
            .string => |text| text,
            else => return error.InvalidFixtureShape,
        };

        const options = parseDecodeOptions(test_case.options);
        if (test_case.shouldError orelse false) {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            if (decode_mod.decodeAlloc(arena_allocator, input, options)) |_| {
                std.debug.print("expected decode error but succeeded: {s}\n", .{test_case.name});
                return error.ExpectedDecodeError;
            } else |_| {}
            continue;
        }

        var actual = decode_mod.decodeAlloc(allocator, input, options) catch |err| {
            std.debug.print("unexpected decode error for fixture: {s} ({s})\n", .{ test_case.name, @errorName(err) });
            return err;
        };
        defer value_util.deinitValue(allocator, &actual);

        try expectJsonEqual(test_case.expected, actual);
    }
}

fn loadFixtureFile(
    allocator: std.mem.Allocator,
    path: []const u8,
) !std.json.Parsed(FixtureDoc) {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(data);

    return std.json.parseFromSlice(FixtureDoc, allocator, data, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

fn parseEncodeOptions(options_value: ?std.json.Value) encode_mod.EncodeOptions {
    var options = encode_mod.EncodeOptions{ .trailing_newline = false };
    const value = options_value orelse return options;
    if (value != .object) return options;

    if (value.object.get("delimiter")) |delimiter_value| {
        if (delimiter_value == .string and delimiter_value.string.len != 0) {
            options.delimiter = delimiter_value.string[0];
        }
    }
    if (value.object.get("indent")) |indent_value| {
        if (indent_value == .integer and indent_value.integer > 0) {
            options.indent_width = @intCast(indent_value.integer);
        }
    }
    if (value.object.get("keyFolding")) |fold_value| {
        if (fold_value == .string) {
            if (std.mem.eql(u8, fold_value.string, "safe")) options.key_folding = .safe;
            if (std.mem.eql(u8, fold_value.string, "off")) options.key_folding = .off;
        }
    }
    if (value.object.get("flattenDepth")) |depth_value| {
        if (depth_value == .integer and depth_value.integer >= 0) {
            options.flatten_depth = @intCast(depth_value.integer);
        }
    }
    return options;
}

fn parseDecodeOptions(options_value: ?std.json.Value) decode_mod.DecodeOptions {
    var options = decode_mod.DecodeOptions{};
    const value = options_value orelse return options;
    if (value != .object) return options;

    if (value.object.get("strict")) |strict_value| {
        if (strict_value == .bool) options.strict = strict_value.bool;
    }
    if (value.object.get("indent")) |indent_value| {
        if (indent_value == .integer and indent_value.integer > 0) {
            options.indent_width = @intCast(indent_value.integer);
        }
    }
    if (value.object.get("expandPaths")) |expand_value| {
        if (expand_value == .string) {
            if (std.mem.eql(u8, expand_value.string, "safe")) options.expand_paths = .safe;
            if (std.mem.eql(u8, expand_value.string, "off")) options.expand_paths = .off;
        }
    }
    return options;
}

fn nameSupported(name: []const u8, supported_names: []const []const u8) bool {
    for (supported_names) |supported| {
        if (std.mem.eql(u8, name, supported)) return true;
    }
    return false;
}

fn expectJsonEqual(expected: std.json.Value, actual: std.json.Value) !void {
    switch (expected) {
        .null => try std.testing.expect(actual == .null),
        .bool => |value| {
            try std.testing.expect(actual == .bool);
            try std.testing.expectEqual(value, actual.bool);
        },
        .integer => |value| {
            try std.testing.expect(actual == .integer);
            try std.testing.expectEqual(value, actual.integer);
        },
        .float => |value| {
            try std.testing.expect(actual == .float);
            try std.testing.expectEqual(value, actual.float);
        },
        .number_string => |value| {
            try std.testing.expect(actual == .number_string);
            try std.testing.expectEqualStrings(value, actual.number_string);
        },
        .string => |value| {
            try std.testing.expect(actual == .string);
            try std.testing.expectEqualStrings(value, actual.string);
        },
        .array => |expected_array| {
            try std.testing.expect(actual == .array);
            try std.testing.expectEqual(expected_array.items.len, actual.array.items.len);
            for (expected_array.items, actual.array.items) |expected_item, actual_item| {
                try expectJsonEqual(expected_item, actual_item);
            }
        },
        .object => |expected_object| {
            try std.testing.expect(actual == .object);
            try std.testing.expectEqual(expected_object.count(), actual.object.count());

            var it = expected_object.iterator();
            while (it.next()) |entry| {
                const actual_value = actual.object.get(entry.key_ptr.*) orelse return error.MissingObjectKey;
                try expectJsonEqual(entry.value_ptr.*, actual_value);
            }
        },
    }
}
