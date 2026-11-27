//! SQLite page storage. All statements use bound integers and blobs.
const std = @import("std");
const Db = opaque {};
const Stmt = opaque {};
extern "c" fn sqlite3_open([*:0]const u8, *?*Db) c_int;
extern "c" fn sqlite3_close(*Db) c_int;
extern "c" fn sqlite3_exec(*Db, [*:0]const u8, ?*anyopaque, ?*anyopaque, ?*anyopaque) c_int;
extern "c" fn sqlite3_prepare_v2(*Db, [*:0]const u8, c_int, *?*Stmt, ?*anyopaque) c_int;
extern "c" fn sqlite3_finalize(*Stmt) c_int;
extern "c" fn sqlite3_bind_int64(*Stmt, c_int, i64) c_int;
extern "c" fn sqlite3_bind_blob64(*Stmt, c_int, [*]const u8, u64, ?*anyopaque) c_int;
extern "c" fn sqlite3_step(*Stmt) c_int;
extern "c" fn sqlite3_column_bytes(*Stmt, c_int) c_int;
extern "c" fn sqlite3_column_blob(*Stmt, c_int) ?[*]const u8;

pub const Store = struct {
    db: *Db,

    pub fn init(path: [*:0]const u8) !Store {
        var db: ?*Db = null;
        const rc = sqlite3_open(path, &db);
        errdefer if (db) |handle| {
            _ = sqlite3_close(handle);
        };
        if (rc != 0) return error.Database;
        var store = Store{ .db = db.? };
        try store.exec("CREATE TABLE pages (id INTEGER PRIMARY KEY, data BLOB NOT NULL)");
        return store;
    }
    pub fn deinit(self: Store) void {
        _ = sqlite3_close(self.db);
    }
    pub fn exec(self: Store, sql: [*:0]const u8) !void {
        if (sqlite3_exec(self.db, sql, null, null, null) != 0) return error.Database;
    }
    fn statement(self: Store, query: [*:0]const u8, id: i64) !*Stmt {
        var stmt: ?*Stmt = null;
        if (sqlite3_prepare_v2(self.db, query, -1, &stmt, null) != 0) return error.Database;
        errdefer _ = sqlite3_finalize(stmt.?);
        if (sqlite3_bind_int64(stmt.?, 1, id) != 0) return error.Database;
        return stmt.?;
    }
    pub fn remove(self: Store, id: i64) !void {
        const stmt = try self.statement("DELETE FROM pages WHERE id = ?", id);
        defer _ = sqlite3_finalize(stmt);
        if (sqlite3_step(stmt) != 101) return error.Database;
    }
    pub fn insert(self: Store, id: i64, data: []const u8) !void {
        const stmt = try self.statement("INSERT INTO pages VALUES (?, ?)", id);
        defer _ = sqlite3_finalize(stmt);
        if (sqlite3_bind_blob64(stmt, 2, data.ptr, data.len, null) != 0 or sqlite3_step(stmt) != 101) return error.Database;
    }
    pub fn read(self: Store, id: i64, out: []u8) !void {
        const stmt = try self.statement("SELECT data FROM pages WHERE id = ?", id);
        defer _ = sqlite3_finalize(stmt);
        switch (sqlite3_step(stmt)) {
            101 => return error.CorruptPage,
            100 => {},
            else => return error.Database,
        }
        if (sqlite3_column_bytes(stmt, 0) != out.len) return error.CorruptPage;
        const data = sqlite3_column_blob(stmt, 0) orelse return error.CorruptPage;
        @memcpy(out, data[0..out.len]);
    }
};
