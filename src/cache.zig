//! Fixed-size immutable page cache with bounded resident and disk tiers.
const std = @import("std");
const Store = @import("storage.zig").Store;
const Sha = std.crypto.hash.sha2.Sha256;
const Tier = enum(u2) { gpu, ram, disk };
const Page = struct { tier: Tier, data: ?[]u8, digest: [32]u8, touched: u64 = 0, pins: usize = 0 };

/// Page counts and successful read hits in GPU, RAM and disk order.
pub const Stats = extern struct { pages: [3]u64, hits: [3]u64 };

/// Single-owner cache. Bindings serialize concurrent callers and validate handle ownership.
pub const Cache = struct {
    allocator: std.mem.Allocator,
    store: Store,
    pages: std.AutoHashMap(i64, Page),
    limits: [3]usize,
    capacity: usize,
    size: usize,
    next: i64 = 0,
    clock: u64 = 0,
    stats: Stats = .{ .pages = .{ 0, 0, 0 }, .hits = .{ 0, 0, 0 } },

    /// Open a fresh SQLite database and establish positive page limits.
    pub fn init(a: std.mem.Allocator, path: [*:0]const u8, size: usize, limits: [3]usize) !Cache {
        if (size == 0 or @reduce(.Min, @as(@Vector(3, usize), limits)) == 0) return error.Invalid;
        const capacity = try std.math.add(usize, try std.math.add(usize, limits[0], limits[1]), limits[2]);
        return .{ .allocator = a, .size = size, .limits = limits, .capacity = capacity, .store = try Store.init(path), .pages = std.AutoHashMap(i64, Page).init(a) };
    }
    /// Release storage after every pin has been returned.
    pub fn deinit(self: *Cache) !void {
        var iter = self.pages.valueIterator();
        while (iter.next()) |page| if (page.pins != 0) return error.Pinned;
        iter = self.pages.valueIterator();
        while (iter.next()) |page| if (page.data) |buf| self.allocator.free(buf);
        self.pages.deinit();
        self.store.deinit();
    }
    fn tick(self: *Cache) u64 {
        self.clock += 1;
        return self.clock;
    }
    fn victim(self: *Cache, tier: Tier) ?i64 {
        var best: ?i64 = null;
        var stamp: u64 = std.math.maxInt(u64);
        var iter = self.pages.iterator();
        while (iter.next()) |entry| {
            const page = entry.value_ptr.*;
            if (page.tier == tier and page.pins == 0 and page.touched <= stamp) {
                best = entry.key_ptr.*;
                stamp = page.touched;
            }
        }
        return best;
    }
    fn move(self: *Cache, id: i64, dest: Tier) void {
        const page = self.pages.getPtr(id).?;
        self.stats.pages[@intFromEnum(page.tier)] -= 1;
        self.stats.pages[@intFromEnum(dest)] += 1;
        page.tier = dest;
        page.touched = self.tick();
    }
    // All fallible I/O precedes the first mutation of resident state.
    fn admit(self: *Cache, id: i64, source: ?Tier) !void {
        var gpu: ?i64 = null;
        var ram: ?i64 = null;
        if (self.stats.pages[0] == self.limits[0]) {
            gpu = self.victim(.gpu) orelse return error.CacheFull;
            if (self.stats.pages[1] == self.limits[1] and source != .ram)
                ram = self.victim(.ram).?;
        }
        if (ram != null or source == .disk) {
            try self.store.exec("BEGIN IMMEDIATE");
            errdefer self.store.exec("ROLLBACK") catch {};
            if (source == .disk) try self.store.remove(id);
            if (ram) |key| try self.store.insert(key, self.pages.get(key).?.data.?);
            try self.store.exec("COMMIT");
        }
        if (ram) |key| {
            const page = self.pages.getPtr(key).?;
            self.allocator.free(page.data.?);
            page.data = null;
            self.move(key, .disk);
        }
        if (gpu) |key| self.move(key, .ram);
    }
    /// Copy a page and return a non-reused allocation identifier.
    pub fn put(self: *Cache, data: []const u8) !i64 {
        if (data.len != self.size) return error.Invalid;
        if (self.pages.count() == self.capacity) return error.CacheFull;
        const id = self.next;
        const next = try std.math.add(i64, id, 1);
        try self.pages.ensureUnusedCapacity(1);
        const buf = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(buf);
        var digest: [32]u8 = undefined;
        Sha.hash(buf, &digest, .{});
        try self.admit(id, null);
        self.pages.putAssumeCapacity(id, .{ .tier = .gpu, .data = buf, .digest = digest, .touched = self.tick() });
        self.next = next;
        self.stats.pages[0] += 1;
        return id;
    }
    /// Promote a page and return a view valid until its next eviction or release.
    pub fn read(self: *Cache, id: i64) ![]const u8 {
        const page = self.pages.getPtr(id) orelse return error.UnknownHandle;
        const source = page.tier;
        if (source == .disk) {
            const buf = try self.allocator.alloc(u8, self.size);
            errdefer self.allocator.free(buf);
            try self.store.read(id, buf);
            var digest: [32]u8 = undefined;
            Sha.hash(buf, &digest, .{});
            if (!std.mem.eql(u8, &digest, &page.digest)) return error.CorruptPage;
            try self.admit(id, source);
            page.data = buf;
        } else if (source == .ram) try self.admit(id, source);
        self.move(id, .gpu);
        self.stats.hits[@intFromEnum(source)] += 1;
        return page.data.?;
    }
    /// Hold a resident view until the matching unpin.
    pub fn pin(self: *Cache, id: i64) ![]const u8 {
        const data = try self.read(id);
        self.pages.getPtr(id).?.pins += 1;
        return data;
    }
    pub fn unpin(self: *Cache, id: i64) !void {
        const page = self.pages.getPtr(id) orelse return error.UnknownHandle;
        if (page.pins == 0) return error.Invalid;
        page.pins -= 1;
    }
    /// Invalidate one allocation and reclaim its slot.
    pub fn release(self: *Cache, id: i64) !void {
        const page = self.pages.get(id) orelse return error.UnknownHandle;
        if (page.pins != 0) return error.Pinned;
        if (page.data) |buf| self.allocator.free(buf) else try self.store.remove(id);
        self.stats.pages[@intFromEnum(page.tier)] -= 1;
        _ = self.pages.remove(id);
    }
};

test "byte exact replay, nested pins, stale handles and disk rollback" {
    var cache = try Cache.init(std.testing.allocator, "", 1, .{ 1, 1, 1 });
    defer cache.deinit() catch unreachable;
    const a = try cache.put("a");
    const b = try cache.put("b");
    const c = try cache.put("c");
    try std.testing.expectError(error.CacheFull, cache.put("d"));
    _ = try cache.pin(c);
    _ = try cache.pin(c);
    try std.testing.expectError(error.CacheFull, cache.read(b));
    try std.testing.expectError(error.Pinned, cache.release(c));
    try cache.unpin(c);
    try std.testing.expectError(error.Pinned, cache.deinit());
    try cache.unpin(c);
    try cache.store.exec("CREATE TRIGGER fail BEFORE INSERT ON pages BEGIN SELECT RAISE(ABORT,'full'); END");
    try std.testing.expectError(error.Database, cache.read(a));
    try cache.store.exec("DROP TRIGGER fail");
    for ([_]i64{ a, b, c }, [_][]const u8{ "a", "b", "c" }) |id, expected| try std.testing.expectEqualSlices(u8, expected, try cache.read(id));
    try cache.release(c);
    try std.testing.expectError(error.UnknownHandle, cache.read(c));
}
