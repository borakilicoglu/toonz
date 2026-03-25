const std = @import("std");

pub const Line = struct {
    indent: usize,
    text: []const u8,
    is_blank: bool,
    has_tab_in_indent: bool,
};

pub fn scanLines(
    allocator: std.mem.Allocator,
    input: []const u8,
) !std.array_list.Managed(Line) {
    var lines = std.array_list.Managed(Line).init(allocator);
    errdefer lines.deinit();

    var cursor: usize = 0;
    while (cursor < input.len) {
        const start = cursor;
        const end = std.mem.indexOfScalarPos(u8, input, start, '\n') orelse input.len;
        cursor = if (end < input.len) end + 1 else input.len;

        var raw = input[start..end];
        raw = std.mem.trimRight(u8, raw, "\r");

        var indent: usize = 0;
        var has_tab_in_indent = false;
        while (indent < raw.len) : (indent += 1) {
            switch (raw[indent]) {
                ' ' => {},
                '\t' => has_tab_in_indent = true,
                else => break,
            }
        }

        const text = raw[indent..];
        const is_blank = std.mem.trim(u8, raw, " \t").len == 0;

        try lines.append(.{
            .indent = indent,
            .text = text,
            .is_blank = is_blank,
            .has_tab_in_indent = has_tab_in_indent,
        });
    }

    if (input.len == 0) return lines;

    if (input[input.len - 1] == '\n') {
        try lines.append(.{
            .indent = 0,
            .text = "",
            .is_blank = true,
            .has_tab_in_indent = false,
        });
    }

    return lines;
}

test "scanLines preserves blanks and indent metadata" {
    const allocator = std.testing.allocator;
    var lines = try scanLines(allocator,
        \\a
        \\
        \\  b
        \\
    );
    defer lines.deinit();

    try std.testing.expectEqual(@as(usize, 4), lines.items.len);
    try std.testing.expect(!lines.items[0].is_blank);
    try std.testing.expect(lines.items[1].is_blank);
    try std.testing.expectEqual(@as(usize, 2), lines.items[2].indent);
    try std.testing.expect(lines.items[3].is_blank);
}
