const Config = @import("config.zig").Config;
const protocol = @import("protocol.zig");
const result = @import("result.zig");
const std = @import("std");

pub const Connection = struct {
    config: Config,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,

    pub fn deinit(self: *Connection) void {
        self.stream.close();
    }

    pub fn query(self: *Connection, sql: []const u8) !result.Result {
        var read_buffer: [4096]u8 = undefined;
        var write_buffer: [0]u8 = .{};
        var reader_impl = self.stream.reader(&read_buffer);
        var writer_impl = self.stream.writer(&write_buffer);

        try protocol.writeSimpleQuery(&writer_impl.interface, sql);

        var columns: [][]const u8 = &.{};
        var rows = std.ArrayListUnmanaged(result.Row){};
        defer rows.deinit(self.allocator);

        while (true) {
            const message = try protocol.readMessage(self.allocator, reader_impl.interface());
            defer protocol.freeMessage(self.allocator, message);

            switch (message.tag) {
                'T' => {
                    columns = try protocol.parseRowDescription(self.allocator, message.payload);
                },
                'D' => {
                    const row = try protocol.parseDataRow(self.allocator, message.payload, columns.len);
                    try rows.append(self.allocator, row);
                },
                'C' => {}, // CommandComplete, ignore
                'Z' => {
                    return result.Result{
                        .columns = columns,
                        .rows = try rows.toOwnedSlice(self.allocator),
                        .allocator = self.allocator,
                    };
                },
                'E' => return error.ServerError,
                else => return error.UnsupportedBackendMessage,
            }
        }
    }
};

pub fn connect(allocator: std.mem.Allocator, config: Config) !Connection {
    const address = try std.net.Address.parseIp(config.host, config.port);
    const stream = try std.net.tcpConnectToAddress(address);
    errdefer stream.close();

    var read_buffer: [4096]u8 = undefined;
    var write_buffer: [0]u8 = .{};
    var reader_impl = stream.reader(&read_buffer);
    var writer_impl = stream.writer(&write_buffer);
    const reader = reader_impl.interface();

    std.debug.print("postgres: connecting to {s}:{d}\n", .{ config.host, config.port });
    try protocol.writeStartupMessage(&writer_impl.interface, config);
    std.debug.print("postgres: startup message sent for user={s} database={s}\n", .{ config.user, config.database });

    while (true) {
        const message = try protocol.readMessage(allocator, reader);
        defer protocol.freeMessage(allocator, message);
        std.debug.print(
            "postgres: received message tag={c} payload_len={d}\n",
            .{ message.tag, message.payload.len },
        );

        switch (message.tag) {
            'R' => {
                const auth = try protocol.parseAuthRequest(message.payload);
                std.debug.print("postgres: auth request={s}\n", .{@tagName(auth)});
                switch (auth) {
                    .Ok => {},
                    .CleartextPassword => {
                        std.debug.print("postgres: sending cleartext password\n", .{});
                        try protocol.writePasswordMessage(&writer_impl.interface, config.password);
                    },
                    else => return error.UnsupportedAuthMethod,
                }
            },
            'S' => std.debug.print("postgres: parameter status received\n", .{}),
            'K' => std.debug.print("postgres: backend key data received\n", .{}),
            'Z' => {
                std.debug.print("postgres: ready for query\n", .{});
                return Connection{
                    .config = config,
                    .allocator = allocator,
                    .stream = stream,
                };
            },
            'E' => {
                std.debug.print("postgres: error response received\n", .{});
                return error.ServerError;
            },
            else => return error.UnsupportedBackendMessage,
        }
    }
}
