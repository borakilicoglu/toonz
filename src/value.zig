const std = @import("std");

pub fn deinitValue(allocator: std.mem.Allocator, value: *std.json.Value) void {
    switch (value.*) {
        .string => |slice| allocator.free(slice),
        .array => |*array| {
            for (array.items) |*item| {
                deinitValue(allocator, item);
            }
            array.deinit();
        },
        .object => |*object| {
            var it = object.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                deinitValue(allocator, entry.value_ptr);
            }
            object.deinit();
        },
        else => {},
    }
}
