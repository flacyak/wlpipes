//! Command line configuration. Pure: no Wayland, no GL, no allocation.

const std = @import("std");

pub const version = "0.1.0";

pub const Error = error{
    UnknownOption,
    MissingValue,
    InvalidValue,
    UnexpectedPositional,
};

/// Which Wayland surface the screensaver paints onto.
pub const Backend = enum {
    /// A fullscreen `wlr-layer-shell` overlay. The real screensaver.
    overlay,
    /// An ordinary `xdg-shell` window, for development. The compositor keeps
    /// ownership of the keyboard, so a bug here cannot lock you out.
    windowed,
};

pub const Grid = struct {
    x: u16 = 26,
    y: u16 = 20,
    z: u16 = 26,

    pub fn volume(self: Grid) u32 {
        return @as(u32, self.x) * @as(u32, self.y) * @as(u32, self.z);
    }
};

pub const Config = struct {
    backend: Backend = .overlay,
    /// Exit after this many seconds. The escape hatch while developing the
    /// overlay backend, which holds an exclusive keyboard grab.
    max_seconds: ?u32 = null,
    /// Slowly orbit the camera. Off by default: the Win95 camera was static.
    rotate: bool = false,
    grid: Grid = .{},
    /// Milliseconds per pipe segment, kept independent of the display's
    /// refresh rate so growth looks the same on a 60Hz and a 240Hz panel.
    segment_ms: u32 = 60,
    /// Pipe runs drawn before the box is cleared and the scene restarts.
    max_runs: u32 = 12,
    /// Segments a single run may draw before it is capped off.
    max_length: u32 = 100,
    /// Fixed RNG seed, for reproducing a specific scene. Null seeds randomly.
    seed: ?u64 = null,
    /// Percent chance that a turn sprouts a teapot instead of a ball joint.
    /// The original hid one among the pipes; zero turns the joke off.
    teapot_percent: u32 = 2,
};

/// What `parse` decided the process should do.
pub const Outcome = union(enum) {
    run: Config,
    help,
    version,
};

/// Parses argv, excluding the program name at index 0.
pub fn parse(args: []const []const u8) Error!Outcome {
    var config: Config = .{};
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (eqlAny(arg, &.{ "-h", "--help" })) return .help;
        if (eqlAny(arg, &.{ "-V", "--version" })) return .version;
        if (applyFlag(&config, arg)) continue;

        const name = optionName(arg) orelse return Error.UnexpectedPositional;
        i += 1;
        if (i >= args.len) return Error.MissingValue;
        try applyOption(&config, name, args[i]);
    }
    return .{ .run = config };
}

/// Handles the options that carry no value. Returns whether `arg` was one.
fn applyFlag(config: *Config, arg: []const u8) bool {
    if (eqlAny(arg, &.{ "-w", "--windowed" })) {
        config.backend = .windowed;
        return true;
    }
    if (std.mem.eql(u8, arg, "--overlay")) {
        config.backend = .overlay;
        return true;
    }
    if (std.mem.eql(u8, arg, "--rotate")) {
        config.rotate = true;
        return true;
    }
    return false;
}

/// Handles the options that take the following argument as their value.
fn applyOption(config: *Config, name: []const u8, value: []const u8) Error!void {
    if (std.mem.eql(u8, name, "max-seconds")) {
        config.max_seconds = try parseInt(u32, value, 1, 86_400);
    } else if (std.mem.eql(u8, name, "grid")) {
        config.grid = try parseGrid(value);
    } else if (std.mem.eql(u8, name, "speed")) {
        config.segment_ms = try parseInt(u32, value, 1, 10_000);
    } else if (std.mem.eql(u8, name, "max-runs")) {
        config.max_runs = try parseInt(u32, value, 1, 1_000);
    } else if (std.mem.eql(u8, name, "max-length")) {
        config.max_length = try parseInt(u32, value, 1, 100_000);
    } else if (std.mem.eql(u8, name, "seed")) {
        config.seed = try parseInt(u64, value, 0, std.math.maxInt(u64));
    } else if (std.mem.eql(u8, name, "teapot")) {
        config.teapot_percent = try parseInt(u32, value, 0, 100);
    } else {
        return Error.UnknownOption;
    }
}

/// Parses `WxHxD`, e.g. `26x20x26`.
fn parseGrid(value: []const u8) Error!Grid {
    var parts = std.mem.splitScalar(u8, value, 'x');
    var dims: [3]u16 = undefined;

    for (&dims) |*dim| {
        const part = parts.next() orelse return Error.InvalidValue;
        dim.* = try parseInt(u16, part, 2, 512);
    }
    if (parts.next() != null) return Error.InvalidValue;

    return .{ .x = dims[0], .y = dims[1], .z = dims[2] };
}

fn parseInt(comptime T: type, value: []const u8, min: T, max: T) Error!T {
    const parsed = std.fmt.parseInt(T, value, 10) catch return Error.InvalidValue;
    if (parsed < min or parsed > max) return Error.InvalidValue;
    return parsed;
}

/// Strips the leading dashes from a long or short option, or returns null for
/// anything that is not shaped like an option at all.
fn optionName(arg: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, arg, "--") and arg.len > 2) return arg[2..];
    if (arg.len == 2 and arg[0] == '-' and arg[1] != '-') return arg[1..];
    return null;
}

fn eqlAny(arg: []const u8, candidates: []const []const u8) bool {
    for (candidates) |candidate| {
        if (std.mem.eql(u8, arg, candidate)) return true;
    }
    return false;
}

pub const usage_text =
    \\wlpipes - the Windows 95 3D Pipes screensaver, for Wayland
    \\
    \\Usage: wlpipes [options]
    \\
    \\Surface:
    \\  -w, --windowed         Draw into an ordinary window instead of a
    \\                         fullscreen overlay. Use this while developing:
    \\                         the compositor keeps the keyboard.
    \\      --overlay          Fullscreen layer-shell overlay (default).
    \\
    \\Scene:
    \\      --grid WxHxD       Cells in the box (default 26x20x26).
    \\      --speed MS         Milliseconds per pipe segment (default 60).
    \\      --max-runs N       Pipe runs before the box clears (default 12).
    \\      --max-length N     Segments before a run is capped (default 100).
    \\      --rotate           Slowly orbit the camera (default off).
    \\      --seed N           Fixed RNG seed, to reproduce a scene.
    \\      --teapot PERCENT   Chance a turn sprouts a teapot (default 2,
    \\                         0 disables the easter egg).
    \\
    \\Lifecycle:
    \\      --max-seconds N    Exit after N seconds.
    \\  -h, --help             Show this help.
    \\  -V, --version          Show the version.
    \\
;

const testing = std.testing;

/// Unwraps a successful parse, failing the test on help/version/error.
fn expectRun(args: []const []const u8) !Config {
    return switch (try parse(args)) {
        .run => |config| config,
        else => error.TestUnexpectedResult,
    };
}

test "defaults" {
    const config = try expectRun(&.{});
    try testing.expectEqual(Backend.overlay, config.backend);
    try testing.expectEqual(@as(?u32, null), config.max_seconds);
    try testing.expectEqual(false, config.rotate);
    try testing.expectEqual(@as(u32, 60), config.segment_ms);
    try testing.expectEqual(@as(u32, 26), config.grid.x);
}

test "flags" {
    try testing.expectEqual(Backend.windowed, (try expectRun(&.{"-w"})).backend);
    try testing.expectEqual(Backend.windowed, (try expectRun(&.{"--windowed"})).backend);
    try testing.expectEqual(true, (try expectRun(&.{"--rotate"})).rotate);
}

test "later flags win" {
    const config = try expectRun(&.{ "--windowed", "--overlay" });
    try testing.expectEqual(Backend.overlay, config.backend);
}

test "value options" {
    const config = try expectRun(&.{
        "--max-seconds", "30",
        "--speed",       "16",
        "--max-runs",    "4",
        "--max-length",  "80",
        "--seed",        "12345",
    });
    try testing.expectEqual(@as(?u32, 30), config.max_seconds);
    try testing.expectEqual(@as(u32, 16), config.segment_ms);
    try testing.expectEqual(@as(u32, 4), config.max_runs);
    try testing.expectEqual(@as(u32, 80), config.max_length);
    try testing.expectEqual(@as(?u64, 12345), config.seed);
}

test "grid parsing" {
    const grid = (try expectRun(&.{ "--grid", "10x8x12" })).grid;
    try testing.expectEqual(@as(u16, 10), grid.x);
    try testing.expectEqual(@as(u16, 8), grid.y);
    try testing.expectEqual(@as(u16, 12), grid.z);
    try testing.expectEqual(@as(u32, 960), grid.volume());
}

test "grid rejects malformed values" {
    for ([_][]const u8{ "10x8", "10x8x12x4", "10x8xz", "", "xxx" }) |value| {
        try testing.expectError(Error.InvalidValue, parse(&.{ "--grid", value }));
    }
}

test "help and version short-circuit" {
    for ([_][]const u8{ "-h", "--help" }) |arg| {
        try testing.expectEqual(Outcome.help, try parse(&.{arg}));
    }
    for ([_][]const u8{ "-V", "--version" }) |arg| {
        try testing.expectEqual(Outcome.version, try parse(&.{arg}));
    }
}

test "help wins over a later broken option" {
    try testing.expectEqual(Outcome.help, try parse(&.{ "--help", "--nonsense" }));
}

test "rejects unknown options" {
    try testing.expectError(Error.UnknownOption, parse(&.{ "--nope", "1" }));
}

test "rejects a missing value" {
    try testing.expectError(Error.MissingValue, parse(&.{"--speed"}));
}

test "rejects positionals" {
    try testing.expectError(Error.UnexpectedPositional, parse(&.{"stray"}));
}

test "rejects out of range values" {
    try testing.expectError(Error.InvalidValue, parse(&.{ "--speed", "0" }));
    try testing.expectError(Error.InvalidValue, parse(&.{ "--max-seconds", "0" }));
    try testing.expectError(Error.InvalidValue, parse(&.{ "--grid", "1x8x12" }));
    try testing.expectError(Error.InvalidValue, parse(&.{ "--speed", "-5" }));
}
