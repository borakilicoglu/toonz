const std = @import("std");
const ToonError = @import("errors.zig").ToonError;
const tokenizer = @import("tokenizer.zig");
const value_util = @import("value.zig");

pub const DecodeOptions = struct {
    strict: bool = false,
    indent_width: usize = 2,
    expand_paths: enum { off, safe } = .off,
    allocator_strategy: enum { arena, caller } = .caller,
};

pub fn decodeAlloc(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecodeOptions,
) !std.json.Value {
    var lines = try tokenizer.scanLines(allocator, input);
    defer lines.deinit();

    var parser = Parser{
        .allocator = allocator,
        .lines = lines.items,
        .index = 0,
        .options = options,
    };

    return parser.parseRoot();
}

const ArrayHeader = struct {
    key: ?[]const u8,
    key_was_quoted: bool,
    len: usize,
    delimiter: u8,
    fields: ?std.array_list.Managed([]const u8),

    fn deinit(self: *ArrayHeader) void {
        if (self.fields) |*fields| fields.deinit();
    }
};

const Parser = struct {
    allocator: std.mem.Allocator,
    lines: []const tokenizer.Line,
    index: usize,
    options: DecodeOptions,

    fn parseRoot(self: *Parser) anyerror!std.json.Value {
        self.skipBlankLinesRoot();
        if (self.index >= self.lines.len) {
            return .{ .object = std.json.ObjectMap.init(self.allocator) };
        }
        try self.validateLine(self.lines[self.index]);
        if (self.lines[self.index].indent != 0) return ToonError.InvalidIndentation;

        if (self.singleNonBlankLineRemaining()) |line| {
            if (findTopLevelColon(line.text) == null and line.text.len != 0 and line.text[0] != '[') {
                self.index = self.lines.len;
                return parseScalar(self.allocator, line.text);
            }
        }

        if (try self.tryParseStandaloneArray(0)) |value| {
            self.skipBlankLinesRoot();
            if (self.index != self.lines.len) return ToonError.TrailingData;
            return value;
        }

        const value = try self.parseObject(0, false, null);
        self.skipBlankLinesRoot();
        if (self.index != self.lines.len) return ToonError.TrailingData;
        return value;
    }

    fn tryParseStandaloneArray(self: *Parser, indent: usize) anyerror!?std.json.Value {
        self.skipBlankLinesRoot();
        if (self.index >= self.lines.len) return null;
        const line = self.lines[self.index];
        if (line.is_blank) return null;
        try self.validateLine(line);
        if (line.indent != indent) return null;

        const colon = findTopLevelColon(line.text) orelse return null;
        const lhs = std.mem.trim(u8, line.text[0..colon], " ");
        if (lhs.len == 0 or lhs[0] != '[') return null;

        var header = (try maybeParseArrayHeader(self.allocator, lhs)) orelse return null;
        defer header.deinit();
        if (header.key != null) return ToonError.InvalidSyntax;

        const rhs = std.mem.trim(u8, line.text[colon + 1 ..], " ");
        self.index += 1;

        return .{ .array = try self.parseArrayBody(indent, &header, rhs) };
    }

    fn parseObject(
        self: *Parser,
        indent: usize,
        stop_at_list_item: bool,
        first_entry_text: ?[]const u8,
    ) anyerror!std.json.Value {
        var object = std.json.ObjectMap.init(self.allocator);
        errdefer object.deinit();

        if (first_entry_text) |text| {
            try self.parseObjectEntryText(&object, indent, indent, text, stop_at_list_item);
        }

        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.is_blank) {
                self.index += 1;
                continue;
            }
            try self.validateLine(line);
            if (line.indent < indent) break;
            if (line.indent != indent) return ToonError.InvalidIndentation;
            if (stop_at_list_item and std.mem.startsWith(u8, line.text, "-")) break;
            try self.parseObjectEntry(&object, indent, stop_at_list_item);
        }

        return .{ .object = object };
    }

    fn parseObjectEntry(
        self: *Parser,
        object: *std.json.ObjectMap,
        indent: usize,
        stop_at_list_item: bool,
    ) anyerror!void {
        const line = self.lines[self.index];
        self.index += 1;
        try self.parseObjectEntryText(object, indent, indent, line.text, stop_at_list_item);
    }

    fn parseObjectEntryText(
        self: *Parser,
        object: *std.json.ObjectMap,
        indent: usize,
        nested_parent_indent: usize,
        text: []const u8,
        stop_at_list_item: bool,
    ) anyerror!void {
        const colon = findTopLevelColon(text) orelse return ToonError.InvalidSyntax;
        const lhs = std.mem.trim(u8, text[0..colon], " ");
        const rhs = std.mem.trim(u8, text[colon + 1 ..], " ");

        if (try maybeParseArrayHeader(self.allocator, lhs)) |header_value| {
            var header = header_value;
            defer header.deinit();
            const key_raw = header.key orelse return ToonError.InvalidSyntax;
            const key_info = try parseKeyInfo(self.allocator, key_raw);
            errdefer self.allocator.free(key_info.value);
            var array_value: std.json.Value = .{ .array = try self.parseArrayBody(nested_parent_indent, &header, rhs) };
            errdefer value_util.deinitValue(self.allocator, &array_value);
            try self.insertObjectValue(object, key_info.value, header.key_was_quoted, array_value);
            return;
        }

        const key_info = try parseKeyInfo(self.allocator, lhs);
        errdefer self.allocator.free(key_info.value);

        if (rhs.len != 0) {
            var scalar_value = try parseScalar(self.allocator, rhs);
            errdefer value_util.deinitValue(self.allocator, &scalar_value);
            try self.insertObjectValue(object, key_info.value, key_info.was_quoted, scalar_value);
            return;
        }

        if (self.index >= self.lines.len) {
            var empty_object: std.json.Value = .{ .object = std.json.ObjectMap.init(self.allocator) };
            errdefer value_util.deinitValue(self.allocator, &empty_object);
            try self.insertObjectValue(object, key_info.value, key_info.was_quoted, empty_object);
            return;
        }
        self.skipBlankLinesRoot();
        if (self.index >= self.lines.len) {
            var empty_object: std.json.Value = .{ .object = std.json.ObjectMap.init(self.allocator) };
            errdefer value_util.deinitValue(self.allocator, &empty_object);
            try self.insertObjectValue(object, key_info.value, key_info.was_quoted, empty_object);
            return;
        }
        if (self.lines[self.index].indent <= indent) {
            var empty_object: std.json.Value = .{ .object = std.json.ObjectMap.init(self.allocator) };
            errdefer value_util.deinitValue(self.allocator, &empty_object);
            try self.insertObjectValue(object, key_info.value, key_info.was_quoted, empty_object);
            return;
        }
        const child_indent = if (self.options.strict)
            nested_parent_indent + self.options.indent_width
        else
            self.lines[self.index].indent;
        if (self.lines[self.index].indent != child_indent) return ToonError.InvalidIndentation;

        var child = try self.parseObject(child_indent, stop_at_list_item, null);
        errdefer value_util.deinitValue(self.allocator, &child);
        try self.insertObjectValue(object, key_info.value, key_info.was_quoted, child);
    }

    fn parseArrayBody(
        self: *Parser,
        parent_indent: usize,
        header: *const ArrayHeader,
        rhs: []const u8,
    ) anyerror!std.json.Array {
        if (header.fields) |fields| {
            return self.parseTabularRows(parent_indent, header.len, header.delimiter, fields.items);
        }

        if (rhs.len != 0) {
            return self.parseInlineArrayPayload(rhs, header.len, header.delimiter);
        }

        if (header.len == 0) {
            return std.json.Array.init(self.allocator);
        }

        return self.parseListArray(parent_indent, header.len);
    }

    fn parseListArray(self: *Parser, parent_indent: usize, expected_len: usize) anyerror!std.json.Array {
        var list = std.json.Array.init(self.allocator);
        errdefer list.deinit();

        const item_indent = parent_indent + self.options.indent_width;
        var count: usize = 0;

        while (self.index < self.lines.len and count < expected_len) : (count += 1) {
            try self.skipBlankLinesInArray();
            if (self.index >= self.lines.len) break;
            const line = self.lines[self.index];
            try self.validateLine(line);
            if (line.indent < item_indent) break;
            if (line.indent != item_indent) return ToonError.InvalidIndentation;
            if (!std.mem.startsWith(u8, line.text, "-")) return ToonError.InvalidSyntax;

            const rest = std.mem.trimLeft(u8, line.text[1..], " ");
            self.index += 1;
            try list.append(try self.parseListItemValue(item_indent, rest));
        }

        if (count != expected_len) return ToonError.InvalidSyntax;
        return list;
    }

    fn parseListItemValue(self: *Parser, item_indent: usize, rest: []const u8) anyerror!std.json.Value {
        if (rest.len == 0) {
            return .{ .object = std.json.ObjectMap.init(self.allocator) };
        }

        if (rest[0] == '[') {
            const colon = findTopLevelColon(rest) orelse return ToonError.InvalidSyntax;
            const lhs = std.mem.trim(u8, rest[0..colon], " ");
            const rhs = std.mem.trim(u8, rest[colon + 1 ..], " ");

            var header = (try maybeParseArrayHeader(self.allocator, lhs)) orelse return ToonError.InvalidSyntax;
            defer header.deinit();
            if (header.key != null) return ToonError.InvalidSyntax;

            return .{ .array = try self.parseArrayBody(item_indent, &header, rhs) };
        }

        if (findTopLevelColon(rest) != null) {
            return self.parseListItemObject(item_indent, rest);
        }

        return parseScalar(self.allocator, rest);
    }

    fn parseListItemObject(self: *Parser, item_indent: usize, first_text: []const u8) anyerror!std.json.Value {
        var object = std.json.ObjectMap.init(self.allocator);
        errdefer object.deinit();

        try self.parseObjectEntryText(
            &object,
            item_indent,
            item_indent + self.options.indent_width,
            first_text,
            false,
        );

        const continuation_indent = item_indent + self.options.indent_width;
        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.is_blank) {
                self.index += 1;
                continue;
            }
            try self.validateLine(line);
            if (line.indent <= item_indent) break;
            if (line.indent != continuation_indent) return ToonError.InvalidIndentation;
            try self.parseObjectEntry(&object, continuation_indent, false);
        }

        return .{ .object = object };
    }

    fn parseTabularRows(
        self: *Parser,
        parent_indent: usize,
        expected_len: usize,
        delimiter: u8,
        fields: []const []const u8,
    ) anyerror!std.json.Array {
        var rows = std.json.Array.init(self.allocator);
        errdefer rows.deinit();

        const row_indent = parent_indent + self.options.indent_width;

        var count: usize = 0;
        while (self.index < self.lines.len and count < expected_len) : (count += 1) {
            try self.skipBlankLinesInArray();
            if (self.index >= self.lines.len) break;
            const line = self.lines[self.index];
            try self.validateLine(line);
            if (line.indent < row_indent) break;
            if (line.indent != row_indent) return ToonError.InvalidIndentation;

            const parts = try splitQuoted(self.allocator, line.text, delimiter);
            defer parts.deinit();
            if (parts.items.len != fields.len) return ToonError.InvalidSyntax;

            var row = std.json.ObjectMap.init(self.allocator);
            errdefer row.deinit();

            for (fields, parts.items) |field, part| {
                const field_key = try parseKeyToken(self.allocator, field);
                errdefer self.allocator.free(field_key);
                try row.put(field_key, try parseScalar(self.allocator, std.mem.trim(u8, part, " ")));
            }

            try rows.append(.{ .object = row });
            self.index += 1;
        }

        if (count != expected_len) return ToonError.InvalidSyntax;
        return rows;
    }

    fn parseInlineArrayPayload(
        self: *Parser,
        payload: []const u8,
        expected_len: usize,
        delimiter: u8,
    ) anyerror!std.json.Array {
        var list = std.json.Array.init(self.allocator);
        errdefer list.deinit();

        if (payload.len == 0) {
            if (expected_len != 0) return ToonError.InvalidSyntax;
            return list;
        }

        const parts = try splitQuoted(self.allocator, payload, delimiter);
        defer parts.deinit();
        if (parts.items.len != expected_len) return ToonError.InvalidSyntax;

        for (parts.items) |part| {
            try list.append(try parseScalar(self.allocator, std.mem.trim(u8, part, " ")));
        }

        return list;
    }

    fn validateLine(self: *Parser, line: tokenizer.Line) !void {
        if (self.options.strict) {
            if (line.has_tab_in_indent) return ToonError.InvalidIndentation;
            if (!line.is_blank and line.indent % self.options.indent_width != 0) return ToonError.InvalidIndentation;
        }
    }

    fn skipBlankLinesRoot(self: *Parser) void {
        while (self.index < self.lines.len and self.lines[self.index].is_blank) : (self.index += 1) {}
    }

    fn skipBlankLinesInArray(self: *Parser) !void {
        while (self.index < self.lines.len and self.lines[self.index].is_blank) {
            if (self.options.strict) return ToonError.InvalidSyntax;
            self.index += 1;
        }
    }

    fn singleNonBlankLineRemaining(self: *Parser) ?tokenizer.Line {
        var found: ?tokenizer.Line = null;
        var i = self.index;
        while (i < self.lines.len) : (i += 1) {
            const line = self.lines[i];
            if (line.is_blank) continue;
            if (found != null) return null;
            found = line;
        }
        return found;
    }

    fn insertObjectValue(
        self: *Parser,
        object: *std.json.ObjectMap,
        key: []const u8,
        was_quoted: bool,
        value: std.json.Value,
    ) anyerror!void {
        if (self.options.expand_paths == .safe and !was_quoted) {
            if (try splitExpandablePath(self.allocator, key)) |segments| {
                defer segments.deinit();
                if (segments.items.len > 1) {
                    defer self.allocator.free(key);
                    return self.insertExpandedPath(object, segments.items, value);
                }
            }
        }

        return self.putObjectValue(object, key, value);
    }

    fn insertExpandedPath(
        self: *Parser,
        object: *std.json.ObjectMap,
        segments: []const []const u8,
        value: std.json.Value,
    ) anyerror!void {
        const segment_key = try self.allocator.dupe(u8, segments[0]);
        errdefer self.allocator.free(segment_key);

        if (segments.len == 1) {
            return self.putObjectValue(object, segment_key, value);
        }

        const gop = try object.getOrPut(segment_key);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(self.allocator) };
        } else switch (gop.value_ptr.*) {
            .object => {
                self.allocator.free(segment_key);
            },
            else => {
                if (self.options.strict) {
                    self.allocator.free(segment_key);
                    return ToonError.StrictViolation;
                }
                self.allocator.free(segment_key);
                value_util.deinitValue(self.allocator, gop.value_ptr);
                gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(self.allocator) };
            },
        }

        return self.insertExpandedPath(&gop.value_ptr.object, segments[1..], value);
    }

    fn putObjectValue(
        self: *Parser,
        object: *std.json.ObjectMap,
        key: []const u8,
        value: std.json.Value,
    ) anyerror!void {
        const gop = try object.getOrPut(key);
        if (!gop.found_existing) {
            gop.value_ptr.* = value;
            return;
        }

        if (gop.value_ptr.* == .object and value == .object) {
            try self.mergeObjects(&gop.value_ptr.object, value.object);
            return;
        }

        if (self.options.strict) return ToonError.StrictViolation;
        self.allocator.free(key);
        value_util.deinitValue(self.allocator, gop.value_ptr);
        gop.value_ptr.* = value;
    }

    fn mergeObjects(
        self: *Parser,
        into: *std.json.ObjectMap,
        incoming: std.json.ObjectMap,
    ) anyerror!void {
        var mutable_incoming = incoming;
        defer mutable_incoming.deinit();

        var it = mutable_incoming.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            entry.key_ptr.* = &.{};
            entry.value_ptr.* = .null;
            try self.putObjectValue(into, key, value);
        }
    }
};

fn maybeParseArrayHeader(allocator: std.mem.Allocator, lhs: []const u8) !?ArrayHeader {
    const bracket = std.mem.indexOfScalar(u8, lhs, '[') orelse return null;
    const close = std.mem.indexOfScalarPos(u8, lhs, bracket + 1, ']') orelse return null;

    const key_part = std.mem.trim(u8, lhs[0..bracket], " ");
    const bracket_inner = std.mem.trim(u8, lhs[bracket + 1 .. close], " ");
    const after = std.mem.trim(u8, lhs[close + 1 ..], " ");

    if (std.mem.indexOfScalarPos(u8, lhs, close + 1, '[') != null) return null;

    var delimiter: u8 = ',';
    var len_slice = bracket_inner;
    if (bracket_inner.len != 0) {
        const last = bracket_inner[bracket_inner.len - 1];
        if (last == ',' or last == '|' or last == '\t') {
            delimiter = last;
            len_slice = bracket_inner[0 .. bracket_inner.len - 1];
        }
    }

    const len = std.fmt.parseUnsigned(usize, std.mem.trim(u8, len_slice, " "), 10) catch return null;
    var fields: ?std.array_list.Managed([]const u8) = null;

    if (after.len != 0) {
        if (after[0] != '{' or after[after.len - 1] != '}') return null;
        fields = try splitQuoted(allocator, after[1 .. after.len - 1], delimiter);
    }

    return .{
        .key = if (key_part.len == 0) null else key_part,
        .key_was_quoted = isQuotedToken(key_part),
        .len = len,
        .delimiter = delimiter,
        .fields = fields,
    };
}

const ParsedKey = struct {
    value: []u8,
    was_quoted: bool,
};

fn parseKeyInfo(allocator: std.mem.Allocator, raw: []const u8) !ParsedKey {
    const trimmed = std.mem.trim(u8, raw, " ");
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return .{
            .value = try unescapeQuoted(allocator, trimmed[1 .. trimmed.len - 1]),
            .was_quoted = true,
        };
    }
    return .{
        .value = try allocator.dupe(u8, trimmed),
        .was_quoted = false,
    };
}

fn parseKeyToken(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    return (try parseKeyInfo(allocator, raw)).value;
}

fn splitQuoted(allocator: std.mem.Allocator, text: []const u8, delimiter: u8) !std.array_list.Managed([]const u8) {
    var parts = std.array_list.Managed([]const u8).init(allocator);
    errdefer parts.deinit();

    if (text.len == 0) return parts;

    var start: usize = 0;
    var in_quotes = false;
    var escaped = false;

    for (text, 0..) |ch, idx| {
        if (escaped) {
            escaped = false;
            continue;
        }

        if (in_quotes and ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"') {
            in_quotes = !in_quotes;
            continue;
        }

        if (!in_quotes and ch == delimiter) {
            try parts.append(text[start..idx]);
            start = idx + 1;
        }
    }

    if (in_quotes) return ToonError.InvalidSyntax;
    try parts.append(text[start..]);
    return parts;
}

fn findTopLevelColon(text: []const u8) ?usize {
    var in_quotes = false;
    var escaped = false;

    for (text, 0..) |ch, idx| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (in_quotes and ch == '\\') {
            escaped = true;
            continue;
        }
        if (ch == '"') {
            in_quotes = !in_quotes;
            continue;
        }
        if (!in_quotes and ch == ':') return idx;
    }

    return null;
}

fn parseScalar(allocator: std.mem.Allocator, raw: []const u8) !std.json.Value {
    if (std.mem.eql(u8, raw, "null")) return .null;
    if (std.mem.eql(u8, raw, "true")) return .{ .bool = true };
    if (std.mem.eql(u8, raw, "false")) return .{ .bool = false };

    if ((raw.len != 0 and raw[0] == '"') or (raw.len != 0 and raw[raw.len - 1] == '"')) {
        if (!(raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')) {
            return ToonError.InvalidSyntax;
        }
    }

    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') {
        return .{ .string = try unescapeQuoted(allocator, raw[1 .. raw.len - 1]) };
    }

    if (try parseNumberToken(raw)) |number| {
        return number;
    }

    return .{ .string = try allocator.dupe(u8, raw) };
}

fn parseNumberToken(raw: []const u8) !?std.json.Value {
    if (!looksLikeNumericToken(raw)) return null;
    if (hasInvalidLeadingZero(raw)) return null;

    if (std.fmt.parseFloat(f64, raw)) |float_value| {
        if (!std.math.isFinite(float_value)) return null;

        if (float_value == 0) {
            return .{ .integer = 0 };
        }

        const truncated = @trunc(float_value);
        const min_i64_f: f64 = @floatFromInt(std.math.minInt(i64));
        const max_i64_f: f64 = @floatFromInt(std.math.maxInt(i64));
        if (truncated == float_value and truncated >= min_i64_f and truncated <= max_i64_f) {
            return .{ .integer = @intFromFloat(truncated) };
        }

        return .{ .float = float_value };
    } else |_| {
        return null;
    }
}

fn looksLikeNumericToken(raw: []const u8) bool {
    if (raw.len == 0) return false;

    var i: usize = 0;
    if (raw[i] == '-' or raw[i] == '+') {
        i += 1;
        if (i >= raw.len) return false;
    }

    var has_digit = false;
    var has_dot = false;
    var has_exp = false;

    while (i < raw.len) : (i += 1) {
        const ch = raw[i];
        if (std.ascii.isDigit(ch)) {
            has_digit = true;
            continue;
        }

        if (ch == '.') {
            if (has_dot or has_exp) return false;
            has_dot = true;
            continue;
        }

        if (ch == 'e' or ch == 'E') {
            if (has_exp or !has_digit) return false;
            has_exp = true;
            has_digit = false;
            if (i + 1 < raw.len and (raw[i + 1] == '+' or raw[i + 1] == '-')) i += 1;
            continue;
        }

        return false;
    }

    return has_digit;
}

fn hasInvalidLeadingZero(raw: []const u8) bool {
    var i: usize = 0;
    if (raw.len == 0) return false;
    if (raw[i] == '-' or raw[i] == '+') i += 1;
    if (i >= raw.len) return false;
    if (raw[i] != '0') return false;
    if (i + 1 >= raw.len) return false;

    const next = raw[i + 1];
    return std.ascii.isDigit(next);
}

fn isQuotedToken(raw: []const u8) bool {
    const trimmed = std.mem.trim(u8, raw, " ");
    return trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"';
}

fn splitExpandablePath(
    allocator: std.mem.Allocator,
    key: []const u8,
) !?std.array_list.Managed([]const u8) {
    if (std.mem.indexOfScalar(u8, key, '.') == null) return null;

    var parts = std.array_list.Managed([]const u8).init(allocator);
    errdefer parts.deinit();

    var start: usize = 0;
    while (start <= key.len) {
        const end = std.mem.indexOfScalarPos(u8, key, start, '.') orelse key.len;
        const segment = key[start..end];
        if (!isIdentifierSegment(segment)) return null;
        try parts.append(segment);
        if (end == key.len) break;
        start = end + 1;
    }

    return parts;
}

fn isIdentifierSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;
    if (!(std.ascii.isAlphabetic(segment[0]) or segment[0] == '_')) return false;
    for (segment[1..]) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    }
    return true;
}

fn unescapeQuoted(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();

    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] != '\\') {
            try output.append(raw[i]);
            continue;
        }

        i += 1;
        if (i >= raw.len) return ToonError.InvalidSyntax;

        switch (raw[i]) {
            '\\' => try output.append('\\'),
            '"' => try output.append('"'),
            'n' => try output.append('\n'),
            'r' => try output.append('\r'),
            't' => try output.append('\t'),
            else => return ToonError.InvalidSyntax,
        }
    }

    return output.toOwnedSlice();
}

test "decode flat object and primitive array subset" {
    const allocator = std.testing.allocator;
    var value = try decodeAlloc(allocator, "name: Ada\ntags[2]: math,logic", .{});
    defer value_util.deinitValue(allocator, &value);

    const object = value.object;
    try std.testing.expectEqualStrings("Ada", object.get("name").?.string);
    try std.testing.expectEqual(@as(usize, 2), object.get("tags").?.array.items.len);
    try std.testing.expectEqualStrings("logic", object.get("tags").?.array.items[1].string);
}

test "decode tabular array with quoted header key" {
    const allocator = std.testing.allocator;
    var value = try decodeAlloc(
        allocator,
        "\"x-items\"[2]{id,name}:\n  1,Ada\n  2,Bob",
        .{},
    );
    defer value_util.deinitValue(allocator, &value);

    const items = value.object.get("x-items").?.array;
    try std.testing.expectEqual(@as(usize, 2), items.items.len);
    try std.testing.expectEqualStrings("Bob", items.items[1].object.get("name").?.string);
}

test "decode tabular array with pipe delimiter" {
    const allocator = std.testing.allocator;
    var value = try decodeAlloc(
        allocator,
        "items[2|]{sku|qty|price}:\n  A1|2|9.99\n  B2|1|14.5",
        .{},
    );
    defer value_util.deinitValue(allocator, &value);

    const items = value.object.get("items").?.array;
    try std.testing.expectEqual(@as(usize, 2), items.items.len);
    try std.testing.expectEqual(@as(i64, 2), items.items[0].object.get("qty").?.integer);
    try std.testing.expectEqual(@as(f64, 14.5), items.items[1].object.get("price").?.float);
}

test "decode list array mixing primitive object and nested array" {
    const allocator = std.testing.allocator;
    var value = try decodeAlloc(
        allocator,
        "[3]:\n  - summary\n  - id: 1\n    name: Ada\n  - [2]:\n    - id: 2\n    - status: draft",
        .{},
    );
    defer value_util.deinitValue(allocator, &value);

    const items = value.array;
    try std.testing.expectEqual(@as(usize, 3), items.items.len);
    try std.testing.expectEqualStrings("summary", items.items[0].string);
    try std.testing.expectEqualStrings("Ada", items.items[1].object.get("name").?.string);
    try std.testing.expectEqualStrings("draft", items.items[2].array.items[1].object.get("status").?.string);
}
