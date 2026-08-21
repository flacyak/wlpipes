//! A mesh uploaded to the GPU: one VAO binding a vertex buffer and an index
//! buffer, ready to draw.

const std = @import("std");
const gl = @import("api.zig");
const c = gl.c;
const mesh_mod = @import("../mesh.zig");
const instances = @import("instances.zig");

/// Vertex attribute slots, matching the `layout(location = ...)` in pipe.vert.
pub const attrib_position: c.GLuint = 0;
pub const attrib_normal: c.GLuint = 1;

pub const Geometry = struct {
    vao: c.GLuint,
    vertex_buffer: c.GLuint,
    index_buffer: c.GLuint,
    index_count: c.GLsizei,

    pub fn deinit(self: *Geometry) void {
        c.glDeleteVertexArrays(1, &self.vao);
        c.glDeleteBuffers(1, &self.vertex_buffer);
        c.glDeleteBuffers(1, &self.index_buffer);
    }

    /// Binds a batch's attributes into this VAO. Call once at startup; the
    /// VAO remembers the binding, so drawing does not re-specify it.
    pub fn attachInstances(self: Geometry, batch: instances.Batch) void {
        c.glBindVertexArray(self.vao);
        instances.describeLayout(batch);
        c.glBindVertexArray(0);
    }

    pub fn drawInstanced(self: Geometry, count: c.GLsizei) void {
        if (count == 0) return;
        c.glBindVertexArray(self.vao);
        c.glDrawElementsInstanced(
            c.GL_TRIANGLES,
            self.index_count,
            c.GL_UNSIGNED_SHORT,
            null,
            count,
        );
    }
};

/// Uploads a mesh. The CPU-side mesh may be freed immediately afterwards.
pub fn upload(mesh: mesh_mod.Mesh) Geometry {
    var geometry: Geometry = .{
        .vao = 0,
        .vertex_buffer = 0,
        .index_buffer = 0,
        .index_count = @intCast(mesh.indices.len),
    };

    c.glGenVertexArrays(1, &geometry.vao);
    c.glBindVertexArray(geometry.vao);

    geometry.vertex_buffer = uploadVertices(mesh.vertices);
    geometry.index_buffer = uploadIndices(mesh.indices);
    describeVertexLayout();

    c.glBindVertexArray(0);
    return geometry;
}

fn uploadVertices(vertices: []const mesh_mod.Vertex) c.GLuint {
    var buffer: c.GLuint = 0;
    c.glGenBuffers(1, &buffer);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, buffer);
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        @intCast(vertices.len * @sizeOf(mesh_mod.Vertex)),
        vertices.ptr,
        c.GL_STATIC_DRAW,
    );
    return buffer;
}

/// The element buffer binding is captured by the VAO, so this must be called
/// while the VAO is bound.
fn uploadIndices(indices: []const u16) c.GLuint {
    var buffer: c.GLuint = 0;
    c.glGenBuffers(1, &buffer);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, buffer);
    c.glBufferData(
        c.GL_ELEMENT_ARRAY_BUFFER,
        @intCast(indices.len * @sizeOf(u16)),
        indices.ptr,
        c.GL_STATIC_DRAW,
    );
    return buffer;
}

fn describeVertexLayout() void {
    const stride = @sizeOf(mesh_mod.Vertex);
    c.glEnableVertexAttribArray(attrib_position);
    c.glVertexAttribPointer(attrib_position, 3, c.GL_FLOAT, c.GL_FALSE, stride, null);

    c.glEnableVertexAttribArray(attrib_normal);
    c.glVertexAttribPointer(
        attrib_normal,
        3,
        c.GL_FLOAT,
        c.GL_FALSE,
        stride,
        @ptrFromInt(@offsetOf(mesh_mod.Vertex, "normal")),
    );
}
