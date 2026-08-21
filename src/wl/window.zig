//! An ordinary `xdg-shell` toplevel. This is the development surface: the
//! compositor keeps ownership of the keyboard, so a bug in here cannot lock
//! you out of your session the way the layer-shell overlay can.

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const connection = @import("connection.zig");

pub const Error = error{ SurfaceFailed, RoleFailed };

pub const default_width: u31 = 960;
pub const default_height: u31 = 720;

pub const Window = struct {
    surface: *wl.Surface,
    xdg_surface: *xdg.Surface,
    toplevel: *xdg.Toplevel,

    /// Set by the compositor's configure; the caller resizes its drawable to
    /// match before the next frame.
    width: u31 = default_width,
    height: u31 = default_height,
    /// Raised on configure, cleared once the caller has resized.
    resized: bool = false,
    configured: bool = false,
    /// Cleared when the compositor asks the window to close.
    running: bool = true,
    /// Raised by the compositor's frame callback: it is a good moment to
    /// paint. Starts true so the first frame is not waiting on a callback
    /// that only gets requested once a frame has been drawn.
    frame_ready: bool = true,

    pub fn deinit(self: *Window) void {
        self.toplevel.destroy();
        self.xdg_surface.destroy();
        self.surface.destroy();
    }
};

/// Creates the surface and its xdg role, then waits for the first configure.
/// `window` must outlive the connection: the listeners hold a pointer to it.
pub fn create(conn: *connection.Connection, window: *Window) !void {
    const globals = conn.globals;
    window.* = .{
        .surface = globals.compositor.createSurface() catch return Error.SurfaceFailed,
        .xdg_surface = undefined,
        .toplevel = undefined,
    };
    errdefer window.surface.destroy();

    window.xdg_surface = globals.wm_base.getXdgSurface(window.surface) catch
        return Error.RoleFailed;
    errdefer window.xdg_surface.destroy();

    window.toplevel = window.xdg_surface.getToplevel() catch return Error.RoleFailed;
    errdefer window.toplevel.destroy();

    setUpListeners(conn, window);
    window.toplevel.setTitle("pipes");
    window.toplevel.setAppId("pipes");
    window.surface.commit();

    try awaitConfigure(conn, window);
}

/// Asks to be told when the next frame is due. Must be called before the
/// buffer is swapped, so the request is committed along with the buffer.
///
/// This is what paces the screensaver. A timer would keep painting into an
/// occluded or blanked output; frame callbacks simply stop arriving, which is
/// exactly the behaviour a screensaver wants.
pub fn requestFrame(window: *Window) void {
    const callback = window.surface.frame() catch return;
    callback.setListener(*Window, onFrameDone, window);
}

fn onFrameDone(callback: *wl.Callback, event: wl.Callback.Event, window: *Window) void {
    switch (event) {
        .done => {
            window.frame_ready = true;
            callback.destroy();
        },
    }
}

fn setUpListeners(conn: *connection.Connection, window: *Window) void {
    conn.globals.wm_base.setListener(?*anyopaque, onWmBasePing, null);
    window.xdg_surface.setListener(*Window, onSurfaceEvent, window);
    window.toplevel.setListener(*Window, onToplevelEvent, window);
}

fn awaitConfigure(conn: *connection.Connection, window: *Window) !void {
    while (!window.configured) {
        _ = try connection.waitAndDispatch(conn, -1);
    }
}

/// The compositor pings to check we are alive; failing to pong gets the window
/// marked unresponsive.
fn onWmBasePing(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, _: ?*anyopaque) void {
    switch (event) {
        .ping => |ping| wm_base.pong(ping.serial),
    }
}

fn onSurfaceEvent(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, window: *Window) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            window.configured = true;
        },
    }
}

/// A zero width or height means "you pick"; we keep whatever we already had.
fn onToplevelEvent(_: *xdg.Toplevel, event: xdg.Toplevel.Event, window: *Window) void {
    switch (event) {
        .configure => |configure| {
            if (configure.width > 0) window.width = @intCast(configure.width);
            if (configure.height > 0) window.height = @intCast(configure.height);
            window.resized = true;
        },
        .close => window.running = false,
    }
}
