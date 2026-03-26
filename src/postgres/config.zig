pub const Config = struct {
    host: []const u8,
    port: u16 = 5432,
    user: []const u8,
    password: []const u8,
    database: []const u8,
};
