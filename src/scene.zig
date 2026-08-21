//! Turns simulation events into renderer instances. The only place that knows
//! both the integer grid and the world-space layout.

const std = @import("std");
const grid_mod = @import("sim/grid.zig");
const palette = @import("palette.zig");
const render = @import("render.zig");
const walk = @import("sim/walk.zig");

const Cell = grid_mod.Cell;

/// Applies one tick's worth of events.
pub fn apply(renderer: *render.Renderer, output: walk.Output, dims: [3]u16) !void {
    for (output.items()) |event| switch (event) {
        .reset => renderer.clear(),
        .joint => |j| try addJoint(renderer, j.cell, j.color, dims),
        .segment => |s| try addSegment(renderer, s.cell, s.direction, s.color, dims),
        .teapot => |t| try addTeapot(renderer, t.cell, t.direction, t.color, dims),
    };
}

/// A segment spans the gap between two cells, so it sits half a cell beyond
/// the one it leaves.
fn addSegment(
    renderer: *render.Renderer,
    cell: Cell,
    direction: grid_mod.Direction,
    color: usize,
    dims: [3]u16,
) !void {
    var center = cellCenter(cell, dims);
    const axis = @intFromEnum(direction.axis());
    center[axis] += 0.5 * @as(f32, @floatFromInt(direction.sign()));

    try renderer.addSegment(.{
        .center = center,
        .color = colorOf(color),
        .axis = axis,
    });
}

fn addJoint(renderer: *render.Renderer, cell: Cell, color: usize, dims: [3]u16) !void {
    try renderer.addJoint(.{
        .center = cellCenter(cell, dims),
        .color = colorOf(color),
        .axis = @intFromEnum(grid_mod.Axis.z),
    });
}

/// The teapot stands where an elbow ball would, turned to face along the pipe
/// leaving the joint so its spout follows the flow.
fn addTeapot(
    renderer: *render.Renderer,
    cell: Cell,
    direction: grid_mod.Direction,
    color: usize,
    dims: [3]u16,
) !void {
    try renderer.addTeapot(.{
        .center = cellCenter(cell, dims),
        .color = colorOf(color),
        .axis = @intFromEnum(direction.axis()),
    });
}

fn colorOf(index: usize) [3]f32 {
    const color = palette.get(index);
    return .{ color.x, color.y, color.z };
}

/// Cells are unit sized and the box is centred on the origin, so the camera
/// can orbit it without tracking a moving centre.
pub fn cellCenter(cell: Cell, dims: [3]u16) [3]f32 {
    var out: [3]f32 = undefined;
    for (0..3) |axis| {
        const half = @as(f32, @floatFromInt(dims[axis])) * 0.5;
        out[axis] = @as(f32, @floatFromInt(cell[axis])) - half + 0.5;
    }
    return out;
}

const testing = std.testing;

test "cellCenter centres the box on the origin" {
    try testing.expectEqual([3]f32{ -1.5, -1.5, -1.5 }, cellCenter(.{ 0, 0, 0 }, .{ 4, 4, 4 }));
    try testing.expectEqual([3]f32{ 1.5, 1.5, 1.5 }, cellCenter(.{ 3, 3, 3 }, .{ 4, 4, 4 }));
}

test "opposite corners are symmetric about the origin" {
    const dims = [3]u16{ 26, 20, 26 };
    const low = cellCenter(.{ 0, 0, 0 }, dims);
    const high = cellCenter(.{ 25, 19, 25 }, dims);
    for (low, high) |a, b| try testing.expectApproxEqAbs(a, -b, 1e-6);
}

test "adjacent cells are exactly one unit apart" {
    const dims = [3]u16{ 8, 8, 8 };
    for (grid_mod.Direction.all) |direction| {
        const from = cellCenter(.{ 4, 4, 4 }, dims);
        const to = cellCenter(grid_mod.step(.{ 4, 4, 4 }, direction), dims);
        const axis = @intFromEnum(direction.axis());
        try testing.expectApproxEqAbs(
            @as(f32, @floatFromInt(direction.sign())),
            to[axis] - from[axis],
            1e-6,
        );
    }
}
