//! The Wayland display connection and the globals we bind from its registry.

const std = @import("std");
const posix = std.posix;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

pub const Error = error{
    ConnectFailed,
    RoundtripFailed,
    DispatchFailed,
    FlushFailed,
    NoCompositor,
    NoWmBase,
};

/// Globals bound from the registry. Optional while the registry is still being
/// enumerated; `require` turns them into a checked, non-optional set.
const Bound = struct {
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
};

pub const Globals = struct {
    compositor: *wl.Compositor,
    wm_base: *xdg.WmBase,
};

pub const Connection = struct {
    display: *wl.Display,
    registry: *wl.Registry,
    globals: Globals,
    bound: Bound,

    pub fn deinit(self: *Connection) void {
        self.globals.wm_base.destroy();
        self.globals.compositor.destroy();
        self.registry.destroy();
        self.display.disconnect();
    }
};

/// Connects to $WAYLAND_DISPLAY and binds every global we need, failing if the
/// compositor does not offer one of them.
pub fn connect(conn: *Connection) Error!void {
    conn.display = try wl.Display.connect(null);
    errdefer conn.display.disconnect();

    conn.registry = conn.display.getRegistry() catch return Error.ConnectFailed;
    errdefer conn.registry.destroy();

    conn.bound = .{};
    conn.registry.setListener(*Bound, onRegistryEvent, &conn.bound);
    if (conn.display.roundtrip() != .SUCCESS) return Error.RoundtripFailed;

    conn.globals = try require(conn.bound);
}

fn require(bound: Bound) Error!Globals {
    return .{
        .compositor = bound.compositor orelse return Error.NoCompositor,
        .wm_base = bound.wm_base orelse return Error.NoWmBase,
    };
}

fn onRegistryEvent(registry: *wl.Registry, event: wl.Registry.Event, bound: *Bound) void {
    switch (event) {
        .global => |global| bindGlobal(registry, global, bound),
        .global_remove => {},
    }
}

/// Binds one advertised global if it is one we care about. Version numbers are
/// the highest we implement, matching what build.zig asked the scanner for.
const Global = @FieldType(wl.Registry.Event, "global");

fn bindGlobal(registry: *wl.Registry, global: Global, bound: *Bound) void {
    if (matches(global.interface, wl.Compositor.interface.name)) {
        bound.compositor = registry.bind(global.name, wl.Compositor, 4) catch null;
    } else if (matches(global.interface, xdg.WmBase.interface.name)) {
        bound.wm_base = registry.bind(global.name, xdg.WmBase, 3) catch null;
    }
}

fn matches(advertised: [*:0]const u8, wanted: [*:0]const u8) bool {
    return std.mem.orderZ(u8, advertised, wanted) == .eq;
}

/// Outcome of one turn of the event loop.
pub const Wake = enum { events, timeout };

/// Blocks until the compositor sends something or `timeout_ms` elapses.
///
/// This is the full libwayland read dance rather than a bare `dispatch`,
/// because a plain `dispatch` blocks with no timeout and the screensaver needs
/// to honour `--max-seconds` even while the compositor is silent.
pub fn waitAndDispatch(conn: *Connection, timeout_ms: i32) Error!Wake {
    const display = conn.display;

    // Events already queued locally need no trip through poll().
    while (!display.prepareRead()) {
        if (display.dispatchPending() != .SUCCESS) return Error.DispatchFailed;
    }

    flushAll(display) catch |err| {
        display.cancelRead();
        return err;
    };

    if (!try pollReadable(display.getFd(), timeout_ms)) {
        display.cancelRead();
        return .timeout;
    }

    if (display.readEvents() != .SUCCESS) return Error.DispatchFailed;
    if (display.dispatchPending() != .SUCCESS) return Error.DispatchFailed;
    return .events;
}

/// Drains the outgoing buffer, tolerating a full socket by waiting for it to
/// drain rather than treating back-pressure as an error.
fn flushAll(display: *wl.Display) Error!void {
    while (true) {
        switch (display.flush()) {
            .SUCCESS => return,
            .AGAIN => _ = try pollWritable(display.getFd()),
            else => return Error.FlushFailed,
        }
    }
}

/// Returns whether the fd became readable before the timeout. A negative
/// timeout blocks indefinitely.
fn pollReadable(fd: c_int, timeout_ms: i32) Error!bool {
    var fds = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};
    const ready = posix.poll(&fds, timeout_ms) catch return Error.DispatchFailed;
    return ready > 0;
}

fn pollWritable(fd: c_int) Error!bool {
    var fds = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.OUT, .revents = 0 }};
    const ready = posix.poll(&fds, -1) catch return Error.FlushFailed;
    return ready > 0;
}
