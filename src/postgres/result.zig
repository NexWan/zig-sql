const std = @import("std");

pub const Row = []?[]const u8;

pub const Result = struct {
    columns: [][]const u8,
    rows: []Row,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Result) void {
        for (self.rows) |row| {
            for (row) |value| {
                if (value) |v| self.allocator.free(v);
            }
            self.allocator.free(row);
        }
        self.allocator.free(self.rows);
        for (self.columns) |col| {
            self.allocator.free(col);
        }
        self.allocator.free(self.columns);
    }
};
