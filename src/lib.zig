const std = @import("std");

pub const ToonError = @import("errors.zig").ToonError;
pub const EncodeOptions = @import("encode.zig").EncodeOptions;
pub const DecodeOptions = @import("decode.zig").DecodeOptions;
pub const deinitValue = @import("value.zig").deinitValue;

pub const encode = @import("encode.zig").encode;
pub const encodeAlloc = @import("encode.zig").encodeAlloc;
pub const decodeAlloc = @import("decode.zig").decodeAlloc;

pub fn transcodeJsonToToonAlloc(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: EncodeOptions,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return encodeAlloc(allocator, parsed.value, options);
}

pub fn transcodeToonToJsonAlloc(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecodeOptions,
) ![]u8 {
    var value = try decodeAlloc(allocator, input, options);
    defer deinitValue(allocator, &value);

    var output: std.io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try std.json.Stringify.value(value, .{}, &output.writer);
    return output.toOwnedSlice();
}

pub fn decodeFromSlice(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecodeOptions,
) !std.json.Value {
    return decodeAlloc(allocator, input, options);
}

test "transcodes raw json text to toon" {
    const allocator = std.testing.allocator;

    const output = try transcodeJsonToToonAlloc(
        allocator,
        "{\"name\":\"Bora\",\"active\":true}",
        .{ .trailing_newline = false },
    );
    defer allocator.free(output);

    try std.testing.expectEqualStrings("name: Bora\nactive: true", output);
}

test "transcodes toon text to raw json text" {
    const allocator = std.testing.allocator;

    const output = try transcodeToonToJsonAlloc(
        allocator,
        "user.name: Bora\nuser.active: true\n",
        .{ .expand_paths = .safe },
    );
    defer allocator.free(output);

    try std.testing.expectEqualStrings("{\"user\":{\"name\":\"Bora\",\"active\":true}}", output);
}

test {
    _ = @import("tokenizer.zig");
    _ = @import("encode.zig");
    _ = @import("decode.zig");
    _ = @import("value.zig");
    _ = @import("fixtures.zig");
}
