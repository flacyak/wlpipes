//! Ties the Wayland surface, the EGL context, and the frame loop together.
//! Stage 2 draws nothing but a cleared frame; the renderer arrives in stage 3.

const std = @import("std");
const Io = std.Io;

const config = @import("config.zig");
const egl = @import("egl.zig");
const gl = @import("gl/api.zig");
const render = @import("render.zig");
const connection = @import("wl/connection.zig");
const window_mod = @import("wl/window.zig");

/// How long a frame may block waiting on the compositor before we re-check the
/// deadline. Keeps `--max-seconds` responsive without busy-waiting.
const poll_interval_ms = 100;

pub fn run(io: Io, allocator: std.mem.Allocator, cfg: config.Config) !void {
    var conn: connection.Connection = undefined;
    try connection.connect(&conn);
    defer conn.deinit();

    var window: window_mod.Window = undefined;
    try window_mod.create(&conn, &window);
    defer window.deinit();

    var instance = try egl.init(conn.display);
    defer instance.deinit();

    var surface = try egl.createSurface(
        instance,
        window.surface,
        window.width,
        window.height,
    );
    defer surface.deinit(instance);

    try surface.makeCurrent(instance);
    try reportContext(io, instance);

    var renderer = try render.init(allocator);
    defer renderer.deinit();

    try frameLoop(io, &conn, &window, &instance, &surface, &renderer, cfg);
}

/// Draws until the compositor closes the window or the deadline passes.
fn frameLoop(
    io: Io,
    conn: *connection.Connection,
    window: *window_mod.Window,
    instance: *egl.Instance,
    surface: *egl.Surface,
    renderer: *render.Renderer,
    cfg: config.Config,
) !void {
    const started = Io.Timestamp.now(io, clock);
    const deadline = deadlineFrom(io, cfg.max_seconds);

    while (window.running) {
        if (expired(io, deadline)) break;

        if (window.resized) {
            surface.resize(window.width, window.height);
            window.resized = false;
        }

        render.draw(renderer, surface.width, surface.height, secondsSince(io, started));
        try surface.swap(instance.*);
        _ = try connection.waitAndDispatch(conn, poll_interval_ms);
    }
}

fn secondsSince(io: Io, started: Io.Timestamp) f32 {
    const elapsed = started.durationTo(Io.Timestamp.now(io, clock));
    return @as(f32, @floatFromInt(elapsed.nanoseconds)) / std.time.ns_per_s;
}

/// `.awake` is monotonic, so a wall-clock adjustment mid-run cannot cut the
/// deadline short or push it out.
const clock: Io.Clock = .awake;

fn deadlineFrom(io: Io, max_seconds: ?u32) ?Io.Timestamp {
    const seconds = max_seconds orelse return null;
    const ns = @as(i96, seconds) * std.time.ns_per_s;
    return Io.Timestamp.now(io, clock).addDuration(.{ .nanoseconds = ns });
}

fn expired(io: Io, deadline: ?Io.Timestamp) bool {
    const at = deadline orelse return false;
    return Io.Timestamp.now(io, clock).nanoseconds >= at.nanoseconds;
}

fn reportContext(io: Io, instance: egl.Instance) !void {
    var buffer: [512]u8 = undefined;
    var writer: Io.File.Writer = .init(.stdout(), io, &buffer);
    const out = &writer.interface;

    try out.print("renderer    {s}\n", .{gl.getString(gl.c.GL_RENDERER)});
    try out.print("gl version  {s}\n", .{gl.getString(gl.c.GL_VERSION)});
    try out.print("msaa        {s}\n", .{if (instance.multisampled) "4x" else "off"});
    try out.flush();
}
