const std = @import("std");
const ToonError = @import("errors.zig").ToonError;
const value_util = @import("value.zig");

pub const EncodeOptions = struct {
    indent_width: usize = 2,
    delimiter: u8 = ',',
    trailing_newline: bool = true,
    key_folding: enum { off, safe } = .off,
    flatten_depth: usize = std.math.maxInt(usize),
};

pub fn encodeAlloc(
    allocator: std.mem.Allocator,
    value: std.json.Value,
    options: EncodeOptions,
) ![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();

    try encode(output.writer(), value, options);
    return output.toOwnedSlice();
}

pub fn encode(
    writer: anytype,
    value: std.json.Value,
    options: EncodeOptions,
) !void {
    var encoder = Encoder(@TypeOf(writer)){ .writer = writer, .options = options };
    try encoder.writeValue(value, 0);
    if (options.trailing_newline) try writer.writeByte('\n');
}

fn Encoder(comptime Writer: type) type {
    return struct {
        writer: Writer,
        options: EncodeOptions,

        fn writeValue(self: *@This(), value: std.json.Value, level: usize) anyerror!void {
            switch (value) {
                .null, .bool, .integer, .float, .number_string, .string => {
                    try self.writeIndent(level);
                    try self.writeScalar(value, self.options.delimiter);
                },
                .array => |items| try self.writeArray(null, items.items, level, false),
                .object => |obj| try self.writeObject(obj, level, null, null),
            }
        }

        fn writeIndent(self: *@This(), level: usize) !void {
            try self.writer.writeByteNTimes(' ', level * self.options.indent_width);
        }

        fn writeObject(
            self: *@This(),
            obj: std.json.ObjectMap,
            level: usize,
            ancestor_prefix: ?[]const u8,
            ancestor_siblings: ?std.json.ObjectMap,
        ) anyerror!void {
            var it = obj.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try self.writer.writeByte('\n');
                first = false;
                try self.writePossiblyFoldedEntry(obj, entry.key_ptr.*, entry.value_ptr.*, level, ancestor_prefix, ancestor_siblings);
            }
        }

        fn writeObjectUnfolded(self: *@This(), obj: std.json.ObjectMap, level: usize) anyerror!void {
            var it = obj.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try self.writer.writeByte('\n');
                first = false;
                try self.writeEntryForKeyValue(entry.key_ptr.*, entry.value_ptr.*, level, false, obj, null, null);
            }
        }

        fn writeArray(
            self: *@This(),
            key: ?[]const u8,
            items: []const std.json.Value,
            level: usize,
            inline_after_dash: bool,
        ) anyerror!void {
            const child_level_increment: usize = if (inline_after_dash and key != null) 2 else 1;
            if (!inline_after_dash) {
                try self.writeIndent(level);
            }
            if (key) |k| try self.writeKey(k);

            if (isUniformScalarObjectArray(items)) {
                try self.writeTabularArray(items, level, child_level_increment);
                return;
            }

            if (allScalars(items)) {
                try self.writeInlineArrayHeader(items.len, null);
                if (items.len != 0) {
                    try self.writer.writeByte(' ');
                    try self.writeInlineScalarArray(items, self.options.delimiter);
                }
                return;
            }

            try self.writeInlineArrayHeader(items.len, null);
            if (items.len == 0) return;

            if (inline_after_dash) {
                try self.writer.writeByte('\n');
            } else {
                try self.writer.writeByte('\n');
            }

            for (items, 0..) |item, index| {
                if (index != 0) try self.writer.writeByte('\n');
                try self.writeListItem(item, level + child_level_increment);
            }
        }

        fn writeListItem(self: *@This(), item: std.json.Value, level: usize) anyerror!void {
            switch (item) {
                .null, .bool, .integer, .float, .number_string, .string => {
                    try self.writeIndent(level);
                    try self.writer.writeAll("- ");
                    try self.writeScalar(item, self.options.delimiter);
                },
                .array => |items| {
                    try self.writeIndent(level);
                    try self.writer.writeAll("- ");
                    try self.writeArray(null, items.items, level, true);
                },
                .object => |obj| try self.writeListItemObject(obj, level),
            }
        }

        fn writeListItemObject(self: *@This(), obj: std.json.ObjectMap, level: usize) anyerror!void {
            if (obj.count() == 0) {
                try self.writeIndent(level);
                try self.writer.writeAll("-");
                return;
            }

            var it = obj.iterator();
            const first = it.next() orelse unreachable;

            try self.writeIndent(level);
            try self.writer.writeAll("- ");
            try self.writeObjectEntryInline(obj, first.key_ptr.*, first.value_ptr.*, level);

            while (it.next()) |entry| {
                try self.writer.writeByte('\n');
                try self.writeObjectEntryIndented(obj, entry.key_ptr.*, entry.value_ptr.*, level + 1);
            }
        }

        fn writeObjectEntryInline(
            self: *@This(),
            siblings: std.json.ObjectMap,
            key: []const u8,
            value: std.json.Value,
            level: usize,
        ) anyerror!void {
            if (self.options.key_folding == .safe and self.options.flatten_depth >= 2) {
                if (try self.foldAnalysis(siblings, key, value, null, null)) |folded| {
                    defer folded.segments.deinit();
                    try self.writeJoinedSegments(folded.segments.items);
                    try self.writeFoldedTail(folded.remainder, level);
                    return;
                }
            }

            try self.writeEntryForKeyValue(key, value, level, true, siblings, null, null);
        }

        fn writeObjectEntryIndented(
            self: *@This(),
            siblings: std.json.ObjectMap,
            key: []const u8,
            value: std.json.Value,
            level: usize,
        ) anyerror!void {
            if (self.options.key_folding == .safe and self.options.flatten_depth >= 2) {
                if (try self.foldAnalysis(siblings, key, value, null, null)) |folded| {
                    defer folded.segments.deinit();
                    try self.writeIndent(level);
                    try self.writeJoinedSegments(folded.segments.items);
                    try self.writeFoldedTail(folded.remainder, level);
                    return;
                }
            }

            try self.writeEntryForKeyValue(key, value, level, false, siblings, null, null);
        }

        fn writePossiblyFoldedEntry(
            self: *@This(),
            siblings: std.json.ObjectMap,
            key: []const u8,
            value: std.json.Value,
            level: usize,
            ancestor_prefix: ?[]const u8,
            ancestor_siblings: ?std.json.ObjectMap,
        ) anyerror!void {
            if (self.options.key_folding == .safe and self.options.flatten_depth >= 2) {
                if (try self.foldAnalysis(siblings, key, value, ancestor_prefix, ancestor_siblings)) |folded| {
                    defer folded.segments.deinit();
                    try self.writeIndent(level);
                    try self.writeJoinedSegments(folded.segments.items);
                    try self.writeFoldedTail(folded.remainder, level);
                    return;
                }
            }

            try self.writeEntryForKeyValue(key, value, level, false, siblings, ancestor_prefix, ancestor_siblings);
        }

        fn writeEntryForKeyValue(
            self: *@This(),
            key: []const u8,
            value: std.json.Value,
            level: usize,
            inline_prefix: bool,
            current_siblings: std.json.ObjectMap,
            ancestor_prefix: ?[]const u8,
            ancestor_siblings: ?std.json.ObjectMap,
        ) anyerror!void {
            _ = ancestor_siblings;
            switch (value) {
                .null, .bool, .integer, .float, .number_string, .string => {
                    if (!inline_prefix) try self.writeIndent(level);
                    try self.writeKey(key);
                    try self.writer.writeAll(": ");
                    try self.writeScalar(value, self.options.delimiter);
                },
                .array => |items| try self.writeArray(key, items.items, level, inline_prefix),
                .object => |child| {
                    if (!inline_prefix) try self.writeIndent(level);
                    try self.writeKey(key);
                    if (child.count() == 0) {
                        try self.writer.writeAll(":");
                    } else {
                        try self.writer.writeAll(":\n");
                        const child_level: usize = level + (if (inline_prefix) @as(usize, 2) else @as(usize, 1));
                        const next_prefix = if (isIdentifierSegment(key))
                            try buildPrefix(ancestor_prefix, key)
                        else
                            null;
                        defer if (next_prefix) |prefix| std.heap.page_allocator.free(prefix);
                        try self.writeObject(
                            child,
                            child_level,
                            next_prefix,
                            if (isIdentifierSegment(key)) current_siblings else null,
                        );
                    }
                },
            }
        }

        fn writeTabularArray(
            self: *@This(),
            items: []const std.json.Value,
            level: usize,
            row_level_increment: usize,
        ) !void {
            const first_obj = items[0].object;
            try self.writeInlineArrayHeader(items.len, first_obj);
            try self.writer.writeByte('\n');

            for (items, 0..) |item, row_index| {
                if (row_index != 0) try self.writer.writeByte('\n');
                try self.writeIndent(level + row_level_increment);

                var field_it = first_obj.iterator();
                var first = true;
                while (field_it.next()) |field| {
                    if (!first) try self.writer.writeByte(self.options.delimiter);
                    first = false;

                    const row_value = item.object.get(field.key_ptr.*) orelse return ToonError.InvalidSyntax;
                    try self.writeScalar(row_value, self.options.delimiter);
                }
            }
        }

        fn writeInlineArrayHeader(
            self: *@This(),
            len: usize,
            fields_obj: ?std.json.ObjectMap,
        ) !void {
            try self.writer.writeByte('[');
            try self.writer.print("{d}", .{len});
            if (self.options.delimiter != ',') try self.writer.writeByte(self.options.delimiter);
            try self.writer.writeByte(']');

            if (fields_obj) |obj| {
                try self.writer.writeByte('{');
                var it = obj.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) try self.writer.writeByte(self.options.delimiter);
                    first = false;
                    try self.writeKey(entry.key_ptr.*);
                }
                try self.writer.writeAll("}:");
            } else {
                try self.writer.writeAll(":");
            }
        }

        fn writeInlineScalarArray(
            self: *@This(),
            values: []const std.json.Value,
            delimiter: u8,
        ) !void {
            for (values, 0..) |item, index| {
                if (index != 0) try self.writer.writeByte(delimiter);
                try self.writeScalar(item, delimiter);
            }
        }

        fn writeScalar(self: *@This(), value: std.json.Value, delimiter: u8) !void {
            switch (value) {
                .null => try self.writer.writeAll("null"),
                .bool => |v| try self.writer.writeAll(if (v) "true" else "false"),
                .integer => |v| try self.writeCanonicalInteger(v),
                .float => |v| try self.writeCanonicalFloat(v),
                .number_string => |v| try self.writeCanonicalNumberString(v),
                .string => |v| try self.writeStringToken(v, delimiter, false),
                else => return ToonError.UnsupportedFeature,
            }
        }

        fn writeCanonicalInteger(self: *@This(), value: i64) !void {
            try self.writer.print("{d}", .{value});
        }

        fn writeCanonicalFloat(self: *@This(), value: f64) !void {
            if (value == 0) {
                try self.writer.writeAll("0");
                return;
            }

            const truncated = @trunc(value);
            const min_i64_f: f64 = @floatFromInt(std.math.minInt(i64));
            const max_i64_f: f64 = @floatFromInt(std.math.maxInt(i64));
            if (truncated == value and truncated >= min_i64_f and truncated <= max_i64_f) {
                try self.writer.print("{d}", .{@as(i64, @intFromFloat(truncated))});
                return;
            }

            try self.writer.print("{d}", .{value});
        }

        fn writeCanonicalNumberString(self: *@This(), raw: []const u8) !void {
            if (std.fmt.parseFloat(f64, raw)) |value| {
                try self.writeCanonicalFloat(value);
                return;
            } else |_| {
                try self.writer.writeAll(raw);
            }
        }

        fn writeKey(self: *@This(), key: []const u8) !void {
            try self.writeStringToken(key, self.options.delimiter, true);
        }

        fn writeStringToken(
            self: *@This(),
            value: []const u8,
            delimiter: u8,
            is_key: bool,
        ) !void {
            if (requiresQuotes(value, delimiter, is_key)) {
                try writeQuotedString(self.writer, value);
                return;
            }
            try self.writer.writeAll(value);
        }

        fn writeJoinedSegments(self: *@This(), segments: []const []const u8) anyerror!void {
            for (segments, 0..) |segment, index| {
                if (index != 0) try self.writer.writeByte('.');
                try self.writer.writeAll(segment);
            }
        }

        fn writeFoldedTail(self: *@This(), value: std.json.Value, level: usize) anyerror!void {
            switch (value) {
                .null, .bool, .integer, .float, .number_string, .string => {
                    try self.writer.writeAll(": ");
                    try self.writeScalar(value, self.options.delimiter);
                },
                .array => |items| try self.writeArray(null, items.items, level, true),
                .object => |obj| {
                    if (obj.count() == 0) {
                        try self.writer.writeAll(":");
                    } else {
                        try self.writer.writeAll(":\n");
                        try self.writeObjectUnfolded(obj, level + 1);
                    }
                },
            }
        }

        fn foldAnalysis(
            self: *@This(),
            siblings: std.json.ObjectMap,
            key: []const u8,
            value: std.json.Value,
            ancestor_prefix: ?[]const u8,
            ancestor_siblings: ?std.json.ObjectMap,
        ) !?FoldedEntry {
            if (!isIdentifierSegment(key)) return null;

            var segments = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
            errdefer segments.deinit();
            try segments.append(key);

            var remainder = value;
            while (segments.items.len < self.options.flatten_depth) {
                if (remainder != .object) break;
                if (remainder.object.count() != 1) break;

                var it = remainder.object.iterator();
                const next = it.next() orelse break;
                if (!isIdentifierSegment(next.key_ptr.*)) break;

                try segments.append(next.key_ptr.*);
                remainder = next.value_ptr.*;
                if (remainder != .object) break;
            }

            if (segments.items.len < 2) {
                segments.deinit();
                return null;
            }

            const candidate = try std.mem.join(std.heap.page_allocator, ".", segments.items);
            defer std.heap.page_allocator.free(candidate);
            if (siblings.get(candidate) != null) {
                segments.deinit();
                return null;
            }

            if (ancestor_prefix) |prefix| {
                if (ancestor_siblings) |outer| {
                    const combined = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.{s}", .{ prefix, candidate });
                    defer std.heap.page_allocator.free(combined);
                    if (outer.get(combined) != null) {
                        segments.deinit();
                        return null;
                    }
                }
            }

            return .{
                .segments = segments,
                .remainder = remainder,
            };
        }
    };
}

const FoldedEntry = struct {
    segments: std.array_list.Managed([]const u8),
    remainder: std.json.Value,
};

fn buildPrefix(prefix: ?[]const u8, key: []const u8) ![]u8 {
    if (prefix) |p| {
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}.{s}", .{ p, key });
    }
    return std.heap.page_allocator.dupe(u8, key);
}

fn isUniformScalarObjectArray(items: []const std.json.Value) bool {
    if (items.len == 0 or items[0] != .object) return false;

    const first = items[0].object;
    var first_it = first.iterator();
    while (first_it.next()) |entry| {
        if (!isScalar(entry.value_ptr.*)) return false;
    }

    for (items[1..]) |item| {
        if (item != .object) return false;
        if (item.object.count() != first.count()) return false;

        var field_it = first.iterator();
        while (field_it.next()) |field| {
            const row_value = item.object.get(field.key_ptr.*) orelse return false;
            if (!isScalar(row_value)) return false;
        }
    }

    return true;
}

fn allScalars(values: []const std.json.Value) bool {
    for (values) |value| {
        if (!isScalar(value)) return false;
    }
    return true;
}

fn isScalar(value: std.json.Value) bool {
    return switch (value) {
        .null, .bool, .integer, .float, .number_string, .string => true,
        else => false,
    };
}

fn isIdentifierSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;
    if (!(std.ascii.isAlphabetic(segment[0]) or segment[0] == '_')) return false;
    for (segment[1..]) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    }
    return true;
}

fn requiresQuotes(value: []const u8, delimiter: u8, is_key: bool) bool {
    if (value.len == 0) return true;
    if (is_key and !isPermissiveKey(value)) return true;
    if (std.mem.eql(u8, value, "null")) return true;
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return true;
    if (looksNumeric(value)) return true;
    if (std.ascii.isWhitespace(value[0]) or std.ascii.isWhitespace(value[value.len - 1])) return true;

    for (value) |ch| {
        switch (ch) {
            '"', '\\', '\n', '\r' => return true,
            '\t' => return true,
            ':', '[', ']', '{', '}' => return true,
            else => {},
        }

        if (ch == delimiter) return true;
        if (is_key and ch == ' ') return true;
    }

    if (value[0] == '-' and (value.len == 1 or value[1] == ' ')) return true;
    if (is_key and value[0] == '-') return true;
    return false;
}

fn isPermissiveKey(value: []const u8) bool {
    if (value.len == 0) return false;
    if (!(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value[1..]) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '.')) return false;
    }
    return true;
}

fn looksNumeric(value: []const u8) bool {
    if (std.fmt.parseInt(i64, value, 10)) |_| {
        return true;
    } else |_| {}

    if (std.fmt.parseFloat(f64, value)) |_| {
        return true;
    } else |_| {}

    return false;
}

fn writeQuotedString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
}

test "encode flat object with primitive array uses unquoted safe strings" {
    const allocator = std.testing.allocator;

    var object = std.json.ObjectMap.init(allocator);

    try object.put(try allocator.dupe(u8, "name"), .{ .string = try allocator.dupe(u8, "Ada") });

    var tags = std.json.Array.init(allocator);
    try tags.append(.{ .string = try allocator.dupe(u8, "math") });
    try tags.append(.{ .string = try allocator.dupe(u8, "logic") });
    try object.put(try allocator.dupe(u8, "tags"), .{ .array = tags });

    var value: std.json.Value = .{ .object = object };
    defer value_util.deinitValue(allocator, &value);
    const text = try encodeAlloc(allocator, value, .{ .trailing_newline = false });
    defer allocator.free(text);

    try std.testing.expectEqualStrings("name: Ada\ntags[2]: math,logic", text);
}

test "encode tabular array with quoted ambiguous values" {
    const allocator = std.testing.allocator;

    var root = std.json.ObjectMap.init(allocator);

    var rows = std.json.Array.init(allocator);

    var row1 = std.json.ObjectMap.init(allocator);
    try row1.put(try allocator.dupe(u8, "id"), .{ .integer = 1 });
    try row1.put(try allocator.dupe(u8, "status"), .{ .string = try allocator.dupe(u8, "true") });
    try rows.append(.{ .object = row1 });

    var row2 = std.json.ObjectMap.init(allocator);
    try row2.put(try allocator.dupe(u8, "id"), .{ .integer = 2 });
    try row2.put(try allocator.dupe(u8, "status"), .{ .string = try allocator.dupe(u8, "false") });
    try rows.append(.{ .object = row2 });

    try root.put(try allocator.dupe(u8, "items"), .{ .array = rows });

    var value: std.json.Value = .{ .object = root };
    defer value_util.deinitValue(allocator, &value);
    const text = try encodeAlloc(allocator, value, .{ .trailing_newline = false });
    defer allocator.free(text);

    try std.testing.expectEqualStrings(
        "items[2]{id,status}:\n  1,\"true\"\n  2,\"false\"",
        text,
    );
}

test "encode root mixed array in list format" {
    const allocator = std.testing.allocator;

    var root = std.json.Array.init(allocator);

    try root.append(.{ .string = try allocator.dupe(u8, "summary") });

    var obj = std.json.ObjectMap.init(allocator);
    try obj.put(try allocator.dupe(u8, "id"), .{ .integer = 1 });
    try obj.put(try allocator.dupe(u8, "name"), .{ .string = try allocator.dupe(u8, "Ada") });
    try root.append(.{ .object = obj });

    var nested = std.json.Array.init(allocator);
    var row1 = std.json.ObjectMap.init(allocator);
    try row1.put(try allocator.dupe(u8, "id"), .{ .integer = 2 });
    try nested.append(.{ .object = row1 });
    var row2 = std.json.ObjectMap.init(allocator);
    try row2.put(try allocator.dupe(u8, "status"), .{ .string = try allocator.dupe(u8, "draft") });
    try nested.append(.{ .object = row2 });
    try root.append(.{ .array = nested });

    var value: std.json.Value = .{ .array = root };
    defer value_util.deinitValue(allocator, &value);
    const text = try encodeAlloc(allocator, value, .{ .trailing_newline = false });
    defer allocator.free(text);

    try std.testing.expectEqualStrings(
        "[3]:\n  - summary\n  - id: 1\n    name: Ada\n  - [2]:\n    - id: 2\n    - status: draft",
        text,
    );
}
