//! C ABI for owned cache instances. The caller serializes access to each instance.
const std = @import("std");
const native = @import("cache.zig");
const Cache = native.Cache;
const allocator = std.heap.c_allocator;

fn status(err: anyerror) c_int {
    return switch (err) {
        error.CacheFull => 1,
        error.CorruptPage => 2,
        error.UnknownHandle => 3,
        error.Pinned => 4,
        error.Database => 5,
        error.OutOfMemory => 6,
        else => 7,
    };
}
export fn kv_open(path: [*:0]const u8, size: usize, gpu: usize, ram: usize, disk: usize, out: **Cache) c_int {
    const cache = allocator.create(Cache) catch return 6;
    cache.* = Cache.init(allocator, path, size, .{ gpu, ram, disk }) catch |err| {
        allocator.destroy(cache);
        return status(err);
    };
    out.* = cache;
    return 0;
}
export fn kv_close(cache: *Cache) c_int {
    cache.deinit() catch |err| return status(err);
    allocator.destroy(cache);
    return 0;
}
export fn kv_put(cache: *Cache, ptr: [*]const u8, len: usize, id: *i64) c_int {
    id.* = cache.put(ptr[0..len]) catch |err| return status(err);
    return 0;
}
export fn kv_read(cache: *Cache, id: i64, pin_mode: bool, out: ?[*]u8) c_int {
    const data = (if (pin_mode) cache.pin(id) else cache.read(id)) catch |err| return status(err);
    if (out) |ptr| @memcpy(ptr[0..data.len], data);
    return 0;
}
export fn kv_unpin(cache: *Cache, id: i64) c_int {
    cache.unpin(id) catch |err| return status(err);
    return 0;
}
export fn kv_release(cache: *Cache, id: i64) c_int {
    cache.release(id) catch |err| return status(err);
    return 0;
}
export fn kv_stats(cache: *Cache, out: *native.Stats) void {
    out.* = cache.stats;
}
