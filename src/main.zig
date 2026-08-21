const std = @import("std");
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
        .run => |cfg| try run(init.io, cfg),
    }
}

/// Placeholder until the Wayland backend lands. Reports the scene it would
/// draw so the configuration is verifiable end to end today.
fn run(io: Io, cfg: config.Config) !void {
    var buffer: [512]u8 = undefined;
    var writer: Io.File.Writer = .init(.stdout(), io, &buffer);
    const out = &writer.interface;

    try out.print("backend     {t}\n", .{cfg.backend});
    try out.print("grid        {d}x{d}x{d} ({d} cells)\n", .{
        cfg.grid.x, cfg.grid.y, cfg.grid.z, cfg.grid.volume(),
    });
    try out.print("segment     {d}ms\n", .{cfg.segment_ms});
    try out.print("runs        {d} of up to {d} segments\n", .{ cfg.max_runs, cfg.max_length });
    try out.print("rotate      {}\n", .{cfg.rotate});
    try out.print("not yet drawing anything: no Wayland backend\n", .{});
    try out.flush();
}

fn writeStdout(io: Io, text: []const u8) !void {
    var buffer: [64]u8 = undefined;
    var writer: Io.File.Writer = .init(.stdout(), io, &buffer);
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
    _ = config;
}
