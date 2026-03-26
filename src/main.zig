const std = @import("std");
const zig_sql = @import("zig_sql");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    const config = try loadConfigFromEnv(allocator);

    var connection = try zig_sql.postgres.connect(allocator, config);
    defer connection.deinit();

    try stdout.print("Connected to PostgreSQL at {s}:{d}\n", .{ config.host, config.port });
    try stdout.flush();
}

fn loadConfigFromEnv(allocator: std.mem.Allocator) !zig_sql.postgres.Config {
    const host = try std.process.getEnvVarOwned(allocator, "PGHOST");
    const user = try std.process.getEnvVarOwned(allocator, "PGUSER");
    const password = try std.process.getEnvVarOwned(allocator, "PGPASSWORD");
    const database = try std.process.getEnvVarOwned(allocator, "PGDATABASE");

    const port_text = std.process.getEnvVarOwned(allocator, "PGPORT") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };

    const port = if (port_text) |value|
        try std.fmt.parseInt(u16, value, 10)
    else
        5432;

    return .{
        .host = host,
        .port = port,
        .user = user,
        .password = password,
        .database = database,
    };
}
