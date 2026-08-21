//! Newell's teapot: the easter egg the original screensaver hid among the
//! pipes.
//!
//! Control point data from the classic GLUT teapot:
//!
//!   Copyright (c) Mark J. Kilgard, 1994.
//!   (c) Copyright 1993, Silicon Graphics, Inc.
//!
//!   Permission to use, copy, modify, and distribute this software for any
//!   purpose and without fee is hereby granted, provided that the above
//!   copyright notice appear in all copies and that both the copyright notice
//!   and this permission notice appear in supporting documentation, and that
//!   the name of Silicon Graphics, Inc. not be used in advertising or
//!   publicity pertaining to distribution of the software without specific,
//!   written prior permission.
//!
//!   THE MATERIAL EMBODIED ON THIS SOFTWARE IS PROVIDED TO YOU "AS-IS" AND
//!   WITHOUT WARRANTY OF ANY KIND, EXPRESS, IMPLIED OR OTHERWISE, INCLUDING
//!   WITHOUT LIMITATION, ANY WARRANTY OF MERCHANTABILITY OR FITNESS FOR A
//!   PARTICULAR PURPOSE.
//!
//! The data describes ten bicubic Bezier patches covering one quadrant. The
//! full 32-patch teapot comes from mirroring them, which `patches` does.

const std = @import("std");
const math = @import("math.zig");
const mesh_mod = @import("mesh.zig");

/// Sixteen control point indices per patch, in row major order.
pub const patch_indices = [_][16]u16{
    .{ 102, 103, 104, 105, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
    .{ 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27 },
    .{ 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40 },
    .{ 96, 96, 96, 96, 97, 98, 99, 100, 101, 101, 101, 101, 0, 1, 2, 3 },
    .{ 0, 1, 2, 3, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117 },
    .{ 118, 118, 118, 118, 124, 122, 119, 121, 123, 126, 125, 120, 40, 39, 38, 37 },
    .{ 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56 },
    .{ 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 28, 65, 66, 67 },
    .{ 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83 },
    .{ 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95 },
};

/// The teapot's control points, z up, as the original data has them.
pub const control_points = [_][3]f32{
    .{ 0.2, 0.0, 2.7 },
    .{ 0.2, -0.112, 2.7 },
    .{ 0.112, -0.2, 2.7 },
    .{ 0.0, -0.2, 2.7 },
    .{ 1.3375, 0.0, 2.53125 },
    .{ 1.3375, -0.749, 2.53125 },
    .{ 0.749, -1.3375, 2.53125 },
    .{ 0.0, -1.3375, 2.53125 },
    .{ 1.4375, 0.0, 2.53125 },
    .{ 1.4375, -0.805, 2.53125 },
    .{ 0.805, -1.4375, 2.53125 },
    .{ 0.0, -1.4375, 2.53125 },
    .{ 1.5, 0.0, 2.4 },
    .{ 1.5, -0.84, 2.4 },
    .{ 0.84, -1.5, 2.4 },
    .{ 0.0, -1.5, 2.4 },
    .{ 1.75, 0.0, 1.875 },
    .{ 1.75, -0.98, 1.875 },
    .{ 0.98, -1.75, 1.875 },
    .{ 0.0, -1.75, 1.875 },
    .{ 2.0, 0.0, 1.35 },
    .{ 2.0, -1.12, 1.35 },
    .{ 1.12, -2.0, 1.35 },
    .{ 0.0, -2.0, 1.35 },
    .{ 2.0, 0.0, 0.9 },
    .{ 2.0, -1.12, 0.9 },
    .{ 1.12, -2.0, 0.9 },
    .{ 0.0, -2.0, 0.9 },
    .{ -2.0, 0.0, 0.9 },
    .{ 2.0, 0.0, 0.45 },
    .{ 2.0, -1.12, 0.45 },
    .{ 1.12, -2.0, 0.45 },
    .{ 0.0, -2.0, 0.45 },
    .{ 1.5, 0.0, 0.225 },
    .{ 1.5, -0.84, 0.225 },
    .{ 0.84, -1.5, 0.225 },
    .{ 0.0, -1.5, 0.225 },
    .{ 1.5, 0.0, 0.15 },
    .{ 1.5, -0.84, 0.15 },
    .{ 0.84, -1.5, 0.15 },
    .{ 0.0, -1.5, 0.15 },
    .{ -1.6, 0.0, 2.025 },
    .{ -1.6, -0.3, 2.025 },
    .{ -1.5, -0.3, 2.25 },
    .{ -1.5, 0.0, 2.25 },
    .{ -2.3, 0.0, 2.025 },
    .{ -2.3, -0.3, 2.025 },
    .{ -2.5, -0.3, 2.25 },
    .{ -2.5, 0.0, 2.25 },
    .{ -2.7, 0.0, 2.025 },
    .{ -2.7, -0.3, 2.025 },
    .{ -3.0, -0.3, 2.25 },
    .{ -3.0, 0.0, 2.25 },
    .{ -2.7, 0.0, 1.8 },
    .{ -2.7, -0.3, 1.8 },
    .{ -3.0, -0.3, 1.8 },
    .{ -3.0, 0.0, 1.8 },
    .{ -2.7, 0.0, 1.575 },
    .{ -2.7, -0.3, 1.575 },
    .{ -3.0, -0.3, 1.35 },
    .{ -3.0, 0.0, 1.35 },
    .{ -2.5, 0.0, 1.125 },
    .{ -2.5, -0.3, 1.125 },
    .{ -2.65, -0.3, 0.9375 },
    .{ -2.65, 0.0, 0.9375 },
    .{ -2.0, -0.3, 0.9 },
    .{ -1.9, -0.3, 0.6 },
    .{ -1.9, 0.0, 0.6 },
    .{ 1.7, 0.0, 1.425 },
    .{ 1.7, -0.66, 1.425 },
    .{ 1.7, -0.66, 0.6 },
    .{ 1.7, 0.0, 0.6 },
    .{ 2.6, 0.0, 1.425 },
    .{ 2.6, -0.66, 1.425 },
    .{ 3.1, -0.66, 0.825 },
    .{ 3.1, 0.0, 0.825 },
    .{ 2.3, 0.0, 2.1 },
    .{ 2.3, -0.25, 2.1 },
    .{ 2.4, -0.25, 2.025 },
    .{ 2.4, 0.0, 2.025 },
    .{ 2.7, 0.0, 2.4 },
    .{ 2.7, -0.25, 2.4 },
    .{ 3.3, -0.25, 2.4 },
    .{ 3.3, 0.0, 2.4 },
    .{ 2.8, 0.0, 2.475 },
    .{ 2.8, -0.25, 2.475 },
    .{ 3.525, -0.25, 2.49375 },
    .{ 3.525, 0.0, 2.49375 },
    .{ 2.9, 0.0, 2.475 },
    .{ 2.9, -0.15, 2.475 },
    .{ 3.45, -0.15, 2.5125 },
    .{ 3.45, 0.0, 2.5125 },
    .{ 2.8, 0.0, 2.4 },
    .{ 2.8, -0.15, 2.4 },
    .{ 3.2, -0.15, 2.4 },
    .{ 3.2, 0.0, 2.4 },
    .{ 0.0, 0.0, 3.15 },
    .{ 0.8, 0.0, 3.15 },
    .{ 0.8, -0.45, 3.15 },
    .{ 0.45, -0.8, 3.15 },
    .{ 0.0, -0.8, 3.15 },
    .{ 0.0, 0.0, 2.85 },
    .{ 1.4, 0.0, 2.4 },
    .{ 1.4, -0.784, 2.4 },
    .{ 0.784, -1.4, 2.4 },
    .{ 0.0, -1.4, 2.4 },
    .{ 0.4, 0.0, 2.55 },
    .{ 0.4, -0.224, 2.55 },
    .{ 0.224, -0.4, 2.55 },
    .{ 0.0, -0.4, 2.55 },
    .{ 1.3, 0.0, 2.55 },
    .{ 1.3, -0.728, 2.55 },
    .{ 0.728, -1.3, 2.55 },
    .{ 0.0, -1.3, 2.55 },
    .{ 1.3, 0.0, 2.4 },
    .{ 1.3, -0.728, 2.4 },
    .{ 0.728, -1.3, 2.4 },
    .{ 0.0, -1.3, 2.4 },
    .{ 0.0, 0.0, 0.0 },
    .{ 1.425, -0.798, 0.0 },
    .{ 1.5, 0.0, 0.075 },
    .{ 1.425, 0.0, 0.0 },
    .{ 0.798, -1.425, 0.0 },
    .{ 0.0, -1.5, 0.075 },
    .{ 0.0, -1.425, 0.0 },
    .{ 1.5, -0.84, 0.075 },
    .{ 0.84, -1.5, 0.075 },
};


/// One patch's sixteen control points, already mirrored into place.
pub const Patch = [4][4][3]f32;

/// Patches 0..5 are the rim, body and lid, which are symmetric about both x
/// and y. Patches 6..9 are the handle and spout, which only mirror in y.
const quadrant_symmetric_patches = 6;

/// 10 base patches, doubled in y, and the first six doubled again in x.
pub const patch_count = patch_indices.len * 2 + quadrant_symmetric_patches * 2;

/// Builds the full 32-patch teapot by mirroring the quadrant data.
///
/// Mirroring a patch flips the winding, so the mirrored copies also reverse
/// their column order; without that the reflected halves would face inwards.
pub fn patches() [patch_count]Patch {
    var out: [patch_count]Patch = undefined;
    var next: usize = 0;

    for (patch_indices, 0..) |indices, patch| {
        out[next] = gather(indices, false);
        next += 1;
        out[next] = mirror(gather(indices, true), .{ false, true, false });
        next += 1;

        if (patch >= quadrant_symmetric_patches) continue;
        out[next] = mirror(gather(indices, true), .{ true, false, false });
        next += 1;
        out[next] = mirror(gather(indices, false), .{ true, true, false });
        next += 1;
    }
    return out;
}

fn gather(indices: [16]u16, reverse_columns: bool) Patch {
    var out: Patch = undefined;
    for (0..4) |row| {
        for (0..4) |col| {
            const source = if (reverse_columns) 3 - col else col;
            out[row][col] = control_points[indices[row * 4 + source]];
        }
    }
    return out;
}

fn mirror(patch: Patch, axes: [3]bool) Patch {
    var out = patch;
    for (&out) |*row| {
        for (row) |*point| {
            for (point, axes) |*value, flip| {
                if (flip) value.* = -value.*;
            }
        }
    }
    return out;
}

/// Cubic Bernstein basis, and its derivative for the surface normal.
fn bernstein(t: f32) [4]f32 {
    const u = 1.0 - t;
    return .{ u * u * u, 3 * t * u * u, 3 * t * t * u, t * t * t };
}

fn bernsteinDerivative(t: f32) [4]f32 {
    const u = 1.0 - t;
    return .{ -3 * u * u, 3 * u * u - 6 * t * u, 6 * t * u - 3 * t * t, 3 * t * t };
}

/// Weighted sum of a patch's control points.
fn combine(patch: Patch, weights_u: [4]f32, weights_v: [4]f32) math.Vec3 {
    var out = math.Vec3.zero;
    for (0..4) |row| {
        for (0..4) |col| {
            const w = weights_u[row] * weights_v[col];
            const p = patch[row][col];
            out = math.Vec3.add(out, math.Vec3.scale(math.Vec3.init(p[0], p[1], p[2]), w));
        }
    }
    return out;
}

/// Position and normal at parameters (u, v) on a patch.
///
/// The normal comes from the analytic partial derivatives rather than from
/// neighbouring triangles, which keeps the surface smooth even at low
/// tessellation. Where the patch is degenerate -- the control points collapse
/// at the top of the lid -- the cross product vanishes and the caller has to
/// substitute something; `surfacePoint` reports that with a null normal.
fn surfacePoint(patch: Patch, u: f32, v: f32) struct { position: math.Vec3, normal: ?math.Vec3 } {
    const bu = bernstein(u);
    const bv = bernstein(v);
    const du = bernsteinDerivative(u);
    const dv = bernsteinDerivative(v);

    const tangent_u = combine(patch, du, bv);
    const tangent_v = combine(patch, bu, dv);
    const normal = math.Vec3.cross(tangent_u, tangent_v);

    return .{
        .position = combine(patch, bu, bv),
        .normal = if (normal.length() > 1e-6) math.Vec3.normalize(normal) else null,
    };
}

/// Subdivisions per patch edge. Six keeps the whole teapot under the u16 index
/// limit while staying smooth at the size it appears on screen.
pub const default_subdivisions: u16 = 6;

/// Builds a teapot mesh scaled to sit inside one grid cell, y up.
///
/// The source data is z up, so it is rotated on the way out to match the
/// scene. Caller owns the mesh.
pub fn build(allocator: std.mem.Allocator, subdivisions: u16) !mesh_mod.Mesh {
    std.debug.assert(subdivisions >= 1);
    const span = @as(usize, subdivisions) + 1;
    const all = patches();

    const vertices = try allocator.alloc(mesh_mod.Vertex, all.len * span * span);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u16, all.len * subdivisions * subdivisions * 6);
    errdefer allocator.free(indices);

    for (all, 0..) |patch, index| {
        writePatchVertices(vertices[index * span * span ..], patch, subdivisions);
        writePatchIndices(
            indices[index * subdivisions * subdivisions * 6 ..],
            @intCast(index * span * span),
            subdivisions,
        );
    }

    normalise(vertices);
    return .{ .vertices = vertices, .indices = indices };
}

fn writePatchVertices(out: []mesh_mod.Vertex, patch: Patch, subdivisions: u16) void {
    const span = @as(usize, subdivisions) + 1;
    const step = 1.0 / @as(f32, @floatFromInt(subdivisions));

    for (0..span) |row| {
        for (0..span) |col| {
            const sample = surfacePoint(
                patch,
                @as(f32, @floatFromInt(row)) * step,
                @as(f32, @floatFromInt(col)) * step,
            );
            // A degenerate corner has no surface normal; point it along the
            // teapot's axis, which is the right answer at the lid's tip.
            const normal = sample.normal orelse math.Vec3.init(0, 0, 1);
            out[row * span + col] = .{
                .position = toSceneAxes(sample.position),
                .normal = toSceneAxes(normal),
            };
        }
    }
}

fn writePatchIndices(out: []u16, base: u16, subdivisions: u16) void {
    const span = @as(u16, subdivisions) + 1;
    var cursor: usize = 0;

    for (0..subdivisions) |row| {
        for (0..subdivisions) |col| {
            const top = base + @as(u16, @intCast(row)) * span + @as(u16, @intCast(col));
            const quad = out[cursor..][0..6];
            cursor += 6;

            quad[0] = top;
            quad[1] = top + span;
            quad[2] = top + 1;
            quad[3] = top + 1;
            quad[4] = top + span;
            quad[5] = top + span + 1;
        }
    }
}

/// The teapot data is z up; the scene is y up.
fn toSceneAxes(v: math.Vec3) [3]f32 {
    return .{ v.x, v.z, -v.y };
}

/// Centres the teapot on the origin and scales it to fit inside one cell, so
/// it drops into a joint's place without sticking through the neighbouring
/// pipes.
fn normalise(vertices: []mesh_mod.Vertex) void {
    var low = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
    var high = [3]f32{ -std.math.floatMax(f32), -std.math.floatMax(f32), -std.math.floatMax(f32) };

    for (vertices) |vertex| {
        for (vertex.position, 0..) |value, axis| {
            low[axis] = @min(low[axis], value);
            high[axis] = @max(high[axis], value);
        }
    }

    var extent: f32 = 0;
    var centre: [3]f32 = undefined;
    for (0..3) |axis| {
        centre[axis] = (low[axis] + high[axis]) * 0.5;
        extent = @max(extent, high[axis] - low[axis]);
    }

    const scale = if (extent > 0) target_size / extent else 1.0;
    for (vertices) |*vertex| {
        for (&vertex.position, centre) |*value, offset| {
            value.* = (value.* - offset) * scale;
        }
    }
}

/// Span from handle tip to spout tip, in cells.
///
/// Sized by measurement rather than taste. At 1.1 the body came out 0.34 cells
/// thick -- all but identical to the pipe radius of 1/3 -- so the teapot
/// vanished into the pipe it sat on. Two pipes meet at an elbow and pass
/// straight through the teapot's middle, so it has to be big enough that the
/// body still bulges clear of both. At 2.6 the body is about 0.78 and reads at
/// a glance. It does overlap neighbouring cells, as the original's did.
const target_size: f32 = 2.6;

const testing = std.testing;

test "mirroring produces the full 32 patch teapot" {
    try testing.expectEqual(@as(usize, 32), patch_count);
    try testing.expectEqual(@as(usize, 32), patches().len);
}

test "every patch index is within the control point table" {
    for (patch_indices) |indices| {
        for (indices) |index| try testing.expect(index < control_points.len);
    }
}

test "the teapot is symmetric about the handle to spout axis" {
    // Mirroring is in y, so for every vertex there should be a partner at -y.
    const mesh = try build(testing.allocator, 4);
    defer mesh.deinit(testing.allocator);

    var lowest: f32 = 0;
    var highest: f32 = 0;
    for (mesh.vertices) |vertex| {
        lowest = @min(lowest, vertex.position[2]);
        highest = @max(highest, vertex.position[2]);
    }
    try testing.expectApproxEqAbs(lowest, -highest, 1e-4);
}

test "the mesh fits inside a cell and is centred" {
    const mesh = try build(testing.allocator, default_subdivisions);
    defer mesh.deinit(testing.allocator);

    for (0..3) |axis| {
        var low: f32 = std.math.floatMax(f32);
        var high: f32 = -std.math.floatMax(f32);
        for (mesh.vertices) |vertex| {
            low = @min(low, vertex.position[axis]);
            high = @max(high, vertex.position[axis]);
        }
        try testing.expect(high - low <= target_size + 1e-4);
        try testing.expectApproxEqAbs(0.0, (low + high) * 0.5, 1e-4);
    }
}

test "the longest axis is scaled to exactly the target size" {
    const mesh = try build(testing.allocator, default_subdivisions);
    defer mesh.deinit(testing.allocator);

    var largest: f32 = 0;
    for (0..3) |axis| {
        var low: f32 = std.math.floatMax(f32);
        var high: f32 = -std.math.floatMax(f32);
        for (mesh.vertices) |vertex| {
            low = @min(low, vertex.position[axis]);
            high = @max(high, vertex.position[axis]);
        }
        largest = @max(largest, high - low);
    }
    try testing.expectApproxEqAbs(target_size, largest, 1e-4);
}

test "normals are unit length everywhere, including degenerate corners" {
    const mesh = try build(testing.allocator, default_subdivisions);
    defer mesh.deinit(testing.allocator);

    for (mesh.vertices) |vertex| {
        const n = vertex.normal;
        const length = @sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        try testing.expectApproxEqAbs(1.0, length, 1e-4);
    }
}

test "the index buffer stays inside u16" {
    const mesh = try build(testing.allocator, default_subdivisions);
    defer mesh.deinit(testing.allocator);

    try testing.expect(mesh.vertices.len <= std.math.maxInt(u16));
    for (mesh.indices) |index| try testing.expect(index < mesh.vertices.len);
}
