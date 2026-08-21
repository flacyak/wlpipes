//! The occupancy grid the pipes grow through. Pure: no GL, no Wayland.

const std = @import("std");

/// Integer cell coordinate. Indexed by axis so direction arithmetic stays a
/// loop rather than three near-identical branches.
pub const Cell = [3]i32;

pub const Axis = enum(u2) { x = 0, y = 1, z = 2 };

pub const Direction = enum(u3) {
    x_pos,
    x_neg,
    y_pos,
    y_neg,
    z_pos,
    z_neg,

    pub const all = [_]Direction{ .x_pos, .x_neg, .y_pos, .y_neg, .z_pos, .z_neg };

    pub fn axis(self: Direction) Axis {
        return @enumFromInt(@intFromEnum(self) / 2);
    }

    /// -1 or +1 along `axis`.
    pub fn sign(self: Direction) i32 {
        return if (@intFromEnum(self) % 2 == 0) 1 else -1;
    }

    pub fn delta(self: Direction) Cell {
        var out: Cell = .{ 0, 0, 0 };
        out[@intFromEnum(self.axis())] = self.sign();
        return out;
    }

    pub fn opposite(self: Direction) Direction {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }
};

pub fn step(cell: Cell, direction: Direction) Cell {
    const d = direction.delta();
    return .{ cell[0] + d[0], cell[1] + d[1], cell[2] + d[2] };
}

pub const Grid = struct {
    /// One byte per cell: whether a pipe has claimed it.
    occupied: []bool,
    dims: [3]u16,

    pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
        allocator.free(self.occupied);
    }

    pub fn cellCount(self: Grid) usize {
        return @as(usize, self.dims[0]) * self.dims[1] * self.dims[2];
    }

    /// Wipes the box for a fresh scene, keeping the allocation.
    pub fn clear(self: *Grid) void {
        @memset(self.occupied, false);
    }

    pub fn contains(self: Grid, cell: Cell) bool {
        for (cell, self.dims) |coordinate, size| {
            if (coordinate < 0 or coordinate >= size) return false;
        }
        return true;
    }

    pub fn indexOf(self: Grid, cell: Cell) usize {
        const x: usize = @intCast(cell[0]);
        const y: usize = @intCast(cell[1]);
        const z: usize = @intCast(cell[2]);
        return (z * self.dims[1] + y) * self.dims[0] + x;
    }

    /// In bounds and unclaimed. Out-of-bounds counts as unavailable, which is
    /// what makes the walls of the box act as walls.
    pub fn isFree(self: Grid, cell: Cell) bool {
        return self.contains(cell) and !self.occupied[self.indexOf(cell)];
    }

    pub fn occupy(self: *Grid, cell: Cell) void {
        std.debug.assert(self.contains(cell));
        self.occupied[self.indexOf(cell)] = true;
    }

    /// Collects the directions leading out of `cell` to a free neighbour.
    /// Returns how many were written to `out`.
    ///
    /// A run ends when this returns zero, which is far more often because the
    /// head boxed itself in than because it reached a wall.
    pub fn freeDirections(self: Grid, cell: Cell, out: *[6]Direction) usize {
        var count: usize = 0;
        for (Direction.all) |direction| {
            if (self.isFree(step(cell, direction))) {
                out[count] = direction;
                count += 1;
            }
        }
        return count;
    }
};

pub fn create(allocator: std.mem.Allocator, dims: [3]u16) !Grid {
    var grid: Grid = .{ .occupied = &.{}, .dims = dims };
    grid.occupied = try allocator.alloc(bool, grid.cellCount());
    grid.clear();
    return grid;
}

/// Finds a free cell to start a run from.
///
/// Random probing is fast while the box is mostly empty, which is the common
/// case; the linear scan is the fallback that guarantees termination once the
/// box is nearly full, so a full box ends the scene rather than spinning.
pub fn findFree(grid: Grid, random: std.Random, probes: usize) ?Cell {
    for (0..probes) |_| {
        const cell = randomCell(grid, random);
        if (grid.isFree(cell)) return cell;
    }
    return firstFree(grid);
}

fn randomCell(grid: Grid, random: std.Random) Cell {
    return .{
        random.intRangeLessThan(i32, 0, grid.dims[0]),
        random.intRangeLessThan(i32, 0, grid.dims[1]),
        random.intRangeLessThan(i32, 0, grid.dims[2]),
    };
}

fn firstFree(grid: Grid) ?Cell {
    const index = std.mem.indexOfScalar(bool, grid.occupied, false) orelse return null;
    const plane = @as(usize, grid.dims[0]) * grid.dims[1];
    return .{
        @intCast(index % grid.dims[0]),
        @intCast((index / grid.dims[0]) % grid.dims[1]),
        @intCast(index / plane),
    };
}

const testing = std.testing;

test "direction axis, sign and delta agree" {
    for (Direction.all) |direction| {
        const delta = direction.delta();
        const axis = @intFromEnum(direction.axis());
        try testing.expectEqual(direction.sign(), delta[axis]);
        for (delta, 0..) |value, index| {
            if (index != axis) try testing.expectEqual(@as(i32, 0), value);
        }
    }
}

test "opposite reverses the delta and is an involution" {
    for (Direction.all) |direction| {
        const opposite = direction.opposite();
        try testing.expectEqual(direction.axis(), opposite.axis());
        try testing.expectEqual(-direction.sign(), opposite.sign());
        try testing.expectEqual(direction, opposite.opposite());
    }
}

test "indexOf is a bijection over the box" {
    var grid = try create(testing.allocator, .{ 3, 4, 5 });
    defer grid.deinit(testing.allocator);

    var seen = try testing.allocator.alloc(bool, grid.cellCount());
    defer testing.allocator.free(seen);
    @memset(seen, false);

    for (0..5) |z| for (0..4) |y| for (0..3) |x| {
        const index = grid.indexOf(.{ @intCast(x), @intCast(y), @intCast(z) });
        try testing.expect(index < grid.cellCount());
        try testing.expect(!seen[index]);
        seen[index] = true;
    };
}

test "cells outside the box are never free" {
    var grid = try create(testing.allocator, .{ 4, 4, 4 });
    defer grid.deinit(testing.allocator);

    const outside = [_]Cell{
        .{ -1, 0, 0 }, .{ 0, -1, 0 }, .{ 0, 0, -1 },
        .{ 4, 0, 0 },  .{ 0, 4, 0 },  .{ 0, 0, 4 },
    };
    for (outside) |cell| {
        try testing.expect(!grid.contains(cell));
        try testing.expect(!grid.isFree(cell));
    }
}

test "a corner has three ways out, an interior cell six" {
    var grid = try create(testing.allocator, .{ 4, 4, 4 });
    defer grid.deinit(testing.allocator);

    var out: [6]Direction = undefined;
    try testing.expectEqual(@as(usize, 3), grid.freeDirections(.{ 0, 0, 0 }, &out));
    try testing.expectEqual(@as(usize, 4), grid.freeDirections(.{ 1, 0, 0 }, &out));
    try testing.expectEqual(@as(usize, 6), grid.freeDirections(.{ 1, 1, 1 }, &out));
}

test "occupied neighbours are not free directions" {
    var grid = try create(testing.allocator, .{ 3, 3, 3 });
    defer grid.deinit(testing.allocator);

    var out: [6]Direction = undefined;
    try testing.expectEqual(@as(usize, 6), grid.freeDirections(.{ 1, 1, 1 }, &out));

    grid.occupy(.{ 2, 1, 1 });
    grid.occupy(.{ 0, 1, 1 });
    try testing.expectEqual(@as(usize, 4), grid.freeDirections(.{ 1, 1, 1 }, &out));
    for (out[0..4]) |direction| {
        try testing.expect(direction.axis() != .x);
    }
}

test "a boxed in cell has no way out even far from any wall" {
    var grid = try create(testing.allocator, .{ 5, 5, 5 });
    defer grid.deinit(testing.allocator);

    const centre: Cell = .{ 2, 2, 2 };
    for (Direction.all) |direction| grid.occupy(step(centre, direction));

    var out: [6]Direction = undefined;
    try testing.expectEqual(@as(usize, 0), grid.freeDirections(centre, &out));
}

test "clear frees the whole box" {
    var grid = try create(testing.allocator, .{ 3, 3, 3 });
    defer grid.deinit(testing.allocator);

    for (0..3) |z| for (0..3) |y| for (0..3) |x| {
        grid.occupy(.{ @intCast(x), @intCast(y), @intCast(z) });
    };
    try testing.expectEqual(@as(?Cell, null), firstFree(grid));

    grid.clear();
    try testing.expectEqual(@as(?Cell, .{ 0, 0, 0 }), firstFree(grid));
}

test "findFree returns a free cell, or null only when the box is full" {
    var prng = std.Random.DefaultPrng.init(99);
    const random = prng.random();

    var grid = try create(testing.allocator, .{ 4, 4, 4 });
    defer grid.deinit(testing.allocator);

    // Fill everything but one cell; probing will almost always miss it, so
    // this exercises the linear fallback.
    for (0..4) |z| for (0..4) |y| for (0..4) |x| {
        grid.occupy(.{ @intCast(x), @intCast(y), @intCast(z) });
    };
    grid.occupied[grid.indexOf(.{ 3, 2, 1 })] = false;

    try testing.expectEqual(@as(?Cell, .{ 3, 2, 1 }), findFree(grid, random, 8));

    grid.occupy(.{ 3, 2, 1 });
    try testing.expectEqual(@as(?Cell, null), findFree(grid, random, 8));
}

test "firstFree round trips through indexOf" {
    var grid = try create(testing.allocator, .{ 5, 3, 7 });
    defer grid.deinit(testing.allocator);

    for (0..grid.cellCount()) |i| {
        @memset(grid.occupied, true);
        grid.occupied[i] = false;
        const cell = firstFree(grid).?;
        try testing.expectEqual(i, grid.indexOf(cell));
    }
}
