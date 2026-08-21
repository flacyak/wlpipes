const std = @import("std");
const app = @import("app.zig");
const config = @import("config.zig");

const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const outcome = config.parse(args[1..]) catch |err| {
        try reportUsageError(init.io, err);
        // A usage error is the user's typo, not a crash: exit quietly rather
        // than returning an error and dumping a stack trace at them.
        std.process.exit(2);
    };

    switch (outcome) {
        .help => try writeStdout(init.io, config.usage_text),
        .version => try writeStdout(init.io, "wlpipes " ++ config.version ++ "\n"),
        .run => |cfg| try run(init.io, arena, cfg),
    }
}

fn run(io: Io, arena: std.mem.Allocator, cfg: config.Config) !void {
    runBackend(io, arena, cfg) catch |err| {
        // hypridle launches this; a Zig stack trace in the journal helps
        // nobody. Say what went wrong in one line and leave.
        try reportRuntimeError(io, err);
        std.process.exit(1);
    };
}

fn runBackend(io: Io, arena: std.mem.Allocator, cfg: config.Config) !void {
    switch (cfg.backend) {
        .windowed => try app.runWindowed(io, arena, cfg),
        .overlay => try app.runOverlay(io, arena, cfg),
    }
}

fn reportRuntimeError(io: Io, err: anyerror) !void {
    var buffer: [256]u8 = undefined;
    var writer: Io.File.Writer = .init(.stderr(), io, &buffer);
    try writer.interface.print("wlpipes: {s}\n", .{describeRuntime(err)});
    try writer.interface.flush();
}

fn describeRuntime(err: anyerror) []const u8 {
    return switch (err) {
        error.ConnectFailed => "cannot reach a Wayland compositor (is WAYLAND_DISPLAY set?)",
        error.NoLayerShell => "this compositor has no wlr-layer-shell; try --windowed",
        error.NoCompositor, error.NoWmBase => "the compositor is missing a protocol we need",
        error.NoDrawableConfigured => "the compositor never gave our overlay a size",
        error.CompileFailed, error.LinkFailed => "the GLES shader failed to build",
        error.NoDisplay, error.InitFailed, error.NoConfig, error.NoContext =>
            "could not create an OpenGL ES context",
        else => @errorName(err),
    };
}

fn writeStdout(io: Io, text: []const u8) !void {
    try writeTo(.stdout(), io, text);
}

fn writeStderr(io: Io, text: []const u8) !void {
    try writeTo(.stderr(), io, text);
}

fn writeTo(file: Io.File, io: Io, text: []const u8) !void {
    var buffer: [128]u8 = undefined;
    var writer: Io.File.Writer = .init(file, io, &buffer);
    try writer.interface.writeAll(text);
    try writer.interface.flush();
}

fn reportUsageError(io: Io, err: config.Error) !void {
    var buffer: [256]u8 = undefined;
    var writer: Io.File.Writer = .init(.stderr(), io, &buffer);
    const out = &writer.interface;

    try out.print("wlpipes: {s}\n", .{describe(err)});
    try out.writeAll("Try 'wlpipes --help'.\n");
    try out.flush();
}

fn describe(err: config.Error) []const u8 {
    return switch (err) {
        error.UnknownOption => "unknown option",
        error.MissingValue => "option is missing its value",
        error.InvalidValue => "option value is out of range or malformed",
        error.UnexpectedPositional => "unexpected argument",
    };
}

test {
    _ = app;
    _ = config;
    _ = @import("math.zig");
    _ = @import("mesh.zig");
    _ = @import("camera.zig");
    _ = @import("gl/instances.zig");
    _ = @import("scene.zig");
    _ = @import("teapot.zig");
    _ = @import("overlay.zig");
    _ = @import("wl/input.zig");
    _ = @import("palette.zig");
    _ = @import("sim/grid.zig");
    _ = @import("sim/walk.zig");
    _ = @import("render.zig");
}
