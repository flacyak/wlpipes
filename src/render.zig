//! Draws the scene. Stage 3 shows one lit cylinder and one lit sphere to
//! prove the shader and the mesh generators; instancing arrives in stage 4.

const std = @import("std");
const gl = @import("gl/api.zig");
const c = gl.c;
const buffer = @import("gl/buffer.zig");
const shader = @import("gl/shader.zig");
const math = @import("math.zig");
const mesh_mod = @import("mesh.zig");

const vertex_source = @embedFile("shaders/pipe.vert");
const fragment_source = @embedFile("shaders/pipe.frag");

/// Vertical field of view, matching the original's 45 degree frustum.
const fov_y = std.math.pi / 4.0;
const near_plane = 0.1;
const far_plane = 100.0;

const Uniforms = struct {
    model_view: c.GLint,
    projection: c.GLint,
    color: c.GLint,
};

pub const Renderer = struct {
    program: shader.Program,
    uniforms: Uniforms,
    cylinder: buffer.Geometry,
    sphere: buffer.Geometry,

    pub fn deinit(self: *Renderer) void {
        self.cylinder.deinit();
        self.sphere.deinit();
        self.program.deinit();
    }
};

/// Compiles the shader and uploads the two static meshes. The CPU-side meshes
/// are freed here: once uploaded, only the GPU copies are ever drawn.
pub fn init(allocator: std.mem.Allocator) !Renderer {
    const program = try shader.build(vertex_source, fragment_source);
    errdefer program.deinit();

    var cylinder = try uploadCylinder(allocator);
    errdefer cylinder.deinit();
    var sphere = try uploadSphere(allocator);
    errdefer sphere.deinit();

    setUpPipelineState();
    return .{
        .program = program,
        .uniforms = .{
            .model_view = program.uniform("u_model_view"),
            .projection = program.uniform("u_projection"),
            .color = program.uniform("u_color"),
        },
        .cylinder = cylinder,
        .sphere = sphere,
    };
}

fn uploadCylinder(allocator: std.mem.Allocator) !buffer.Geometry {
    const mesh = try mesh_mod.cylinder(
        allocator,
        mesh_mod.pipe_radius,
        1.0,
        mesh_mod.default_facets,
    );
    defer mesh.deinit(allocator);
    return buffer.upload(mesh);
}

fn uploadSphere(allocator: std.mem.Allocator) !buffer.Geometry {
    const mesh = try mesh_mod.sphere(
        allocator,
        mesh_mod.elbow_radius,
        mesh_mod.default_stacks,
        mesh_mod.default_slices,
    );
    defer mesh.deinit(allocator);
    return buffer.upload(mesh);
}

/// Backface culling stays off: the tubes are open, so their inner walls are
/// visible at a run's ends and the shader lights them two-sided.
fn setUpPipelineState() void {
    c.glEnable(c.GL_DEPTH_TEST);
    c.glDepthFunc(c.GL_LESS);
    c.glDisable(c.GL_CULL_FACE);
    c.glClearColor(0.0, 0.0, 0.0, 1.0);
}

/// Draws one frame. `seconds` drives a slow turntable so the lighting can be
/// judged from every angle.
///
/// The sample scene is a pipe running into a ball joint: the same two shapes
/// the simulation will emit, arranged the way it will arrange them.
pub fn draw(self: *Renderer, width: u31, height: u31, seconds: f32) void {
    c.glViewport(0, 0, width, height);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    self.program.use();
    self.program.setMat4(self.uniforms.projection, projectionFor(width, height));

    const view = math.lookAt(
        math.Vec3.init(0, 0.7, 3.4),
        math.Vec3.zero,
        math.Vec3.init(0, 1, 0),
    );
    const turntable = math.multiply(view, math.rotationY(seconds * 0.5));
    const blue = math.Vec3.init(0.0, 0.0, 0.7);

    // A cell-long pipe laid along X, ending in the elbow ball at the origin.
    const along_x = math.multiply(
        math.translation(math.Vec3.init(-0.5, 0, 0)),
        math.rotationY(std.math.pi / 2.0),
    );
    drawShape(self, self.cylinder, turntable, along_x, blue);
    drawShape(self, self.sphere, turntable, math.identity, blue);

    // A second pipe leaving the joint along Z, so the elbow reads as an elbow.
    drawShape(self, self.cylinder, turntable, math.translation(math.Vec3.init(0, 0, 0.5)), blue);
}

fn drawShape(
    self: *Renderer,
    geometry: buffer.Geometry,
    view: math.Mat4,
    model: math.Mat4,
    color: math.Vec3,
) void {
    self.program.setMat4(self.uniforms.model_view, math.multiply(view, model));
    self.program.setVec3(self.uniforms.color, color);
    geometry.draw();
}

fn projectionFor(width: u31, height: u31) math.Mat4 {
    const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(@max(height, 1)));
    return math.perspective(fov_y, aspect, near_plane, far_plane);
}
