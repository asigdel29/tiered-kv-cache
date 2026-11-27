//! Build the native library, executable, and cache tests with system SQLite.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options: std.Build.Module.CreateOptions = .{ .target = target, .optimize = optimize, .link_libc = true };
    const cli = b.createModule(options);
    cli.root_source_file = b.path("src/main.zig");
    cli.linkSystemLibrary("sqlite3", .{});
    b.installArtifact(b.addExecutable(.{ .name = "kv-cache", .root_module = cli }));
    const abi = b.createModule(options);
    abi.root_source_file = b.path("src/abi.zig");
    abi.linkSystemLibrary("sqlite3", .{});
    b.installArtifact(b.addLibrary(.{ .name = "tieredkv", .linkage = .dynamic, .root_module = abi }));
    const core = b.addModule("tiered-cache", options);
    core.root_source_file = b.path("src/cache.zig");
    core.linkSystemLibrary("sqlite3", .{});
    b.step("test", "Run cache tests").dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = core })).step);
}
