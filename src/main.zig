//! Standalone replay and paired benchmark for the native cache.
const std = @import("std");
const Cache = @import("cache.zig").Cache;
const A = std.mem.Allocator;
const Io = std.Io;
extern "c" fn mkstemp([*:0]u8) c_int;
extern "c" fn close(c_int) c_int;
extern "c" fn puts([*:0]const u8) c_int;
extern "c" fn sqlite3_libversion() [*:0]const u8;
extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;

const Options = struct {
    rounds: usize = 1,
    reads: usize = 128,
    repeats: usize = 7,
    seed: u64 = 42,
    page_bytes: usize = 4096,
    directory: []const u8 = "/tmp",
    output: []const u8 = "bench-results/cache.json",
};
const Counts = struct { gpu: u64, ram: u64, disk: u64 };
fn counts(n: [3]u64) Counts {
    return .{ .gpu = n[0], .ram = n[1], .disk = n[2] };
}
const Spill = struct {
    path: [:0]u8,
    fn create(a: A, dir: []const u8) !Spill {
        const path = try std.fmt.allocPrintSentinel(a, "{s}/kv-pages-XXXXXX", .{dir}, 0);
        const fd = mkstemp(path.ptr);
        if (fd < 0) return error.ScratchFile;
        _ = close(fd);
        return .{ .path = path };
    }
    fn remove(self: Spill, io: Io) void {
        std.Io.Dir.cwd().deleteFile(io, self.path) catch {};
    }
};
const backend = "host-bytes/host-bytes/sqlite";
fn replay(a: A, io: Io, o: Options) !void {
    const spill = try Spill.create(a, o.directory);
    defer spill.remove(io);
    var cache = try Cache.init(std.heap.c_allocator, spill.path, 4096, .{ 1, 1, 1 });
    defer cache.deinit() catch unreachable;
    var handles: [3]i64 = undefined;
    var payload: [4096]u8 = undefined;
    for (&handles, 0..) |*h, i| {
        @memset(&payload, @intCast(i));
        h.* = try cache.put(&payload);
    }
    for (0..o.rounds) |_| for ([_]usize{ 2, 1, 0, 2, 1, 0 }) |i| {
        @memset(&payload, @intCast(i));
        if (!std.mem.eql(u8, &payload, try cache.read(handles[i]))) return error.ReplayMismatch;
    };
    const record = .{ .backend = backend, .verified_reads = try std.math.mul(usize, o.rounds, 6), .pages = counts(cache.stats.pages), .hits = counts(cache.stats.hits) };
    _ = puts(try a.dupeZ(u8, try std.json.Stringify.valueAlloc(a, record, .{})));
}
const Measure = struct { read_ns: []u64, p50_ns: f64, p95_ns: u64, mean_ns: f64, hits: Counts };
fn f(n: anytype) f64 {
    return @floatFromInt(n);
}
fn measure(a: A, io: Io, dir: []const u8, size: usize, data: []const u8, trace: []const u8, limits: [3]usize) !Measure {
    const spill = try Spill.create(a, dir);
    defer spill.remove(io);
    // Cache storage uses a reclaiming allocator, including every evicted payload.
    var cache = try Cache.init(std.heap.c_allocator, spill.path, size, limits);
    defer cache.deinit() catch unreachable;
    var handles: [16]i64 = undefined;
    for (&handles, 0..) |*h, i| h.* = try cache.put(data[i * size ..][0..size]);
    for (trace) |i| _ = try cache.read(handles[i]);
    const before = cache.stats.hits;
    const samples = try a.alloc(u64, trace.len);
    var sum: f64 = 0;
    for (trace, samples) |i, *ns| {
        const begin = Io.Clock.awake.now(io);
        const page = try cache.read(handles[i]);
        ns.* = @intCast(begin.durationTo(Io.Clock.awake.now(io)).toNanoseconds());
        if (!std.mem.eql(u8, page, data[@as(usize, i) * size ..][0..size])) return error.ReplayMismatch;
        sum += f(ns.*);
    }
    const sorted = try a.dupe(u64, samples);
    std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
    var hits: [3]u64 = undefined;
    for (&hits, before, cache.stats.hits) |*h, b, end| h.* = end - b;
    return .{ .read_ns = samples, .p50_ns = (f(sorted[(sorted.len - 1) / 2]) + f(sorted[sorted.len / 2])) / 2, .p95_ns = sorted[sorted.len - 1 - sorted.len / 20], .mean_ns = sum / f(trace.len), .hits = counts(hits) };
}
const Trial = struct { resident: Measure, tiered: Measure };
const Delta = struct { mean_ns: f64, ci95_ns: [2]f64 };
const Work = struct { trace: []usize, trials: []Trial, tiered_minus_resident: Delta };
fn paired(a: A, io: Io, o: Options, data: []const u8, trace: []const u8) !Work {
    const trials = try a.alloc(Trial, o.repeats);
    const deltas = try a.alloc(f64, o.repeats);
    var sum: f64 = 0;
    for (trials, deltas, 0..) |*trial, *delta, i| {
        for (0..2) |j| {
            const resident = (i + j) % 2 == 0;
            const m = try measure(a, io, o.directory, o.page_bytes, data, trace, if (resident) .{ 16, 1, 1 } else .{ 4, 4, 8 });
            if (resident) trial.resident = m else trial.tiered = m;
        }
        delta.* = trial.tiered.mean_ns - trial.resident.mean_ns;
        sum += delta.*;
    }
    var rng = std.Random.DefaultPrng.init(o.seed);
    var samples: [2000]f64 = undefined;
    for (&samples) |*v| {
        v.* = 0;
        for (0..deltas.len) |_| v.* += deltas[rng.random().uintLessThan(usize, deltas.len)];
        v.* /= f(deltas.len);
    }
    std.mem.sort(f64, &samples, {}, std.sort.asc(f64));
    const indices = try a.alloc(usize, trace.len);
    for (indices, trace) |*i, x| i.* = x;
    return .{ .trace = indices, .trials = trials, .tiered_minus_resident = .{ .mean_ns = sum / f(deltas.len), .ci95_ns = .{ samples[49], samples[1949] } } };
}
// Follow an existing directory symlink, including /tmp on macOS.
fn ensureDirectory(io: Io, dir: []const u8) !void {
    var opened = Io.Dir.cwd().openDir(io, dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (std.fs.path.dirname(dir)) |parent| try ensureDirectory(io, parent);
            Io.Dir.cwd().createDir(io, dir, .default_dir) catch |e| if (e != error.PathAlreadyExists) return e;
            return;
        },
        else => return err,
    };
    opened.close(io);
}
fn benchmark(a: A, io: Io, o: Options) !void {
    var rng = std.Random.DefaultPrng.init(o.seed);
    const data = try a.alloc(u8, try std.math.mul(usize, 16, o.page_bytes));
    rng.random().bytes(data);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    const trace = try a.alloc(u8, o.reads);
    var work: [3]Work = undefined;
    for (&work, 0..) |*w, index| {
        for (trace, 0..) |*v, i| v.* = switch (index) {
            0 => @intCast(15 - i % 4),
            1 => @intCast(i % 16),
            else => if (rng.random().uintLessThan(u8, 10) < 8) 12 + rng.random().uintLessThan(u8, 4) else rng.random().uintLessThan(u8, 12),
        };
        w.* = try paired(a, io, o, data, trace);
    }
    const info = @import("builtin");
    const revision: ?[]const u8 = if (getenv("GITHUB_SHA")) |ptr| std.mem.span(ptr) else null;
    const hex = std.fmt.bytesToHex(digest, .lower);
    const record = .{
        .schema_version = @as(u8, 1),
        .backend = backend,
        .seed = o.seed,
        .reads = o.reads,
        .repeats = o.repeats,
        .page_bytes = o.page_bytes,
        .tier_capacities = .{ .resident = [_]usize{ 16, 1, 1 }, .tiered = [_]usize{ 4, 4, 8 } },
        .payload_sha256 = @as([]const u8, &hex),
        .zig = info.zig_version_string,
        .platform = @tagName(info.os.tag) ++ "/" ++ @tagName(info.cpu.arch),
        .sqlite = std.mem.span(sqlite3_libversion()),
        .revision = revision,
        .workloads = .{ .hot = work[0], .scan = work[1], .mixed = work[2] },
    };
    const json = try std.json.Stringify.valueAlloc(a, record, .{});
    if (std.fs.path.dirname(o.output)) |dir| try ensureDirectory(io, dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = o.output, .data = json });
    _ = puts(try std.fmt.allocPrintSentinel(a, "Saved 3 workloads to {s}", .{o.output}, 0));
}
const usage = "Usage: kv-cache replay [--directory DIR] [--rounds N]\n       kv-cache bench [--reads N] [--repeats N] [--page-bytes N] [--seed N] [--directory DIR] [--output FILE]";
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        _ = puts(usage);
        return;
    }
    if (args.len < 2) return error.ExpectedCommand;
    const replaying = std.mem.eql(u8, args[1], "replay");
    if (!replaying and !std.mem.eql(u8, args[1], "bench")) return error.UnknownCommand;
    var opts = Options{};
    var i: usize = 2;
    while (i < args.len) : (i += 2) {
        const key = args[i];
        if (std.mem.eql(u8, key, "--help")) {
            _ = puts(usage);
            return;
        }
        if (i + 1 == args.len) return error.MissingValue;
        const val = args[i + 1];
        if (std.mem.eql(u8, key, "--directory")) {
            opts.directory = val;
        } else if (replaying) {
            if (!std.mem.eql(u8, key, "--rounds")) return error.UnknownOption;
            opts.rounds = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.eql(u8, key, "--reads")) {
            opts.reads = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.eql(u8, key, "--repeats")) {
            opts.repeats = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.eql(u8, key, "--seed")) {
            opts.seed = try std.fmt.parseInt(u64, val, 10);
        } else if (std.mem.eql(u8, key, "--page-bytes")) {
            opts.page_bytes = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.eql(u8, key, "--output")) {
            opts.output = val;
        } else return error.UnknownOption;
    }
    if (opts.rounds == 0 or opts.reads == 0 or opts.repeats < 2 or opts.page_bytes == 0) return error.InvalidValue;
    if (replaying) try replay(a, init.io, opts) else try benchmark(a, init.io, opts);
}
