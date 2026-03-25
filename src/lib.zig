const std = @import("std");

pub const ToonError = @import("errors.zig").ToonError;
pub const EncodeOptions = @import("encode.zig").EncodeOptions;
pub const DecodeOptions = @import("decode.zig").DecodeOptions;
pub const deinitValue = @import("value.zig").deinitValue;

pub const encode = @import("encode.zig").encode;
pub const encodeAlloc = @import("encode.zig").encodeAlloc;
pub const decodeAlloc = @import("decode.zig").decodeAlloc;

pub fn decodeFromSlice(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecodeOptions,
) !std.json.Value {
    return decodeAlloc(allocator, input, options);
}

test {
    _ = @import("tokenizer.zig");
    _ = @import("encode.zig");
    _ = @import("decode.zig");
    _ = @import("value.zig");
    _ = @import("fixtures.zig");
}
