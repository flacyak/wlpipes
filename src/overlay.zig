//! The overlay backend: one layer-shell panel per monitor, all sharing a
//! single scene and EGL context, dismissed by any input.

const std = @import("std");
const Io = std.Io;

const config = @import("config.zig");
const egl = @import("egl.zig");
const render = @import("render.zig");
const connection = @import("wl/connection.zig");
const input_mod = @import("wl/input.zig");
const layer = @import("wl/layer.zig");

pub const Panels = struct {
    items: std.ArrayList(layer.Panel) = .empty,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Panels, instance: egl.Instance) void {
        for (self.items.items) |*panel| panel.deinit(instance);
        self.items.deinit(self.allocator);
    }

    fn has(self: Panels, output_name: u32) bool {
        for (self.items.items) |panel| {
            if (panel.output_name == output_name) return true;
        }
        return false;
    }

    /// True while any panel still has a live surface worth drawing.
    pub fn anyLive(self: Panels) bool {
        for (self.items.items) |panel| {
            if (!panel.closed) return true;
        }
        return false;
    }
};

/// Brings panels into line with the monitors the compositor is advertising:
/// adds one for a newly plugged monitor, drops one whose monitor went away.
pub fn reconcile(
    panels: *Panels,
    conn: *connection.Connection,
    instance: egl.Instance,
) !void {
    dropStalePanels(panels, conn, instance);

    const shell = try conn.requireLayerShell();
    for (conn.outputs.items()) |output| {
        if (panels.has(output.name)) continue;
        const panel = try panels.items.addOne(panels.allocator);
        try layer.createPanel(conn, shell, output, panel);
    }
    conn.outputs.changed = false;
}

/// Removes panels whose monitor is gone, or that the compositor closed.
fn dropStalePanels(
    panels: *Panels,
    conn: *connection.Connection,
    instance: egl.Instance,
) void {
    var index: usize = 0;
    while (index < panels.items.items.len) {
        const panel = &panels.items.items[index];
        if (stillWanted(panel.*, conn)) {
            index += 1;
            continue;
        }
        panel.deinit(instance);
        _ = panels.items.swapRemove(index);
    }
}

fn stillWanted(panel: layer.Panel, conn: *connection.Connection) bool {
    if (panel.closed) return false;
    for (conn.outputs.items()) |output| {
        if (output.name == panel.output_name) return true;
    }
    return false;
}

/// Paints every panel that has a frame due. Returns whether anything was
/// drawn, so the caller knows the pass was not a no-op.
pub fn drawPanels(
    panels: *Panels,
    instance: egl.Instance,
    renderer: *render.Renderer,
    cfg: config.Config,
    yaw: f32,
) !bool {
    var painted = false;
    for (panels.items.items) |*panel| {
        if (panel.closed or !panel.configured or !panel.frame_ready) continue;
        panel.frame_ready = false;

        try layer.syncDrawable(panel, instance);
        const surface = panel.egl_surface orelse continue;

        try surface.makeCurrent(instance);
        try paint(surface, renderer, cfg, yaw);

        // Requested before the swap so it commits with the buffer.
        panel.requestFrame();
        try surface.swap(instance);
        painted = true;
    }
    return painted;
}

/// Every monitor shows the same box from its own aspect ratio, so the scene is
/// coherent across a multi-monitor desk rather than several unrelated ones.
fn paint(
    surface: egl.Surface,
    renderer: *render.Renderer,
    cfg: config.Config,
    yaw: f32,
) !void {
    const camera = @import("app.zig").frameCamera(surface, cfg, yaw);
    render.draw(renderer, surface.width, surface.height, camera);
}

const testing = std.testing;

test "panels tracks which outputs it already covers" {
    var panels: Panels = .{ .allocator = testing.allocator };
    defer panels.items.deinit(testing.allocator);

    try testing.expect(!panels.has(3));
    try testing.expect(!panels.anyLive());

    // Only the bookkeeping fields matter here; the proxies are never touched.
    try panels.items.append(testing.allocator, .{
        .output_name = 3,
        .surface = undefined,
        .layer_surface = undefined,
    });
    try testing.expect(panels.has(3));
    try testing.expect(!panels.has(4));
    try testing.expect(panels.anyLive());
}

test "a closed panel is no longer live" {
    var panels: Panels = .{ .allocator = testing.allocator };
    defer panels.items.deinit(testing.allocator);

    try panels.items.append(testing.allocator, .{
        .output_name = 1,
        .surface = undefined,
        .layer_surface = undefined,
        .closed = true,
    });
    try testing.expect(!panels.anyLive());
}

test "a panel is dropped when its monitor goes away" {
    var panels: Panels = .{ .allocator = testing.allocator };
    defer panels.items.deinit(testing.allocator);

    for ([_]u32{ 1, 2, 3 }) |name| {
        try panels.items.append(testing.allocator, .{
            .output_name = name,
            .surface = undefined,
            .layer_surface = undefined,
        });
    }

    // swapRemove reorders, so removal must be by output name rather than index.
    _ = panels.items.swapRemove(1);
    try testing.expect(panels.has(1));
    try testing.expect(!panels.has(2));
    try testing.expect(panels.has(3));
}
