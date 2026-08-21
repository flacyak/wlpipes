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
        .version => try writeStdout(init.io, "pipes " ++ config.version ++ "\n"),
        .run => |cfg| try run(init.io, arena, cfg),
    }
}

/// Only the windowed backend exists so far; the overlay lands in stage 6.
fn run(io: Io, arena: std.mem.Allocator, cfg: config.Config) !void {
    if (cfg.backend == .overlay) {
        try writeStderr(io, "pipes: the overlay backend is not implemented yet, " ++
            "run with --windowed\n");
        std.process.exit(3);
    }
    try app.run(io, arena, cfg);
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

    try out.print("pipes: {s}\n", .{describe(err)});
    try out.writeAll("Try 'pipes --help'.\n");
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
    _ = @import("demo.zig");
    _ = @import("palette.zig");
    _ = @import("render.zig");
}
