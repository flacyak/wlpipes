//! Fullscreen `wlr-layer-shell` surfaces, one per monitor. This is the real
//! screensaver surface.
//!
//! DANGER: these sit on the overlay layer and take an exclusive keyboard grab.
//! If input handling breaks, the session becomes untypeable. `--max-seconds`
//! is the escape hatch and exists for exactly this.

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const connection = @import("connection.zig");
const egl = @import("../egl.zig");

pub const Error = error{ SurfaceFailed, RoleFailed };

/// Identifies us in `hyprctl layers`, and is what a Hyprland `layerrule`
/// matches against.
const namespace = "wlpipes";

/// One monitor's worth of screensaver.
pub const Panel = struct {
    /// Registry name of the monitor, so hotplug removal can find this panel.
    output_name: u32,
    surface: *wl.Surface,
    layer_surface: *zwlr.LayerSurfaceV1,
    egl_surface: ?egl.Surface = null,

    width: u31 = 0,
    height: u31 = 0,
    /// Raised on configure; cleared once the drawable has been resized.
    resized: bool = false,
    /// False until the compositor has told us how big this monitor is.
    configured: bool = false,
    /// Raised by the frame callback: a good moment to paint.
    frame_ready: bool = true,
    /// Set when the compositor destroys the surface under us.
    closed: bool = false,

    pub fn deinit(self: *Panel, instance: egl.Instance) void {
        if (self.egl_surface) |*surface| surface.deinit(instance);
        self.layer_surface.destroy();
        self.surface.destroy();
    }

    /// Asks to be told when the next frame is due. Must be called before the
    /// buffer is swapped so the request commits alongside it.
    pub fn requestFrame(self: *Panel) void {
        const callback = self.surface.frame() catch return;
        callback.setListener(*Panel, onFrameDone, self);
    }
};

fn onFrameDone(callback: *wl.Callback, event: wl.Callback.Event, panel: *Panel) void {
    switch (event) {
        .done => {
            panel.frame_ready = true;
            callback.destroy();
        },
    }
}

/// Creates a fullscreen overlay surface on one monitor. The panel is not
/// drawable until the compositor's first configure arrives.
pub fn createPanel(
    conn: *connection.Connection,
    shell: *zwlr.LayerShellV1,
    output: connection.Output,
    panel: *Panel,
) !void {
    const surface = conn.globals.compositor.createSurface() catch return Error.SurfaceFailed;
    errdefer surface.destroy();

    const layer_surface = shell.getLayerSurface(
        surface,
        output.proxy,
        .overlay,
        namespace,
    ) catch return Error.RoleFailed;
    errdefer layer_surface.destroy();

    panel.* = .{
        .output_name = output.name,
        .surface = surface,
        .layer_surface = layer_surface,
    };
    configure(panel);
    surface.commit();
}

/// Anchoring to all four edges makes the compositor report the monitor's full
/// size in the configure, which is how a layer surface asks to be fullscreen.
fn configure(panel: *Panel) void {
    const layer_surface = panel.layer_surface;
    layer_surface.setAnchor(.{ .top = true, .bottom = true, .left = true, .right = true });

    // -1 means "ignore other panels' reserved space": cover the bars too.
    layer_surface.setExclusiveZone(-1);

    // Exclusive keyboard is what lets the dismissing keystroke reach us rather
    // than leaking into whatever was focused underneath.
    layer_surface.setKeyboardInteractivity(.exclusive);

    layer_surface.setListener(*Panel, onLayerSurfaceEvent, panel);
}

fn onLayerSurfaceEvent(
    layer_surface: *zwlr.LayerSurfaceV1,
    event: zwlr.LayerSurfaceV1.Event,
    panel: *Panel,
) void {
    switch (event) {
        .configure => |c| {
            layer_surface.ackConfigure(c.serial);
            applySize(panel, c.width, c.height);
        },
        // The compositor tore the surface down, e.g. its monitor went away.
        .closed => panel.closed = true,
    }
}

fn applySize(panel: *Panel, width: u32, height: u32) void {
    if (width == 0 or height == 0) return;
    panel.width = @intCast(width);
    panel.height = @intCast(height);
    panel.configured = true;
    panel.resized = true;
}

/// Attaches a drawable once the size is known, or resizes an existing one.
pub fn syncDrawable(panel: *Panel, instance: egl.Instance) !void {
    if (!panel.configured) return;

    if (panel.egl_surface) |*surface| {
        surface.resize(panel.width, panel.height);
    } else {
        panel.egl_surface = try egl.createSurface(
            instance,
            panel.surface,
            panel.width,
            panel.height,
        );
    }
    panel.resized = false;
}
