const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wayland = generateWaylandBindings(b);

    const exe = b.addExecutable(.{
        .name = "wlpipes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addImport("wayland", wayland);
    linkGraphicsLibraries(exe.root_module);
    b.installArtifact(exe);

    addRunStep(b, exe);
    addTestStep(b, target, optimize, wayland);
}

/// Runs wayland-scanner over the protocols we speak and exposes the result as
/// the "wayland" module.
fn generateWaylandBindings(b: *std.Build) *std.Build.Module {
    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    // Vendored rather than depending on the wlr-protocols package, so the repo
    // builds standalone. xdg-shell above is not optional even for the overlay:
    // the layer shell xml references xdg_popup.
    scanner.addCustomProtocol(b.path("protocol/wlr-layer-shell-unstable-v1.xml"));

    // Pass the highest version we actually implement; anything newer in the
    // protocol xml is left ungenerated so newer wayland-protocols stays safe.
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_output", 4);
    scanner.generate("xdg_wm_base", 3);
    scanner.generate("zwlr_layer_shell_v1", 4);

    return b.createModule(.{ .root_source_file = scanner.result });
}

fn linkGraphicsLibraries(module: *std.Build.Module) void {
    module.linkSystemLibrary("wayland-client", .{});
    module.linkSystemLibrary("wayland-egl", .{});
    module.linkSystemLibrary("EGL", .{});
    module.linkSystemLibrary("GLESv2", .{});
}

/// `zig build run -- <args>` builds, installs, then runs the screensaver.
fn addRunStep(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the screensaver");
    run_step.dependOn(&run_cmd.step);
}

/// `zig build test` runs every `test` block reachable from src/main.zig.
fn addTestStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    wayland: *std.Build.Module,
) void {
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("wayland", wayland);
    linkGraphicsLibraries(module);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = module })).step);
}
