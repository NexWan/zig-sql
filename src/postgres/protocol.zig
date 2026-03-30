const std = @import("std");
const Config = @import("config.zig").Config;

pub const BackendTag = enum(u8) {
    Authentication = 'R',
    BackendKeyData = 'K',
    ParameterStatus = 'S',
    ReadyForQuery = 'Z',
    ErrorResponse = 'E',
};

pub const AuthRequest = enum(i32) {
    Ok = 0,
    CleartextPassword = 3,
    MD5Password = 5,
    SASL = 10,
};

pub const BackendMessage = struct {
    tag: u8,
    payload: []const u8,
};

pub fn writeStartupMessage(writer: anytype, config: Config) !void {
    var payload_buf: [512]u8 = undefined;
    var payload_stream = std.io.fixedBufferStream(&payload_buf);
    const payload_writer = payload_stream.writer();

    try writeInt32BE(payload_writer, 196608);
    try writeCString(payload_writer, "user");
    try writeCString(payload_writer, config.user);
    try writeCString(payload_writer, "database");
    try writeCString(payload_writer, config.database);
    try writeCString(payload_writer, "client_encoding");
    try writeCString(payload_writer, "UTF8");
    try payload_writer.writeByte(0);

    const payload_len = payload_stream.pos;
    try writeInt32BE(writer, @intCast(payload_len + 4));
    try writer.writeAll(payload_buf[0..payload_len]);
}

fn writeCString(writer: anytype, value: []const u8) !void {
    try writer.writeAll(value);
    try writer.writeByte(0);
}

fn writeInt32BE(writer: anytype, value: i32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, value, .big);
    try writer.writeAll(&buf);
}

pub fn writePasswordMessage(writer: anytype, password: []const u8) !void {
    try writer.writeByte('p');
    try writeInt32BE(writer, @intCast(4 + password.len + 1));
    try writeCString(writer, password);
}

fn readInt32BE(reader: *std.Io.Reader) !i32 {
    return try reader.takeInt(i32, .big);
}

pub fn readMessage(allocator: std.mem.Allocator, reader: *std.Io.Reader) !BackendMessage {
    const tag = try reader.takeByte();
    const length = try readInt32BE(reader);

    if (length < 4) return error.InvalidMessageLength;

    const payload_len: usize = @intCast(length - 4);
    const payload = try reader.readAlloc(allocator, payload_len);

    return BackendMessage{
        .tag = tag,
        .payload = payload,
    };
}

pub fn freeMessage(allocator: std.mem.Allocator, message: BackendMessage) void {
    allocator.free(message.payload);
}

pub fn parseAuthRequest(payload: []const u8) !AuthRequest {
    if (payload.len < 4) return error.InvalidAuthenticationMessage;

    const code = std.mem.readInt(i32, payload[0..4], .big);
    return std.meta.intToEnum(AuthRequest, code) catch error.UnsupportedAuthMethod;
}

pub fn parseRowDescription(allocator: std.mem.Allocator, payload: []const u8) ![][]const u8 {
    if (payload.len < 2) return error.InvalidRowDescription;
    const col_count: usize = @intCast(std.mem.readInt(i16, payload[0..2], .big));

    const columns = try allocator.alloc([]const u8, col_count);
    errdefer allocator.free(columns);

    var pos: usize = 2;
    for (0..col_count) |i| {
        const name_start = pos;
        while (pos < payload.len and payload[pos] != 0) : (pos += 1) {}
        columns[i] = try allocator.dupe(u8, payload[name_start..pos]);
        pos += 1; // skip null terminator
        pos += 18; // tableOID(4) + colAttr(2) + typeOID(4) + typeSize(2) + typeMod(4) + format(2)
    }

    return columns;
}

pub fn parseDataRow(allocator: std.mem.Allocator, payload: []const u8, col_count: usize) ![]?[]const u8 {
    const row = try allocator.alloc(?[]const u8, col_count);
    errdefer allocator.free(row);

    var pos: usize = 2; // skip int16 column count
    for (0..col_count) |i| {
        if (pos + 4 > payload.len) return error.InvalidDataRow;
        const len = std.mem.readInt(i32, payload[pos..][0..4], .big);
        pos += 4;
        if (len == -1) {
            row[i] = null;
        } else {
            const value_len: usize = @intCast(len);
            row[i] = try allocator.dupe(u8, payload[pos .. pos + value_len]);
            pos += value_len;
        }
    }

    return row;
}

pub fn writeSimpleQuery(writer: anytype, query: []const u8) !void {
    try writer.writeByte('Q');
    try writeInt32BE(writer, @intCast(4 + query.len + 1));
    try writeCString(writer, query);
}
