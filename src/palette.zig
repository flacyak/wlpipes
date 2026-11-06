//! The seven pipe colours, taken from the original's material table (the same
//! values xscreensaver's pipes.c uses). Pure: no GL, no allocation.

const std = @import("std");
const math = @import("math.zig");

/// Diffuse colours. The rest of the material — ambient, specular, shininess —
/// is the same for every pipe and lives in the fragment shader.
pub const colors = [_]math.Vec3{
    .{ .x = 0.7, .y = 0.0, .z = 0.0 }, // red
    .{ .x = 0.1, .y = 0.5, .z = 0.2 }, // green
    .{ .x = 0.0, .y = 0.0, .z = 0.7 }, // blue
    .{ .x = 0.2, .y = 0.5, .z = 0.7 }, // cyan
    .{ .x = 0.7, .y = 0.7, .z = 0.0 }, // yellow
    .{ .x = 0.6, .y = 0.2, .z = 0.5 }, // magenta
    .{ .x = 0.7, .y = 0.7, .z = 0.7 }, // white
};

pub const count = colors.len;

/// Picks a colour index, avoiding `previous` so two consecutive runs never
/// share a colour. Pass `null` for the first run of a scene.
pub fn choose(random: std.Random, previous: ?usize) usize {
    if (previous == null) return random.uintLessThan(usize, count);

    // Draw from the other six, then shift past the excluded one. This is a
    // single draw with no rejection loop, so it cannot spin.
    const drawn = random.uintLessThan(usize, count - 1);
    return if (drawn >= previous.?) drawn + 1 else drawn;
}

pub fn get(index: usize) math.Vec3 {
    return colors[index % count];
}

const testing = std.testing;

test "every colour is in range" {
    for (colors) |color| {
        for ([_]f32{ color.x, color.y, color.z }) |channel| {
            try testing.expect(channel >= 0.0 and channel <= 1.0);
        }
    }
}

test "choose never repeats the previous colour" {
    var prng = std.Random.DefaultPrng.init(0x9e3779b9);
    const random = prng.random();

    for (0..count) |previous| {
        for (0..500) |_| {
            const picked = choose(random, previous);
            try testing.expect(picked != previous);
            try testing.expect(picked < count);
        }
    }
}

test "choose reaches every other colour" {
    var prng = std.Random.DefaultPrng.init(1234);
    const random = prng.random();
    var seen: [count]bool = @splat(false);

    for (0..2000) |_| seen[choose(random, 3)] = true;

    for (seen, 0..) |hit, index| {
        try testing.expectEqual(index != 3, hit);
    }
}

test "choose with no previous can return any colour" {
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();
    var seen: [count]bool = @splat(false);

    for (0..2000) |_| seen[choose(random, null)] = true;
    for (seen) |hit| try testing.expect(hit);
}
