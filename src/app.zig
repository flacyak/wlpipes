//! Ties the Wayland surface, the EGL context, and the frame loop together.
//! Stage 2 draws nothing but a cleared frame; the renderer arrives in stage 3.

const std = @import("std");
const Io = std.Io;

const config = @import("config.zig");
const egl = @import("egl.zig");
const gl = @import("gl/api.zig");
const connection = @import("wl/connection.zig");
const window_mod = @import("wl/window.zig");

/// How long a frame may block waiting on the compositor before we re-check the
/// deadline. Keeps `--max-seconds` responsive without busy-waiting.
const poll_interval_ms = 100;

pub fn run(io: Io, cfg: config.Config) !void {
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
    try frameLoop(io, &conn, &window, &instance, &surface, cfg);
}

/// Draws until the compositor closes the window or the deadline passes.
fn frameLoop(
    io: Io,
    conn: *connection.Connection,
    window: *window_mod.Window,
    instance: *egl.Instance,
    surface: *egl.Surface,
    cfg: config.Config,
) !void {
    const deadline = deadlineFrom(io, cfg.max_seconds);

    while (window.running) {
        if (expired(io, deadline)) break;

        if (window.resized) {
            surface.resize(window.width, window.height);
            window.resized = false;
        }

        drawFrame(surface.width, surface.height);
        try surface.swap(instance.*);
        _ = try connection.waitAndDispatch(conn, poll_interval_ms);
    }
}

/// Stage 2 has nothing to draw yet, so the frame is the black the pipes will
/// later sit against. Proves the context, the swap chain and the resize path.
fn drawFrame(width: u31, height: u31) void {
    gl.c.glViewport(0, 0, width, height);
    gl.c.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.c.glClear(gl.c.GL_COLOR_BUFFER_BIT | gl.c.GL_DEPTH_BUFFER_BIT);
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
