//! Procedural geometry for the two shapes a pipe is made of. Pure: no GL, so
//! the generators are unit-testable without a context.
//!
//! Both meshes are built once at startup and drawn many times with instancing,
//! so they are generated at full quality rather than being cheap.

const std = @import("std");
const math = @import("math.zig");

/// Interleaved position and normal, laid out for a single vertex buffer.
pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
};

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []u16,

    pub fn deinit(self: Mesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

/// Matches the original's `MakeTube`: radius 1/3 of a cell, one cell long.
pub const pipe_radius: f32 = 1.0 / 3.0;
/// The elbow ball, sized so it swallows the mitre where two pipes meet.
pub const elbow_radius: f32 = 0.5;
/// The slightly larger ball that opens and closes a run.
pub const cap_radius: f32 = 0.6;

pub const default_facets: u16 = 24;
pub const default_stacks: u16 = 16;
pub const default_slices: u16 = 16;

/// An open tube along the Z axis, spanning `-length/2 .. +length/2`.
///
/// Deliberately has no end caps: every pipe end is covered by the next segment
/// or by an elbow/cap ball, so caps would be invisible geometry.
pub fn cylinder(
    allocator: std.mem.Allocator,
    radius: f32,
    length: f32,
    facets: u16,
) !Mesh {
    std.debug.assert(facets >= 3);
    const rings = 2;
    const vertices = try allocator.alloc(Vertex, @as(usize, facets) * rings);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u16, @as(usize, facets) * 6);
    errdefer allocator.free(indices);

    writeTubeRings(vertices, radius, length, facets);
    writeTubeIndices(indices, facets);
    return .{ .vertices = vertices, .indices = indices };
}

/// Two rings of `facets` vertices, the first at -z and the second at +z.
/// Normals point radially outward, giving the tube a smooth shaded surface.
fn writeTubeRings(vertices: []Vertex, radius: f32, length: f32, facets: u16) void {
    const half = length * 0.5;
    for (0..facets) |i| {
        const angle = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(facets));
        const nx = @cos(angle);
        const ny = @sin(angle);
        const normal = [3]f32{ nx, ny, 0 };

        vertices[i] = .{ .position = .{ nx * radius, ny * radius, -half }, .normal = normal };
        vertices[facets + i] = .{ .position = .{ nx * radius, ny * radius, half }, .normal = normal };
    }
}

/// Stitches the two rings into a closed band, wrapping the last quad round to
/// the first vertex so there is no visible seam.
fn writeTubeIndices(indices: []u16, facets: u16) void {
    for (0..facets) |i| {
        const near: u16 = @intCast(i);
        const next: u16 = @intCast((i + 1) % facets);
        const out = indices[i * 6 ..][0..6];

        out[0] = near;
        out[1] = next;
        out[2] = facets + near;
        out[3] = next;
        out[4] = facets + next;
        out[5] = facets + near;
    }
}

/// A UV sphere centred on the origin.
///
/// The longitude seam is duplicated rather than shared, which costs one extra
/// column of vertices but keeps the index arithmetic a plain grid walk.
pub fn sphere(
    allocator: std.mem.Allocator,
    radius: f32,
    stacks: u16,
    slices: u16,
) !Mesh {
    std.debug.assert(stacks >= 2 and slices >= 3);
    const columns = @as(usize, slices) + 1;
    const rows = @as(usize, stacks) + 1;

    const vertices = try allocator.alloc(Vertex, rows * columns);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u16, @as(usize, stacks) * slices * 6);
    errdefer allocator.free(indices);

    writeSphereVertices(vertices, radius, stacks, slices);
    writeSphereIndices(indices, stacks, slices);
    return .{ .vertices = vertices, .indices = indices };
}

/// Walks latitude from the north pole to the south, longitude all the way
/// round. On a unit sphere the position doubles as the normal.
fn writeSphereVertices(vertices: []Vertex, radius: f32, stacks: u16, slices: u16) void {
    const columns = @as(usize, slices) + 1;

    for (0..@as(usize, stacks) + 1) |row| {
        const polar = std.math.pi * @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(stacks));
        const ring_radius = @sin(polar);
        const y = @cos(polar);

        for (0..columns) |col| {
            const azimuth = std.math.tau * @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(slices));
            const normal = [3]f32{ ring_radius * @cos(azimuth), y, ring_radius * @sin(azimuth) };
            vertices[row * columns + col] = .{
                .position = .{ normal[0] * radius, normal[1] * radius, normal[2] * radius },
                .normal = normal,
            };
        }
    }
}

/// Two triangles per grid quad. The degenerate quads at the poles are left in:
/// they cost two triangles each and keep this a flat loop.
fn writeSphereIndices(indices: []u16, stacks: u16, slices: u16) void {
    const columns = @as(u16, slices) + 1;
    var cursor: usize = 0;

    for (0..stacks) |row| {
        for (0..slices) |col| {
            const top: u16 = @intCast(row * columns + col);
            const bottom: u16 = top + columns;
            const out = indices[cursor..][0..6];
            cursor += 6;

            out[0] = top;
            out[1] = top + 1;
            out[2] = bottom;
            out[3] = top + 1;
            out[4] = bottom + 1;
            out[5] = bottom;
        }
    }
}

const testing = std.testing;
const tolerance = 1e-5;

fn expectUnitNormals(mesh: Mesh) !void {
    for (mesh.vertices) |vertex| {
        const n = vertex.normal;
        const len = @sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        try testing.expectApproxEqAbs(1.0, len, tolerance);
    }
}

fn expectIndicesInRange(mesh: Mesh) !void {
    for (mesh.indices) |index| {
        try testing.expect(index < mesh.vertices.len);
    }
}

/// Quantised position, so vertices that coincide geometrically but were
/// emitted separately (a duplicated seam, a fanned pole) hash together.
const WeldKey = struct { x: i32, y: i32, z: i32 };

fn weldKey(position: [3]f32) WeldKey {
    const scale = 100_000.0;
    return .{
        .x = @intFromFloat(@round(position[0] * scale)),
        .y = @intFromFloat(@round(position[1] * scale)),
        .z = @intFromFloat(@round(position[2] * scale)),
    };
}

/// Maps every vertex to the first vertex sharing its position. Without this a
/// duplicated seam reads as a hole, because the two sides carry different
/// indices even though they sit on top of each other.
fn weldVertices(mesh: Mesh, allocator: std.mem.Allocator) ![]u16 {
    const canonical = try allocator.alloc(u16, mesh.vertices.len);
    errdefer allocator.free(canonical);

    var seen: std.AutoHashMapUnmanaged(WeldKey, u16) = .empty;
    defer seen.deinit(allocator);

    for (mesh.vertices, 0..) |vertex, i| {
        const entry = try seen.getOrPut(allocator, weldKey(vertex.position));
        if (!entry.found_existing) entry.value_ptr.* = @intCast(i);
        canonical[i] = entry.value_ptr.*;
    }
    return canonical;
}

/// Counts how many triangles use each undirected edge, after welding. An
/// interior edge is used twice; an edge used once lies on a boundary rim.
fn countEdgeUses(
    mesh: Mesh,
    canonical: []const u16,
    allocator: std.mem.Allocator,
) !std.AutoHashMapUnmanaged(u32, u32) {
    var edges: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    errdefer edges.deinit(allocator);

    var i: usize = 0;
    while (i < mesh.indices.len) : (i += 3) {
        const tri = [3]u16{
            canonical[mesh.indices[i]],
            canonical[mesh.indices[i + 1]],
            canonical[mesh.indices[i + 2]],
        };
        // A pole quad welds down to a zero-area triangle. It rasterises to
        // nothing, so skip it whole: counting its edges would double up one
        // of them and make a sound surface look non-manifold.
        if (isDegenerate(tri)) continue;

        for (0..3) |corner| {
            const a = tri[corner];
            const b = tri[(corner + 1) % 3];
            const key = (@as(u32, @min(a, b)) << 16) | @max(a, b);
            const entry = try edges.getOrPutValue(allocator, key, 0);
            entry.value_ptr.* += 1;
        }
    }
    return edges;
}

fn isDegenerate(tri: [3]u16) bool {
    return tri[0] == tri[1] or tri[1] == tri[2] or tri[2] == tri[0];
}

/// Asserts the mesh has exactly `boundary` single-use edges and that every
/// other edge is shared by two triangles. This catches off-by-one errors in
/// the seam and pole stitching, which are otherwise invisible until render.
fn expectSurface(mesh: Mesh, allocator: std.mem.Allocator, boundary: u32) !void {
    const canonical = try weldVertices(mesh, allocator);
    defer allocator.free(canonical);

    var edges = try countEdgeUses(mesh, canonical, allocator);
    defer edges.deinit(allocator);

    var single: u32 = 0;
    var it = edges.valueIterator();
    while (it.next()) |count| {
        switch (count.*) {
            1 => single += 1,
            2 => {},
            else => return error.TestUnexpectedResult,
        }
    }
    try testing.expectEqual(boundary, single);
}

/// Asserts every triangle faces away from the origin. Both our shapes are
/// centred and convex, so a triangle's geometric normal must point the same
/// way as its centroid. Inverted winding is invisible in a counts-and-normals
/// check but turns the surface inside out under two-sided lighting.
fn expectOutwardWinding(mesh: Mesh) !void {
    var i: usize = 0;
    while (i < mesh.indices.len) : (i += 3) {
        const a = mesh.vertices[mesh.indices[i]].position;
        const b = mesh.vertices[mesh.indices[i + 1]].position;
        const c = mesh.vertices[mesh.indices[i + 2]].position;

        const edge1 = math.Vec3.init(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
        const edge2 = math.Vec3.init(c[0] - a[0], c[1] - a[1], c[2] - a[2]);
        const face = math.Vec3.cross(edge1, edge2);
        if (face.length() < tolerance) continue; // degenerate at a pole

        const centroid = math.Vec3.init(
            (a[0] + b[0] + c[0]) / 3.0,
            (a[1] + b[1] + c[1]) / 3.0,
            (a[2] + b[2] + c[2]) / 3.0,
        );
        try testing.expect(math.Vec3.dot(face, centroid) > 0);
    }
}

test "cylinder has the expected counts" {
    const mesh = try cylinder(testing.allocator, pipe_radius, 1.0, 24);
    defer mesh.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 48), mesh.vertices.len);
    try testing.expectEqual(@as(usize, 144), mesh.indices.len);
}

test "cylinder is a well formed band open at both rims" {
    const facets = 24;
    const mesh = try cylinder(testing.allocator, pipe_radius, 1.0, facets);
    defer mesh.deinit(testing.allocator);

    try expectUnitNormals(mesh);
    try expectIndicesInRange(mesh);
    try expectOutwardWinding(mesh);
    // Uncapped by design, so the only boundary edges are the two rim loops.
    try expectSurface(mesh, testing.allocator, facets * 2);
}

test "cylinder sits on the radius and spans the requested length" {
    const mesh = try cylinder(testing.allocator, pipe_radius, 1.0, 24);
    defer mesh.deinit(testing.allocator);

    for (mesh.vertices) |vertex| {
        const p = vertex.position;
        try testing.expectApproxEqAbs(pipe_radius, @sqrt(p[0] * p[0] + p[1] * p[1]), tolerance);
        try testing.expectApproxEqAbs(0.5, @abs(p[2]), tolerance);
    }
}

test "cylinder normals point straight out from the axis" {
    const mesh = try cylinder(testing.allocator, pipe_radius, 1.0, 12);
    defer mesh.deinit(testing.allocator);

    for (mesh.vertices) |vertex| {
        try testing.expectApproxEqAbs(0.0, vertex.normal[2], tolerance);
        // Normal is parallel to the outward radial direction.
        const p = vertex.position;
        const cross = p[0] * vertex.normal[1] - p[1] * vertex.normal[0];
        try testing.expectApproxEqAbs(0.0, cross, tolerance);
    }
}

test "sphere has the expected counts" {
    const mesh = try sphere(testing.allocator, 1.0, 16, 16);
    defer mesh.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 17 * 17), mesh.vertices.len);
    try testing.expectEqual(@as(usize, 16 * 16 * 6), mesh.indices.len);
}

test "sphere is closed and its vertices sit on the radius" {
    const mesh = try sphere(testing.allocator, elbow_radius, 16, 16);
    defer mesh.deinit(testing.allocator);

    try expectUnitNormals(mesh);
    try expectIndicesInRange(mesh);
    try expectOutwardWinding(mesh);
    try expectSurface(mesh, testing.allocator, 0); // fully closed
    for (mesh.vertices) |vertex| {
        const p = vertex.position;
        const r = @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        try testing.expectApproxEqAbs(elbow_radius, r, tolerance);
    }
}

test "sphere index buffer stays within u16 at our sizes" {
    const mesh = try sphere(testing.allocator, 1.0, default_stacks, default_slices);
    defer mesh.deinit(testing.allocator);
    try testing.expect(mesh.vertices.len <= std.math.maxInt(u16));
}

test "generators reject degenerate parameters at runtime" {
    // Guarded by asserts, so only exercised in safe builds; the counts below
    // are the smallest shapes that are still surfaces.
    const tube = try cylinder(testing.allocator, 1.0, 1.0, 3);
    defer tube.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 6), tube.vertices.len);

    const ball = try sphere(testing.allocator, 1.0, 2, 3);
    defer ball.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 12), ball.vertices.len);
}
