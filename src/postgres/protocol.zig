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
