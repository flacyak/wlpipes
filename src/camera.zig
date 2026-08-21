//! Frames the pipe box in view. Pure: no GL, so the framing maths is testable
//! without a context.

const std = @import("std");
const math = @import("math.zig");

/// Vertical field of view, matching the original's 45 degree frustum.
pub const fov_y: f32 = std.math.pi / 4.0;

/// Leaves a little air around the box so pipes at the edge are not clipped by
/// their own radius.
const margin: f32 = 1.15;

const near_plane: f32 = 0.5;

pub const Camera = struct {
    projection: math.Mat4,
    view: math.Mat4,
};

/// Places the camera far enough back that the whole box fits, orbited `yaw`
/// radians about the vertical axis through the box's centre.
pub fn frame(extent: math.Vec3, aspect: f32, yaw: f32) Camera {
    const distance = distanceFor(extent, aspect);
    const eye = math.Vec3.init(
        @sin(yaw) * distance,
        0,
        @cos(yaw) * distance,
    );

    const far_plane = distance + math.Vec3.length(extent);
    return .{
        .projection = math.perspective(fov_y, aspect, near_plane, far_plane),
        .view = math.lookAt(eye, math.Vec3.zero, math.Vec3.init(0, 1, 0)),
    };
}

/// Distance at which the box's silhouette fits both the vertical and the
/// horizontal field of view, plus half its depth so the near face clears the
/// near plane as the box turns.
fn distanceFor(extent: math.Vec3, aspect: f32) f32 {
    const half_fov_y = fov_y * 0.5;
    const half_fov_x = std.math.atan(@tan(half_fov_y) * aspect);

    const for_height = (extent.y * 0.5 * margin) / @tan(half_fov_y);
    const for_width = (extent.x * 0.5 * margin) / @tan(half_fov_x);

    // Orbiting swings the box's diagonal across the view, so reserve room for
    // the wider of the two horizontal extents rather than just x.
    const half_diagonal = 0.5 * @sqrt(extent.x * extent.x + extent.z * extent.z);
    return @max(for_height, for_width) + half_diagonal;
}

const testing = std.testing;
const tolerance = 1e-4;

/// Projects a world point to normalised device coordinates.
fn project(camera: Camera, point: math.Vec3) math.Vec3 {
    const clip = math.multiply(camera.projection, camera.view);
    const x = clip[0] * point.x + clip[4] * point.y + clip[8] * point.z + clip[12];
    const y = clip[1] * point.x + clip[5] * point.y + clip[9] * point.z + clip[13];
    const z = clip[2] * point.x + clip[6] * point.y + clip[10] * point.z + clip[14];
    const w = clip[3] * point.x + clip[7] * point.y + clip[11] * point.z + clip[15];
    return math.Vec3.init(x / w, y / w, z / w);
}

/// Asserts every corner of the box lands inside the unit cube.
fn expectBoxVisible(extent: math.Vec3, aspect: f32, yaw: f32) !void {
    const camera = frame(extent, aspect, yaw);
    const half = math.Vec3.scale(extent, 0.5);

    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sy| {
            for ([_]f32{ -1, 1 }) |sz| {
                const corner = math.Vec3.init(half.x * sx, half.y * sy, half.z * sz);
                const ndc = project(camera, corner);
                try testing.expect(@abs(ndc.x) <= 1.0);
                try testing.expect(@abs(ndc.y) <= 1.0);
                try testing.expect(ndc.z >= -1.0 and ndc.z <= 1.0);
            }
        }
    }
}

test "the whole box fits on a square viewport" {
    try expectBoxVisible(math.Vec3.init(26, 20, 26), 1.0, 0);
}

test "the whole box fits on wide and tall viewports" {
    for ([_]f32{ 0.5, 0.75, 1.0, 1.78, 2.5, 4.0 }) |aspect| {
        try expectBoxVisible(math.Vec3.init(26, 20, 26), aspect, 0);
    }
}

test "the box stays framed all the way round an orbit" {
    var step: usize = 0;
    while (step < 16) : (step += 1) {
        const yaw = std.math.tau * @as(f32, @floatFromInt(step)) / 16.0;
        try expectBoxVisible(math.Vec3.init(26, 20, 26), 1.78, yaw);
    }
}

test "non cubic boxes stay framed" {
    try expectBoxVisible(math.Vec3.init(40, 8, 12), 1.78, 0);
    try expectBoxVisible(math.Vec3.init(8, 40, 12), 1.78, 0);
    try expectBoxVisible(math.Vec3.init(8, 12, 40), 1.78, 1.0);
}

test "a bigger box needs a longer lens" {
    const near = distanceFor(math.Vec3.init(10, 10, 10), 1.0);
    const far = distanceFor(math.Vec3.init(20, 20, 20), 1.0);
    try testing.expect(far > near);
    try testing.expectApproxEqRel(2.0, far / near, tolerance);
}

test "the camera looks at the origin from the requested angle" {
    const camera = frame(math.Vec3.init(10, 10, 10), 1.0, 0);
    const centre = project(camera, math.Vec3.zero);
    try testing.expectApproxEqAbs(0.0, centre.x, tolerance);
    try testing.expectApproxEqAbs(0.0, centre.y, tolerance);
}

test "yaw of a quarter turn swaps which axis faces the camera" {
    const extent = math.Vec3.init(10, 10, 10);
    const front = frame(extent, 1.0, 0);
    const side = frame(extent, 1.0, std.math.pi / 2.0);

    // A point on +x is centred horizontally when we orbit to look down x.
    const probe = math.Vec3.init(4, 0, 0);
    try testing.expect(@abs(project(side, probe).x) < @abs(project(front, probe).x));
}
