//! A fixed serpentine path through the box, used to exercise the instanced
//! renderer before the simulation exists. Stage 5 deletes this file.

const std = @import("std");
const config = @import("config.zig");
const math = @import("math.zig");
const palette = @import("palette.zig");
const render = @import("render.zig");

const Step = struct { axis: render.Axis, length: i32 };

/// Walks a fixed circuit, changing colour at each turn, so the demo shows off
/// every axis and several colours at once.
const circuit = [_]Step{
    .{ .axis = .x, .length = 6 },
    .{ .axis = .y, .length = 4 },
    .{ .axis = .z, .length = 6 },
    .{ .axis = .x, .length = -4 },
    .{ .axis = .y, .length = -6 },
    .{ .axis = .z, .length = -4 },
    .{ .axis = .x, .length = -3 },
    .{ .axis = .y, .length = 5 },
};

/// Fills the renderer with the demo scene, centred on the box.
pub fn build(renderer: *render.Renderer, grid: config.Grid) !void {
    renderer.clear();

    var cell = [3]i32{ 2, 2, 2 };
    for (circuit, 0..) |step, index| {
        const color = palette.get(index);
        try addJoint(renderer, cell, grid, color);
        try addRun(renderer, &cell, step, grid, color);
    }
    try addJoint(renderer, cell, grid, palette.get(circuit.len));
}

/// Lays `step.length` segments along one axis, moving `cell` to the far end.
fn addRun(
    renderer: *render.Renderer,
    cell: *[3]i32,
    step: Step,
    grid: config.Grid,
    color: math.Vec3,
) !void {
    const axis = @intFromEnum(step.axis);
    const direction: i32 = if (step.length < 0) -1 else 1;

    for (0..@abs(step.length)) |_| {
        // The segment spans the gap between two cells, so it sits half a cell
        // beyond the one we are leaving.
        var center = cellToWorld(cell.*, grid);
        center[axis] += @as(f32, @floatFromInt(direction)) * 0.5;

        try renderer.addSegment(.{
            .center = center,
            .color = .{ color.x, color.y, color.z },
            .axis = @intFromEnum(step.axis),
        });
        cell[axis] += direction;
    }
}

fn addJoint(
    renderer: *render.Renderer,
    cell: [3]i32,
    grid: config.Grid,
    color: math.Vec3,
) !void {
    try renderer.addJoint(.{
        .center = cellToWorld(cell, grid),
        .color = .{ color.x, color.y, color.z },
        .axis = @intFromEnum(render.Axis.z),
    });
}

/// Cells are unit sized; the box is centred on the origin so the camera can
/// orbit it without tracking a moving centre.
pub fn cellToWorld(cell: [3]i32, grid: config.Grid) [3]f32 {
    const dims = [3]u16{ grid.x, grid.y, grid.z };
    var out: [3]f32 = undefined;
    for (0..3) |axis| {
        const half = @as(f32, @floatFromInt(dims[axis])) * 0.5;
        out[axis] = @as(f32, @floatFromInt(cell[axis])) - half + 0.5;
    }
    return out;
}

const testing = std.testing;

test "cellToWorld centres the grid on the origin" {
    const grid: config.Grid = .{ .x = 4, .y = 4, .z = 4 };
    try testing.expectEqual([3]f32{ -1.5, -1.5, -1.5 }, cellToWorld(.{ 0, 0, 0 }, grid));
    try testing.expectEqual([3]f32{ 1.5, 1.5, 1.5 }, cellToWorld(.{ 3, 3, 3 }, grid));
}

test "cellToWorld keeps opposite corners symmetric" {
    const grid: config.Grid = .{ .x = 26, .y = 20, .z = 26 };
    const low = cellToWorld(.{ 0, 0, 0 }, grid);
    const high = cellToWorld(.{ 25, 19, 25 }, grid);
    for (low, high) |a, b| try testing.expectApproxEqAbs(a, -b, 1e-6);
}
