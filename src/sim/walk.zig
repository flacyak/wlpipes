//! The pipe growth state machine. Pure: no GL, no Wayland, no allocation
//! beyond the grid it is handed.
//!
//! A *run* is one continuous pipe of a single colour. It ends when its head
//! has no free neighbour, or when it reaches its length cap. Note which of
//! those dominates: walls end very few runs, because long before the head
//! reaches one it has usually boxed itself in against pipe it already laid.
//! Checking only for walls would let the pipe walk through itself and the box
//! would never fill.

const std = @import("std");
const grid_mod = @import("grid.zig");
const palette = @import("../palette.zig");

const Cell = grid_mod.Cell;
const Direction = grid_mod.Direction;
const Grid = grid_mod.Grid;

pub const Params = struct {
    /// Runs drawn before the box is wiped and the scene restarts.
    max_runs: u32 = 12,
    /// Upper bound on a run's length; each run picks its own below this.
    max_length: u32 = 100,
    /// Shortest a run may be, so a scene is not all stubs.
    min_length: u32 = 5,
    /// Random probes before falling back to a linear scan for a free cell.
    start_probes: usize = 64,
    /// Percent chance a turn sprouts a teapot rather than a ball joint.
    teapot_percent: u32 = 2,
};

/// What one tick produced, for the caller to turn into geometry.
pub const Event = union(enum) {
    /// A pipe spanning the gap between `cell` and its neighbour in `direction`.
    segment: struct { cell: Cell, direction: Direction, color: usize },
    /// A ball at a cell centre: an elbow at a turn, or a run's end cap.
    joint: struct { cell: Cell, color: usize },
    /// The easter egg, standing in for an elbow. `direction` is where the pipe
    /// is heading, so the teapot can be turned to face along it.
    teapot: struct { cell: Cell, direction: Direction, color: usize },
    /// The box was wiped. Everything emitted before this is gone.
    reset,
};

/// At most one reset, one closing cap and one opening cap in a single tick.
pub const max_events = 3;

pub const Output = struct {
    buffer: [max_events]Event = undefined,
    len: usize = 0,

    pub fn items(self: *const Output) []const Event {
        return self.buffer[0..self.len];
    }

    fn push(self: *Output, event: Event) void {
        std.debug.assert(self.len < max_events);
        self.buffer[self.len] = event;
        self.len += 1;
    }
};

pub const Walker = struct {
    grid: Grid,
    random: std.Random,
    params: Params,

    /// Null between runs, and for the very first cell of a run when there is
    /// no previous direction to compare against.
    direction: ?Direction = null,
    position: Cell = .{ 0, 0, 0 },
    color: usize = 0,
    /// Segments laid in the current run.
    length: u32 = 0,
    /// Length of the current run's straight, which drives the turn odds.
    straight: u32 = 0,
    /// Cap this run stops at, drawn fresh per run.
    length_limit: u32 = 0,
    /// Runs completed in the current scene.
    runs: u32 = 0,
    /// False until the first tick has placed a starting cell.
    started: bool = false,

    /// Advances one segment. Returns the geometry that tick produced.
    pub fn tick(self: *Walker) Output {
        var out: Output = .{};
        if (!self.started) {
            beginScene(self, &out);
            return out;
        }

        var free: [6]Direction = undefined;
        const count = self.grid.freeDirections(self.position, &free);

        if (count == 0 or self.length >= self.length_limit) {
            endRun(self, &out);
            return out;
        }
        advance(self, &out, free[0..count]);
        return out;
    }
};

/// Lays one segment, turning first if the walk decides to or has to.
fn advance(self: *Walker, out: *Output, free: []const Direction) void {
    const chosen = chooseDirection(self, free);

    if (self.direction) |previous| {
        if (previous != chosen) {
            out.push(elbowAt(self, chosen));
            self.straight = 0;
        }
    }

    out.push(.{ .segment = .{
        .cell = self.position,
        .direction = chosen,
        .color = self.color,
    } });

    self.position = grid_mod.step(self.position, chosen);
    self.grid.occupy(self.position);
    self.direction = chosen;
    self.length += 1;
    self.straight += 1;
}

/// Keeps going straight unless the way is blocked or the odds say to turn.
fn chooseDirection(self: *Walker, free: []const Direction) Direction {
    const current = self.direction orelse return pickAny(self, free);

    if (!contains(free, current)) return pickTurn(self, free, current);
    if (self.length > 0 and shouldTurn(self)) return pickTurn(self, free, current);
    return current;
}

/// The original's turn rule. The chance of turning climbs the longer the
/// current straight runs, which is what gives Pipes its characteristic long
/// straights punctuated by turns. A flat probability reads as far too twitchy.
fn shouldTurn(self: *Walker) bool {
    return self.random.uintLessThan(u32, 50) <
        self.random.uintLessThan(u32, self.straight + 1);
}

fn pickAny(self: *Walker, free: []const Direction) Direction {
    return free[self.random.uintLessThan(usize, free.len)];
}

/// Picks any free direction other than `current`, falling back to `current`
/// when it is the only way out.
fn pickTurn(self: *Walker, free: []const Direction, current: Direction) Direction {
    var turns: [6]Direction = undefined;
    var count: usize = 0;
    for (free) |direction| {
        if (direction == current) continue;
        turns[count] = direction;
        count += 1;
    }
    if (count == 0) return current;
    return turns[self.random.uintLessThan(usize, count)];
}

/// Most turns get a ball joint. Occasionally one gets Newell's teapot, which
/// is the joke the original screensaver hid among the pipes.
fn elbowAt(self: *Walker, heading: Direction) Event {
    if (self.params.teapot_percent > 0 and
        self.random.uintLessThan(u32, 100) < self.params.teapot_percent)
    {
        return .{ .teapot = .{
            .cell = self.position,
            .direction = heading,
            .color = self.color,
        } };
    }
    return .{ .joint = .{ .cell = self.position, .color = self.color } };
}

fn contains(directions: []const Direction, wanted: Direction) bool {
    return std.mem.indexOfScalar(Direction, directions, wanted) != null;
}

/// Caps the finished run, then either starts the next one or wipes the box.
fn endRun(self: *Walker, out: *Output) void {
    out.push(.{ .joint = .{ .cell = self.position, .color = self.color } });
    self.runs += 1;

    if (self.runs >= self.params.max_runs) {
        wipe(self, out);
        return;
    }
    if (!beginRun(self, out)) wipe(self, out);
}

/// Starts the first run of a fresh scene.
fn beginScene(self: *Walker, out: *Output) void {
    self.started = true;
    if (!beginRun(self, out)) wipe(self, out);
}

/// Clears the box and opens a new scene. The caller drops its geometry when it
/// sees the reset event.
fn wipe(self: *Walker, out: *Output) void {
    self.grid.clear();
    self.runs = 0;
    self.direction = null;
    out.push(.reset);
    _ = beginRun(self, out);
}

/// Claims a starting cell and emits its opening cap. Returns false when the
/// box has no free cell left, which is the caller's cue to wipe.
fn beginRun(self: *Walker, out: *Output) bool {
    const start = grid_mod.findFree(self.grid, self.random, self.params.start_probes) orelse
        return false;

    self.position = start;
    self.grid.occupy(start);
    self.direction = null;
    self.length = 0;
    self.straight = 0;
    self.length_limit = drawLengthLimit(self);
    self.color = palette.choose(self.random, if (self.runs == 0) null else self.color);

    out.push(.{ .joint = .{ .cell = start, .color = self.color } });
    return true;
}

/// Runs vary in length so a scene is not a set of identical strands.
fn drawLengthLimit(self: *Walker) u32 {
    const span = self.params.max_length -| self.params.min_length;
    if (span == 0) return self.params.min_length;
    return self.params.min_length + self.random.uintLessThan(u32, span + 1);
}

pub fn create(grid: Grid, random: std.Random, params: Params) Walker {
    return .{ .grid = grid, .random = random, .params = params };
}

const testing = std.testing;

const Harness = struct {
    walker: Walker,
    prng: std.Random.DefaultPrng,

    fn deinit(self: *Harness, allocator: std.mem.Allocator) void {
        self.walker.grid.deinit(allocator);
    }
};

fn harness(allocator: std.mem.Allocator, dims: [3]u16, seed: u64, params: Params) !*Harness {
    const self = try allocator.create(Harness);
    self.prng = std.Random.DefaultPrng.init(seed);
    self.walker = create(try grid_mod.create(allocator, dims), self.prng.random(), params);
    return self;
}

fn destroy(self: *Harness, allocator: std.mem.Allocator) void {
    self.deinit(allocator);
    allocator.destroy(self);
}

test "a segment never leaves the box" {
    const h = try harness(testing.allocator, .{ 8, 6, 8 }, 0xC0FFEE, .{});
    defer destroy(h, testing.allocator);

    for (0..20_000) |_| {
        const out = h.walker.tick();
        for (out.items()) |event| switch (event) {
            .segment => |s| {
                try testing.expect(h.walker.grid.contains(s.cell));
                try testing.expect(h.walker.grid.contains(grid_mod.step(s.cell, s.direction)));
            },
            .joint => |j| try testing.expect(h.walker.grid.contains(j.cell)),
            .teapot => |t| try testing.expect(h.walker.grid.contains(t.cell)),
            .reset => {},
        };
    }
}

test "a cell is never claimed twice within one scene" {
    const h = try harness(testing.allocator, .{ 7, 5, 7 }, 0x1234, .{ .max_runs = 6 });
    defer destroy(h, testing.allocator);

    var claimed = std.AutoHashMapUnmanaged(Cell, void).empty;
    defer claimed.deinit(testing.allocator);

    for (0..5_000) |_| {
        const out = h.walker.tick();
        for (out.items()) |event| switch (event) {
            .reset => claimed.clearRetainingCapacity(),
            .joint => |j| _ = try claimed.getOrPut(testing.allocator, j.cell),
            .teapot => |t| _ = try claimed.getOrPut(testing.allocator, t.cell),
            .segment => |s| {
                // The far end of the segment is the cell being claimed now.
                const target = grid_mod.step(s.cell, s.direction);
                const entry = try claimed.getOrPut(testing.allocator, target);
                try testing.expect(!entry.found_existing);
            },
        };
    }
}

test "every run terminates and the scene resets" {
    const h = try harness(testing.allocator, .{ 6, 5, 6 }, 0xBEEF, .{ .max_runs = 4 });
    defer destroy(h, testing.allocator);

    var resets: usize = 0;
    var caps: usize = 0;
    for (0..10_000) |_| {
        for (h.walker.tick().items()) |event| switch (event) {
            .reset => resets += 1,
            .joint, .teapot => caps += 1,
            .segment => {},
        };
    }
    // A 6x5x6 box cannot absorb 10k segments without wiping repeatedly.
    try testing.expect(resets > 5);
    try testing.expect(caps > resets);
}

test "a run stops at its length cap" {
    const h = try harness(testing.allocator, .{ 40, 40, 40 }, 7, .{
        .max_runs = 1000,
        .min_length = 6,
        .max_length = 6,
    });
    defer destroy(h, testing.allocator);

    var length: u32 = 0;
    var checked: usize = 0;
    for (0..4_000) |_| {
        for (h.walker.tick().items()) |event| switch (event) {
            .segment => length += 1,
            .joint, .teapot => {},
            .reset => {},
        };
        // The walker resets `length` when a run ends, so sample it each tick.
        if (h.walker.length == 0 and length > 0) {
            try testing.expect(length <= 6 * 2);
            length = 0;
            checked += 1;
        }
    }
    try testing.expect(checked > 10);
}

fn occupiedCount(grid: Grid) usize {
    var used: usize = 0;
    for (grid.occupied) |cell| {
        if (cell) used += 1;
    }
    return used;
}

test "the box genuinely fills up rather than stalling early" {
    const h = try harness(testing.allocator, .{ 10, 10, 10 }, 0xF00D, .{
        .max_runs = 10_000,
        .min_length = 5,
        .max_length = 200,
    });
    defer destroy(h, testing.allocator);

    // Sample before each tick: a wipe zeroes the grid, so reading it after the
    // run finishes would always report an empty box.
    var peak: usize = 0;
    for (0..4_000) |_| {
        peak = @max(peak, occupiedCount(h.walker.grid));
        _ = h.walker.tick();
    }

    // Walls alone would strand the head early. Boxing-in against its own pipe
    // is what actually packs the box.
    const capacity = h.walker.grid.cellCount();
    try testing.expect(peak * 100 / capacity > 60);
}

test "straights are long, which is the look" {
    const h = try harness(testing.allocator, .{ 60, 60, 60 }, 0x51DE, .{
        .max_runs = 100_000,
        .min_length = 400,
        .max_length = 400,
    });
    defer destroy(h, testing.allocator);

    var segments: usize = 0;
    var joints: usize = 0;
    for (0..20_000) |_| {
        for (h.walker.tick().items()) |event| switch (event) {
            .segment => segments += 1,
            .joint, .teapot => joints += 1,
            .reset => {},
        };
    }

    // The turn odds climb with the straight's length, giving a mean run of
    // several cells between turns. A flat probability would sit near 1/p and
    // look far more twitchy.
    const mean = segments / joints;
    try testing.expect(mean >= 4 and mean <= 20);
}

test "instance count stays bounded by the box over a long fuzz" {
    const h = try harness(testing.allocator, .{ 8, 8, 8 }, 0x5EED, .{ .max_runs = 5 });
    defer destroy(h, testing.allocator);

    const capacity = h.walker.grid.cellCount();
    var live: usize = 0;
    var peak: usize = 0;

    for (0..50_000) |_| {
        for (h.walker.tick().items()) |event| switch (event) {
            .reset => live = 0,
            .segment, .joint, .teapot => live += 1,
        };
        peak = @max(peak, live);
    }
    // Each claimed cell yields at most one segment plus one joint.
    try testing.expect(peak <= capacity * 2);
}

fn countTeapots(h: *Harness, ticks: usize) struct { teapots: usize, joints: usize } {
    var teapots: usize = 0;
    var joints: usize = 0;
    for (0..ticks) |_| {
        for (h.walker.tick().items()) |event| switch (event) {
            .teapot => teapots += 1,
            .joint => joints += 1,
            .segment, .reset => {},
        };
    }
    return .{ .teapots = teapots, .joints = joints };
}

test "a teapot percent of zero hides the easter egg entirely" {
    const h = try harness(testing.allocator, .{ 20, 20, 20 }, 0x7EA, .{
        .max_runs = 10_000,
        .teapot_percent = 0,
    });
    defer destroy(h, testing.allocator);

    const counted = countTeapots(h, 20_000);
    try testing.expectEqual(@as(usize, 0), counted.teapots);
    try testing.expect(counted.joints > 0);
}

test "a teapot percent of a hundred replaces every elbow" {
    const h = try harness(testing.allocator, .{ 20, 20, 20 }, 0x7EA, .{
        .max_runs = 10_000,
        .teapot_percent = 100,
    });
    defer destroy(h, testing.allocator);

    const counted = countTeapots(h, 5_000);
    try testing.expect(counted.teapots > 0);
    // Run caps are still balls; only elbows become teapots, so joints remain.
    try testing.expect(counted.joints > 0);
}

test "the default rate is rare but not vanishing" {
    const h = try harness(testing.allocator, .{ 30, 30, 30 }, 0xBADA55, .{
        .max_runs = 10_000,
        .min_length = 200,
        .max_length = 200,
    });
    defer destroy(h, testing.allocator);

    const counted = countTeapots(h, 40_000);
    const total = counted.teapots + counted.joints;
    try testing.expect(total > 1_000);

    // Wide bounds on purpose: this pins the joke as an occasional surprise
    // rather than asserting an exact rate, since run caps dilute it.
    const per_mille = counted.teapots * 1000 / total;
    try testing.expect(per_mille > 2 and per_mille < 60);
}
