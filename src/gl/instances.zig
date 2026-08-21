//! A growable buffer of per-instance attributes.
//!
//! Pipes only ever grow, so the buffer appends and uploads just the new tail.
//! Clearing a scene keeps the allocation, both on the CPU and on the GPU, so a
//! long-running screensaver stops reallocating after its first full box.

const std = @import("std");
const gl = @import("api.zig");
const c = gl.c;

/// Instance attribute slots, continuing after the per-vertex ones in
/// gl/buffer.zig.
pub const attrib_center: c.GLuint = 2;
pub const attrib_color: c.GLuint = 3;
pub const attrib_axis: c.GLuint = 4;

/// Segments are always axis aligned, so an axis index replaces what would
/// otherwise be a full model matrix: 28 bytes per instance instead of 76.
pub const Axis = enum(u32) { x = 0, y = 1, z = 2 };

pub const Instance = extern struct {
    center: [3]f32,
    color: [3]f32,
    axis: u32,
};

pub const Batch = struct {
    items: std.ArrayList(Instance) = .empty,
    buffer: c.GLuint = 0,
    /// Bytes currently allocated on the GPU.
    capacity_bytes: usize = 0,
    /// Instances already copied to the GPU; the rest are a pending tail.
    uploaded: usize = 0,

    pub fn deinit(self: *Batch, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        if (self.buffer != 0) c.glDeleteBuffers(1, &self.buffer);
    }

    pub fn append(self: *Batch, allocator: std.mem.Allocator, instance: Instance) !void {
        try self.items.append(allocator, instance);
    }

    /// Drops every instance but keeps both allocations for the next scene.
    pub fn clear(self: *Batch) void {
        self.items.clearRetainingCapacity();
        self.uploaded = 0;
    }

    pub fn count(self: Batch) c.GLsizei {
        return @intCast(self.items.items.len);
    }
};

pub fn create() Batch {
    var batch: Batch = .{};
    c.glGenBuffers(1, &batch.buffer);
    return batch;
}

/// Copies any instances added since the last call. Reallocates only when the
/// buffer has genuinely outgrown the GPU allocation.
pub fn upload(batch: *Batch) void {
    const items = batch.items.items;
    if (items.len == batch.uploaded) return;

    c.glBindBuffer(c.GL_ARRAY_BUFFER, batch.buffer);
    const needed = items.len * @sizeOf(Instance);

    if (needed > batch.capacity_bytes) {
        growAndUpload(batch, items, needed);
    } else {
        uploadTail(batch, items);
    }
    batch.uploaded = items.len;
}

fn growAndUpload(batch: *Batch, items: []const Instance, needed: usize) void {
    const capacity = nextCapacity(batch.capacity_bytes, needed);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(capacity), null, c.GL_DYNAMIC_DRAW);
    c.glBufferSubData(c.GL_ARRAY_BUFFER, 0, @intCast(needed), items.ptr);
    batch.capacity_bytes = capacity;
}

/// Doubles the allocation rather than fitting it exactly, so a growing scene
/// reallocates a logarithmic number of times instead of once per segment.
fn nextCapacity(current_bytes: usize, needed_bytes: usize) usize {
    const minimum = 64 * @sizeOf(Instance);
    return @max(needed_bytes, @max(current_bytes * 2, minimum));
}

fn uploadTail(batch: *Batch, items: []const Instance) void {
    const offset = batch.uploaded * @sizeOf(Instance);
    const length = (items.len - batch.uploaded) * @sizeOf(Instance);
    c.glBufferSubData(
        c.GL_ARRAY_BUFFER,
        @intCast(offset),
        @intCast(length),
        items.ptr + batch.uploaded,
    );
}

/// Binds the instance attributes into the currently bound VAO, one step per
/// instance rather than per vertex.
pub fn describeLayout(batch: Batch) void {
    const stride = @sizeOf(Instance);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, batch.buffer);

    bindFloats(attrib_center, 3, stride, @offsetOf(Instance, "center"));
    bindFloats(attrib_color, 3, stride, @offsetOf(Instance, "color"));

    // Integer attributes need glVertexAttribIPointer; the float entry point
    // would silently convert and the shader would read garbage.
    c.glEnableVertexAttribArray(attrib_axis);
    c.glVertexAttribIPointer(
        attrib_axis,
        1,
        c.GL_UNSIGNED_INT,
        stride,
        @ptrFromInt(@offsetOf(Instance, "axis")),
    );
    c.glVertexAttribDivisor(attrib_axis, 1);
}

fn bindFloats(location: c.GLuint, size: c.GLint, stride: c.GLsizei, offset: usize) void {
    c.glEnableVertexAttribArray(location);
    c.glVertexAttribPointer(location, size, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(offset));
    c.glVertexAttribDivisor(location, 1);
}

const testing = std.testing;

test "instance layout is the compact one the shader expects" {
    // 28 bytes, versus 76 if each instance carried a full model matrix.
    try testing.expectEqual(@as(usize, 28), @sizeOf(Instance));
    try testing.expectEqual(@as(usize, 0), @offsetOf(Instance, "center"));
    try testing.expectEqual(@as(usize, 12), @offsetOf(Instance, "color"));
    try testing.expectEqual(@as(usize, 24), @offsetOf(Instance, "axis"));
}

test "axis indices match the shader's branches" {
    try testing.expectEqual(@as(u32, 0), @intFromEnum(Axis.x));
    try testing.expectEqual(@as(u32, 1), @intFromEnum(Axis.y));
    try testing.expectEqual(@as(u32, 2), @intFromEnum(Axis.z));
}

test "capacity grows geometrically, never shrinking" {
    const minimum = 64 * @sizeOf(Instance);
    try testing.expectEqual(minimum, nextCapacity(0, 1));
    try testing.expectEqual(minimum, nextCapacity(0, minimum));

    // Doubling covers the request.
    try testing.expectEqual(@as(usize, 2000), nextCapacity(1000, 1500));
    // A request larger than double is honoured exactly.
    try testing.expectEqual(@as(usize, 9000), nextCapacity(1000, 9000));
}

test "capacity reaches a full box in a handful of reallocations" {
    // A 26x20x26 grid is 13520 cells, so at most that many segments.
    const target = 13_520 * @sizeOf(Instance);
    var capacity: usize = 0;
    var reallocations: usize = 0;

    while (capacity < target) : (reallocations += 1) {
        capacity = nextCapacity(capacity, capacity + 1);
    }
    try testing.expect(reallocations <= 10);
}

test "clearing keeps the allocation for the next scene" {
    var batch: Batch = .{};
    defer batch.deinit(testing.allocator);

    for (0..500) |i| {
        try batch.append(testing.allocator, .{
            .center = .{ @floatFromInt(i), 0, 0 },
            .color = .{ 1, 0, 0 },
            .axis = @intFromEnum(Axis.x),
        });
    }
    const grown = batch.items.capacity;
    try testing.expectEqual(@as(c.GLsizei, 500), batch.count());

    batch.clear();
    try testing.expectEqual(@as(c.GLsizei, 0), batch.count());
    try testing.expectEqual(@as(usize, 0), batch.uploaded);
    // The point of clearRetainingCapacity: a screensaver that resets its box
    // every few minutes must not reallocate every time.
    try testing.expectEqual(grown, batch.items.capacity);
}
