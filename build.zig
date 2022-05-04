const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ralph-agi", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addObjectFile("lib/raylib_mac_4.0_src/libraylib.a");
    
    exe.linkFramework("CoreVideo");
    exe.linkFramework("IOKit");
    exe.linkFramework("Cocoa");
    exe.linkFramework("GLUT");
    exe.linkFramework("OpenGL");

    exe.linkSystemLibrary("c");

    exe.install();

    // const cflags = &[_][]const u8{
    //     "-std=c99",
    //     "-pedantic",
    //     //"-Werror",
    //     "-Wall",
    //     "-Wextra",
    //     "-O0", // No optimizations at all (used for debugging bruh)...later remove this.

    //     // RC: Some build errors are simply because compiler is too strict, need to loosen the error requirements.
    //     "-Wunused-parameter",
    //     //"-Wzero-length-array",
    // };
    
    exe.addIncludeDir("lib");

    // From source.
    exe.addIncludeDir("lib/raylib_mac_4.0_src");

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
