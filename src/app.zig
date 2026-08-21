//! Ties the Wayland surface, the EGL context, and the frame loop together.
//! Stage 2 draws nothing but a cleared frame; the renderer arrives in stage 3.

const std = @import("std");
const Io = std.Io;

const config = @import("config.zig");
const egl = @import("egl.zig");
const gl = @import("gl/api.zig");
const render = @import("render.zig");
const camera_mod = @import("camera.zig");
const grid_mod = @import("sim/grid.zig");
const scene = @import("scene.zig");
const walk = @import("sim/walk.zig");
const math = @import("math.zig");
const connection = @import("wl/connection.zig");
const window_mod = @import("wl/window.zig");
const input_mod = @import("wl/input.zig");
const overlay = @import("overlay.zig");
const layer = @import("wl/layer.zig");

/// How long a frame may block waiting on the compositor before we re-check the
/// deadline. Keeps `--max-seconds` responsive without busy-waiting.
const poll_interval_ms = 100;

/// Entry point for the windowed development backend.
pub fn runWindowed(io: Io, allocator: std.mem.Allocator, cfg: config.Config) !void {
    var conn: connection.Connection = undefined;
    try connection.connect(&conn);
    defer conn.deinit();

    var window: window_mod.Window = undefined;
    try window_mod.create(&conn, &window);
    defer window.deinit();

    var instance = try egl.init(conn.display);
    defer instance.deinit();

    var surface = try bindSurface(io, instance, &window);
    defer surface.deinit(instance);

    var renderer = try render.init(allocator);
    defer renderer.deinit();

    var walker = try createWalker(io, allocator, cfg);
    defer walker.grid.deinit(allocator);

    try frameLoop(io, &conn, &window, &instance, &surface, &renderer, &walker, cfg);
}

/// Gives the window an EGL drawable and makes it current, so every GL call
/// after this point has a context to land in.
fn bindSurface(io: Io, instance: egl.Instance, window: *window_mod.Window) !egl.Surface {
    const surface = try egl.createSurface(
        instance,
        window.surface,
        window.width,
        window.height,
    );
    errdefer {
        var mutable = surface;
        mutable.deinit(instance);
    }

    try surface.makeCurrent(instance);
    try reportContext(io, instance);
    return surface;
}

/// Draws until the compositor closes the window or the deadline passes.
fn frameLoop(
    io: Io,
    conn: *connection.Connection,
    window: *window_mod.Window,
    instance: *egl.Instance,
    surface: *egl.Surface,
    renderer: *render.Renderer,
    walker: *walk.Walker,
    cfg: config.Config,
) !void {
    const started = Io.Timestamp.now(io, clock);
    var next_tick: f32 = 0;
    const deadline = deadlineFrom(io, cfg.max_seconds);

    while (window.running) {
        if (expired(io, deadline)) break;

        // Nothing to do until the compositor says a frame is due. The wait has
        // a timeout only so the deadline stays enforceable while it is silent.
        if (!window.frame_ready) {
            _ = try connection.waitAndDispatch(conn, poll_interval_ms);
            continue;
        }
        window.frame_ready = false;

        if (window.resized) {
            surface.resize(window.width, window.height);
            window.resized = false;
        }

        const seconds = secondsSince(io, started);
        try growPipes(renderer, walker, cfg, seconds, &next_tick);

        const camera = frameCamera(surface.*, cfg, seconds);
        render.draw(renderer, surface.width, surface.height, camera);

        // Requested before the swap so it is committed with the buffer.
        window_mod.requestFrame(window);
        try surface.swap(instance.*);
    }
}

/// Seeds from the clock unless --seed pins it, so each launch differs.
fn createWalker(io: Io, allocator: std.mem.Allocator, cfg: config.Config) !walk.Walker {
    const seed = cfg.seed orelse @as(u64, @bitCast(@as(i64, @truncate(
        Io.Timestamp.now(io, .real).nanoseconds,
    ))));
    prng = std.Random.DefaultPrng.init(seed);

    const grid = try grid_mod.create(allocator, .{ cfg.grid.x, cfg.grid.y, cfg.grid.z });
    return walk.create(grid, prng.random(), .{
        .max_runs = cfg.max_runs,
        .max_length = cfg.max_length,
    });
}

/// Lives here rather than inside the Walker because std.Random holds a pointer
/// to its state, which must outlive every tick.
var prng: std.Random.DefaultPrng = undefined;

/// Advances the simulation on a fixed timestep, independent of the display's
/// refresh rate: growth must look the same on a 60Hz and a 240Hz panel.
///
/// Catches up at most a few ticks per frame, so a stalled frame does not make
/// the pipes lurch forward all at once.
fn growPipes(
    renderer: *render.Renderer,
    walker: *walk.Walker,
    cfg: config.Config,
    seconds: f32,
    next_tick: *f32,
) !void {
    const interval = @as(f32, @floatFromInt(cfg.segment_ms)) / 1000.0;
    const max_catch_up = 4;

    var ticks: usize = 0;
    while (seconds >= next_tick.* and ticks < max_catch_up) : (ticks += 1) {
        try scene.apply(renderer, walker.tick(), walker.grid.dims);
        next_tick.* += interval;
    }
    if (seconds >= next_tick.*) next_tick.* = seconds + interval;
}

/// Radians per second of camera drift when --rotate is on.
const orbit_speed: f32 = 0.15;

pub fn frameCamera(surface: egl.Surface, cfg: config.Config, seconds: f32) camera_mod.Camera {
    const extent = math.Vec3.init(
        @floatFromInt(cfg.grid.x),
        @floatFromInt(cfg.grid.y),
        @floatFromInt(cfg.grid.z),
    );
    const aspect = @as(f32, @floatFromInt(surface.width)) /
        @as(f32, @floatFromInt(@max(surface.height, 1)));
    const yaw = if (cfg.rotate) seconds * orbit_speed else 0.0;
    return camera_mod.frame(extent, aspect, yaw);
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


/// Entry point for the real screensaver: a fullscreen overlay on every monitor.
pub fn runOverlay(io: Io, allocator: std.mem.Allocator, cfg: config.Config) !void {
    var conn: connection.Connection = undefined;
    try connection.connect(&conn);
    defer conn.deinit();
    _ = try conn.requireLayerShell();

    var instance = try egl.init(conn.display);
    defer instance.deinit();

    var input: input_mod.Input = .{};
    defer input.deinit();
    if (conn.globals.seat) |seat| input_mod.watch(&input, seat);

    var panels: overlay.Panels = .{ .allocator = allocator };
    defer panels.deinit(instance);
    try overlay.reconcile(&panels, &conn, instance);

    // The renderer compiles its shader immediately, so a context must already
    // be current. Unlike a window, a layer surface has no size until the
    // compositor configures it, so there is nothing to make current until then.
    try awaitFirstDrawable(&conn, &panels, instance);

    var renderer = try render.init(allocator);
    defer renderer.deinit();
    var walker = try createWalker(io, allocator, cfg);
    defer walker.grid.deinit(allocator);

    try overlayLoop(io, &conn, &panels, &instance, &renderer, &walker, &input, cfg);
}

/// Draws until any input arrives, the compositor takes the surfaces away, or
/// the deadline passes.
///
/// Every one of those exits matters: this loop is holding an exclusive
/// keyboard grab over a fullscreen surface, so failing to leave it strands the
/// user in a session they cannot type into.
fn overlayLoop(
    io: Io,
    conn: *connection.Connection,
    panels: *overlay.Panels,
    instance: *egl.Instance,
    renderer: *render.Renderer,
    walker: *walk.Walker,
    input: *input_mod.Input,
    cfg: config.Config,
) !void {
    const started = Io.Timestamp.now(io, clock);
    const deadline = deadlineFrom(io, cfg.max_seconds);
    var next_tick: f32 = 0;

    while (!input.dismissed and panels.anyLive()) {
        if (expired(io, deadline)) break;

        const seconds = secondsSince(io, started);
        input.accept_motion = seconds >= input_mod.settle_seconds;

        if (conn.outputs.changed) try overlay.reconcile(panels, conn, instance.*);
        try growPipes(renderer, walker, cfg, seconds, &next_tick);

        const yaw = if (cfg.rotate) seconds * orbit_speed else 0.0;
        _ = try overlay.drawPanels(panels, instance.*, renderer, cfg, yaw);

        // Blocks until a frame callback or an input event arrives. The timeout
        // only bounds how long the deadline check can be delayed.
        _ = try connection.waitAndDispatch(conn, poll_interval_ms);
    }
}


/// Waits for the first monitor to report its size, then makes its drawable
/// current so the renderer has somewhere to compile into.
///
/// Bounded rather than open ended: a compositor that never configures us must
/// fail loudly instead of hanging with an overlay half-mapped.
fn awaitFirstDrawable(
    conn: *connection.Connection,
    panels: *overlay.Panels,
    instance: egl.Instance,
) !void {
    const max_attempts = 100;
    var attempts: usize = 0;

    while (attempts < max_attempts) : (attempts += 1) {
        for (panels.items.items) |*panel| {
            if (panel.closed or !panel.configured) continue;
            try layer.syncDrawable(panel, instance);
            const surface = panel.egl_surface orelse continue;
            try surface.makeCurrent(instance);
            return;
        }
        _ = try connection.waitAndDispatch(conn, poll_interval_ms);
    }
    return error.NoDrawableConfigured;
}
