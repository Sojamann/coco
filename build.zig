const std = @import("std");

pub fn build(b: *std.Build) void {
    const libgit_object_option = b.option(
        []const u8,
        "libgit2-object",
        "path to the libgit2 object file (should align with -Dlibgit2-version",
    );
    const libgit_version = b.option(
        []const u8,
        "libgit2-version",
        "what version of libgit2 to use",
    ) orelse "v1.7.2";

    var libgit_object: std.Build.LazyPath = undefined;
    if (libgit_object_option) |path| {
        b.getInstallStep().dependOn(&b.addInstallFile(.{ .path = path }, "libgit2.a").step);
        libgit_object = .{ .path = path };
    } else {
        var set_version_cmd = b.addSystemCommand(&.{ "git", "-C", "./libgit2", "checkout" });
        set_version_cmd.addArg(libgit_version);

        var build_libgit_cmd = b.addSystemCommand(&.{"./build-libgit"});
        const generated = build_libgit_cmd.addOutputFileArg("libgit2.a");
        build_libgit_cmd.addArg(libgit_version);
        build_libgit_cmd.step.dependOn(&set_version_cmd.step);
        libgit_object = generated;

        b.getInstallStep().dependOn(&build_libgit_cmd.step);
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "coco",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addObjectFile(libgit_object);
    exe.addIncludePath(.{ .path = "./libgit2/include" });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
