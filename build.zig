const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const os = target.result.os.tag;
    const version = b.option([]const u8, "version", "Version string shown in the app") orelse "1.0.0";

    if (os != .linux and os != .windows) @panic("WooferSoundPad supports Linux and Windows only");

    // ── raylib, compiled straight from vendor/ ───────────────────────────────
    // Built without rmodels and raudio: all audio goes through miniaudio
    // (src/c/woof_audio.c). raylib's own build.zig already requires Zig 0.17.
    const raylib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    raylib_mod.addCMacro("PLATFORM_DESKTOP_GLFW", "");
    raylib_mod.addCMacro("GRAPHICS_API_OPENGL_33", "");
    raylib_mod.addCMacro("SUPPORT_MODULE_RMODELS", "0");
    raylib_mod.addCMacro("SUPPORT_MODULE_RAUDIO", "0");
    raylib_mod.addCMacro("SUPPORT_FILEFORMAT_JPG", "1"); // thumbnails
    raylib_mod.addIncludePath(b.path("vendor/raylib"));
    raylib_mod.addIncludePath(b.path("vendor/raylib/platforms"));
    raylib_mod.addIncludePath(b.path("vendor/raylib/external/glfw/include"));

    if (os == .linux) {
        // Avoid _GNU_SOURCE: on glibc >= 2.38 it redirects sscanf/strtol to
        // __isoc23_* symbols and the binary stops running on older distros
        raylib_mod.addCMacro("_DEFAULT_SOURCE", "");
        // X11 also covers Wayland sessions through XWayland. GLFW loads the
        // X11 extension libraries and libGL with dlopen, so nothing to link here.
        raylib_mod.addCMacro("_GLFW_X11", "");
    } else {
        raylib_mod.addCMacro("_GNU_SOURCE", "");
    }

    raylib_mod.addCSourceFiles(.{
        .root = b.path("vendor/raylib"),
        .files = &.{ "rcore.c", "rshapes.c", "rtextures.c", "rtext.c", "rglfw.c" },
        .flags = &.{"-std=c99"},
    });

    const raylib = b.addLibrary(.{
        .name = "raylib",
        .linkage = .static,
        .root_module = raylib_mod,
    });

    // ── C bindings: raylib + rlgl + our miniaudio wrapper + tinyfiledialogs ──
    const c_bindings = b.addTranslateC(.{
        .root_source_file = b.path("src/c/bindings.h"),
        .target = target,
        .optimize = optimize,
    });
    c_bindings.addIncludePath(b.path("vendor/raylib"));
    c_bindings.addIncludePath(b.path("vendor/tinyfiledialogs"));
    c_bindings.addIncludePath(b.path("src/c"));

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);
    build_options.addOption([]const u8, "repo_url", b.option([]const u8, "repo-url", "Project page linked from the app") orelse "https://github.com/RshaCuDeVidro/WooferSoundPad");

    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = if (optimize == .debug) null else true,
        .imports = &.{
            .{ .name = "c", .module = c_bindings.createModule() },
            .{ .name = "assets", .module = assets_mod },
        },
    });
    exe_mod.addOptions("build_options", build_options);
    exe_mod.addIncludePath(b.path("vendor/raylib"));
    exe_mod.addIncludePath(b.path("vendor/tinyfiledialogs"));
    exe_mod.addIncludePath(b.path("src/c"));
    exe_mod.addCSourceFiles(.{
        .root = b.path("src/c"),
        .files = &.{ "woof_audio.c", "woof_http.c" },
        .flags = &.{"-std=c99"},
    });
    exe_mod.addCSourceFiles(.{
        .root = b.path("vendor/tinyfiledialogs"),
        .files = &.{"tinyfiledialogs.c"},
        .flags = &.{"-std=c99"},
    });

    // System libraries go on the executable: on a static library they would be
    // stuffed into the .a archive and lld complains.
    if (os == .linux) {
        // miniaudio loads PulseAudio/ALSA/JACK at runtime with dlopen; X11 is
        // used directly for global hotkeys
        for ([_][]const u8{ "X11", "dl", "pthread", "m" }) |lib| {
            exe_mod.linkSystemLibrary(lib, .{});
        }
    } else {
        for ([_][]const u8{ "opengl32", "winmm", "gdi32", "user32", "shell32", "ole32", "comdlg32", "ws2_32" }) |lib| {
            exe_mod.linkSystemLibrary(lib, .{});
        }
        exe_mod.addWin32ResourceFile(.{ .file = b.path("assets/windows/app.rc") });
    }
    exe_mod.linkLibrary(raylib);

    const exe = b.addExecutable(.{
        .name = "WooferSoundPad",
        .root_module = exe_mod,
    });
    // No console window on Windows outside of debug builds
    if (os == .windows and optimize != .debug) exe.subsystem = .windows;
    b.installArtifact(exe);

    const run_step = b.step("run", "Run WooferSoundPad");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const tests = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run unit tests (parsers, config)");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
