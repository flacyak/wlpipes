//! The Wayland display connection and the globals we bind from its registry.

const std = @import("std");
const posix = std.posix;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

pub const Error = error{
    ConnectFailed,
    RoundtripFailed,
    DispatchFailed,
    FlushFailed,
    NoCompositor,
    NoWmBase,
    NoLayerShell,
};

/// More monitors than anyone plugs in, and a fixed cap keeps the registry
/// listener allocation-free: it cannot fail partway through binding.
pub const max_outputs = 16;

/// One connected monitor. `name` is the registry name, which is what
/// global_remove reports when the monitor goes away.
pub const Output = struct {
    name: u32,
    proxy: *wl.Output,
};

/// Globals bound from the registry. Optional while the registry is still being
/// enumerated; `require` turns them into a checked, non-optional set.
const Bound = struct {
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
    layer_shell: ?*zwlr.LayerShellV1 = null,
    seat: ?*wl.Seat = null,
};

pub const Globals = struct {
    compositor: *wl.Compositor,
    wm_base: *xdg.WmBase,
    /// Absent on compositors without wlr-layer-shell; only the overlay
    /// backend needs it, so connecting still succeeds without it.
    layer_shell: ?*zwlr.LayerShellV1,
    seat: ?*wl.Seat,
};

/// Monitors currently advertised. Kept here because the registry listener is
/// the only thing that learns about hotplug; the overlay reconciles against it.
pub const Outputs = struct {
    entries: [max_outputs]Output = undefined,
    len: usize = 0,
    /// Raised whenever a monitor appears or disappears, so the overlay knows
    /// to add or drop a surface.
    changed: bool = false,

    pub fn items(self: *const Outputs) []const Output {
        return self.entries[0..self.len];
    }

    fn add(self: *Outputs, output: Output) void {
        if (self.len == max_outputs) return;
        self.entries[self.len] = output;
        self.len += 1;
        self.changed = true;
    }

    /// Returns the proxy so the caller can release it after dropping any
    /// surface that was using it.
    fn remove(self: *Outputs, name: u32) ?*wl.Output {
        for (self.items(), 0..) |output, index| {
            if (output.name != name) continue;
            const proxy = output.proxy;
            self.entries[index] = self.entries[self.len - 1];
            self.len -= 1;
            self.changed = true;
            return proxy;
        }
        return null;
    }
};

pub const Connection = struct {
    display: *wl.Display,
    registry: *wl.Registry,
    globals: Globals,
    bound: Bound,
    outputs: Outputs,

    pub fn deinit(self: *Connection) void {
        for (self.outputs.items()) |output| output.proxy.release();
        if (self.globals.seat) |seat| seat.release();
        if (self.globals.layer_shell) |shell| shell.destroy();
        self.globals.wm_base.destroy();
        self.globals.compositor.destroy();
        self.registry.destroy();
        self.display.disconnect();
    }

    pub fn requireLayerShell(self: Connection) Error!*zwlr.LayerShellV1 {
        return self.globals.layer_shell orelse Error.NoLayerShell;
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
    conn.outputs = .{};
    conn.registry.setListener(*Connection, onRegistryEvent, conn);
    if (conn.display.roundtrip() != .SUCCESS) return Error.RoundtripFailed;

    conn.globals = try require(conn.bound);
    conn.outputs.changed = false;
}

fn require(bound: Bound) Error!Globals {
    return .{
        .compositor = bound.compositor orelse return Error.NoCompositor,
        .wm_base = bound.wm_base orelse return Error.NoWmBase,
        .layer_shell = bound.layer_shell,
        .seat = bound.seat,
    };
}

fn onRegistryEvent(registry: *wl.Registry, event: wl.Registry.Event, conn: *Connection) void {
    switch (event) {
        .global => |global| bindGlobal(registry, global, conn),
        // A monitor was unplugged. Release the proxy only after the overlay has
        // dropped the surface that was on it, which it does on the next frame.
        .global_remove => |removed| {
            if (conn.outputs.remove(removed.name)) |proxy| proxy.release();
        },
    }
}

/// Binds one advertised global if it is one we care about. Version numbers are
/// the highest we implement, matching what build.zig asked the scanner for.
const Global = @FieldType(wl.Registry.Event, "global");

fn bindGlobal(registry: *wl.Registry, global: Global, conn: *Connection) void {
    const bound = &conn.bound;
    if (matches(global.interface, wl.Compositor.interface.name)) {
        bound.compositor = registry.bind(global.name, wl.Compositor, 4) catch null;
    } else if (matches(global.interface, xdg.WmBase.interface.name)) {
        bound.wm_base = registry.bind(global.name, xdg.WmBase, 3) catch null;
    } else if (matches(global.interface, zwlr.LayerShellV1.interface.name)) {
        bound.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 4) catch null;
    } else if (matches(global.interface, wl.Seat.interface.name)) {
        bound.seat = registry.bind(global.name, wl.Seat, 7) catch null;
    } else if (matches(global.interface, wl.Output.interface.name)) {
        bindOutput(registry, global, conn);
    }
}

fn bindOutput(registry: *wl.Registry, global: Global, conn: *Connection) void {
    const proxy = registry.bind(global.name, wl.Output, 4) catch return;
    conn.outputs.add(.{ .name = global.name, .proxy = proxy });
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
