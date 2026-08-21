//! Vector and matrix helpers. Pure: no GL, no Wayland, no allocation.
//!
//! Matrices are column-major `[16]f32`, matching what GL expects, so they can
//! be handed to `glUniformMatrix4fv` with `transpose = GL_FALSE`.

const std = @import("std");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero: Vec3 = .{ .x = 0, .y = 0, .z = 0 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(v: Vec3, factor: f32) Vec3 {
        return .{ .x = v.x * factor, .y = v.y * factor, .z = v.z * factor };
    }

    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn length(v: Vec3) f32 {
        return @sqrt(dot(v, v));
    }

    /// Returns the zero vector unchanged rather than producing NaNs.
    pub fn normalize(v: Vec3) Vec3 {
        const len = length(v);
        return if (len == 0) v else scale(v, 1.0 / len);
    }
};

pub const Mat4 = [16]f32;

pub const identity: Mat4 = .{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
};

/// Returns `a * b`, applying `b` first when used to transform a column vector.
pub fn multiply(a: Mat4, b: Mat4) Mat4 {
    var out: Mat4 = undefined;
    for (0..4) |col| {
        for (0..4) |row| {
            var sum: f32 = 0;
            for (0..4) |k| sum += a[k * 4 + row] * b[col * 4 + k];
            out[col * 4 + row] = sum;
        }
    }
    return out;
}

pub fn translation(v: Vec3) Mat4 {
    var out = identity;
    out[12] = v.x;
    out[13] = v.y;
    out[14] = v.z;
    return out;
}

/// Right-handed perspective projection onto GL's [-1, 1] depth range.
pub fn perspective(fovy_radians: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const f = 1.0 / @tan(fovy_radians * 0.5);
    var out: Mat4 = @splat(0);
    out[0] = f / aspect;
    out[5] = f;
    out[10] = (far + near) / (near - far);
    out[11] = -1;
    out[14] = (2 * far * near) / (near - far);
    return out;
}

/// Right-handed view matrix looking from `eye` towards `center`.
pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Mat4 {
    const forward = Vec3.normalize(Vec3.sub(center, eye));
    const side = Vec3.normalize(Vec3.cross(forward, up));
    const upward = Vec3.cross(side, forward);

    return .{
        side.x,  upward.x,  -forward.x, 0,
        side.y,  upward.y,  -forward.y, 0,
        side.z,  upward.z,  -forward.z, 0,
        -Vec3.dot(side, eye), -Vec3.dot(upward, eye), Vec3.dot(forward, eye), 1,
    };
}

/// Rotation about the Y axis, used for the optional camera drift.
pub fn rotationY(radians: f32) Mat4 {
    const s = @sin(radians);
    const c = @cos(radians);
    var out = identity;
    out[0] = c;
    out[2] = -s;
    out[8] = s;
    out[10] = c;
    return out;
}

const testing = std.testing;
const tolerance = 1e-5;

fn expectVec3(expected: Vec3, actual: Vec3) !void {
    try testing.expectApproxEqAbs(expected.x, actual.x, tolerance);
    try testing.expectApproxEqAbs(expected.y, actual.y, tolerance);
    try testing.expectApproxEqAbs(expected.z, actual.z, tolerance);
}

/// Transforms a column vector, dividing through by w.
fn transform(m: Mat4, v: Vec3) Vec3 {
    const x = m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12];
    const y = m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13];
    const z = m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14];
    const w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15];
    return if (w == 0) Vec3.init(x, y, z) else Vec3.init(x / w, y / w, z / w);
}

test "cross product is right handed" {
    const x = Vec3.init(1, 0, 0);
    const y = Vec3.init(0, 1, 0);
    try expectVec3(Vec3.init(0, 0, 1), Vec3.cross(x, y));
}

test "normalize leaves the zero vector alone" {
    try expectVec3(Vec3.zero, Vec3.normalize(Vec3.zero));
    try testing.expectApproxEqAbs(1.0, Vec3.normalize(Vec3.init(3, 4, 0)).length(), tolerance);
}

test "identity is a multiplicative unit" {
    const m = translation(Vec3.init(1, 2, 3));
    try testing.expectEqualSlices(f32, &m, &multiply(m, identity));
    try testing.expectEqualSlices(f32, &m, &multiply(identity, m));
}

test "translation moves a point" {
    const m = translation(Vec3.init(1, 2, 3));
    try expectVec3(Vec3.init(11, 22, 33), transform(m, Vec3.init(10, 20, 30)));
}

test "multiply applies the right operand first" {
    const first = translation(Vec3.init(1, 0, 0));
    const then = rotationY(std.math.pi / 2.0);
    // Translate along +x, then rotate: +x should swing to -z.
    try expectVec3(Vec3.init(0, 0, -1), transform(multiply(then, first), Vec3.zero));
}

test "rotationY turns +x towards -z" {
    const m = rotationY(std.math.pi / 2.0);
    try expectVec3(Vec3.init(0, 0, -1), transform(m, Vec3.init(1, 0, 0)));
}

test "lookAt puts the target down -z in view space" {
    const eye = Vec3.init(0, 0, 5);
    const view = lookAt(eye, Vec3.zero, Vec3.init(0, 1, 0));
    try expectVec3(Vec3.init(0, 0, -5), transform(view, Vec3.zero));
    try expectVec3(Vec3.zero, transform(view, eye));
}

test "lookAt keeps up pointing up" {
    const view = lookAt(Vec3.init(0, 0, 5), Vec3.zero, Vec3.init(0, 1, 0));
    const above = transform(view, Vec3.init(0, 1, 0));
    try testing.expect(above.y > 0);
}

test "perspective maps the near and far planes to -1 and 1" {
    const p = perspective(std.math.pi / 4.0, 1.0, 1.0, 100.0);
    try testing.expectApproxEqAbs(-1.0, transform(p, Vec3.init(0, 0, -1)).z, tolerance);
    try testing.expectApproxEqAbs(1.0, transform(p, Vec3.init(0, 0, -100)).z, tolerance);
}

test "perspective narrows x as aspect widens" {
    const square = perspective(std.math.pi / 4.0, 1.0, 1.0, 100.0);
    const wide = perspective(std.math.pi / 4.0, 2.0, 1.0, 100.0);
    const point = Vec3.init(1, 0, -5);
    try testing.expect(@abs(transform(wide, point).x) < @abs(transform(square, point).x));
}
