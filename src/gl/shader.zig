//! Shader compilation and linking, with the driver's diagnostics surfaced.

const std = @import("std");
const gl = @import("api.zig");
const c = gl.c;
const math = @import("../math.zig");

pub const Error = error{ CompileFailed, LinkFailed };

/// Longest driver message we will echo. Anything longer is truncated: the
/// first line is invariably the one that matters.
const log_limit = 2048;

pub const Program = struct {
    id: c.GLuint,

    pub fn deinit(self: Program) void {
        c.glDeleteProgram(self.id);
    }

    pub fn use(self: Program) void {
        c.glUseProgram(self.id);
    }

    pub fn uniform(self: Program, name: [*:0]const u8) c.GLint {
        return c.glGetUniformLocation(self.id, name);
    }

    pub fn setMat4(_: Program, location: c.GLint, matrix: math.Mat4) void {
        c.glUniformMatrix4fv(location, 1, c.GL_FALSE, &matrix);
    }

    pub fn setVec3(_: Program, location: c.GLint, v: math.Vec3) void {
        c.glUniform3f(location, v.x, v.y, v.z);
    }
};

/// Compiles and links a vertex/fragment pair. The shaders are detached and
/// deleted once linked; the driver keeps them alive until then.
pub fn build(vertex_source: [:0]const u8, fragment_source: [:0]const u8) Error!Program {
    const vertex = try compile(c.GL_VERTEX_SHADER, vertex_source);
    defer c.glDeleteShader(vertex);

    const fragment = try compile(c.GL_FRAGMENT_SHADER, fragment_source);
    defer c.glDeleteShader(fragment);

    return try link(vertex, fragment);
}

fn compile(stage: c.GLenum, source: [:0]const u8) Error!c.GLuint {
    const shader = c.glCreateShader(stage);
    errdefer c.glDeleteShader(shader);

    const pointer: [*c]const u8 = source.ptr;
    c.glShaderSource(shader, 1, &pointer, null);
    c.glCompileShader(shader);

    var status: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);
    if (status == c.GL_TRUE) return shader;

    reportShaderLog(shader, stageName(stage));
    return Error.CompileFailed;
}

fn link(vertex: c.GLuint, fragment: c.GLuint) Error!Program {
    const program = c.glCreateProgram();
    errdefer c.glDeleteProgram(program);

    c.glAttachShader(program, vertex);
    c.glAttachShader(program, fragment);
    c.glLinkProgram(program);
    c.glDetachShader(program, vertex);
    c.glDetachShader(program, fragment);

    var status: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &status);
    if (status == c.GL_TRUE) return .{ .id = program };

    reportProgramLog(program);
    return Error.LinkFailed;
}

fn stageName(stage: c.GLenum) []const u8 {
    return if (stage == c.GL_VERTEX_SHADER) "vertex" else "fragment";
}

fn reportShaderLog(shader: c.GLuint, stage: []const u8) void {
    var buffer: [log_limit]u8 = undefined;
    var length: c.GLsizei = 0;
    c.glGetShaderInfoLog(shader, buffer.len, &length, &buffer);
    std.log.err("{s} shader failed to compile:\n{s}", .{ stage, buffer[0..@intCast(length)] });
}

fn reportProgramLog(program: c.GLuint) void {
    var buffer: [log_limit]u8 = undefined;
    var length: c.GLsizei = 0;
    c.glGetProgramInfoLog(program, buffer.len, &length, &buffer);
    std.log.err("program failed to link:\n{s}", .{buffer[0..@intCast(length)]});
}
