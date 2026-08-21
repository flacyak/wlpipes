//! Draws the scene as two instanced calls: one for every pipe segment, one for
//! every joint ball. Stage 4 fills them from a fixed demo path; stage 5 hands
//! the job to the simulation.

const std = @import("std");
const gl = @import("gl/api.zig");
const c = gl.c;
const buffer = @import("gl/buffer.zig");
const instances = @import("gl/instances.zig");
const shader = @import("gl/shader.zig");
const camera_mod = @import("camera.zig");
const math = @import("math.zig");
const mesh_mod = @import("mesh.zig");

const vertex_source = @embedFile("shaders/pipe.vert");
const fragment_source = @embedFile("shaders/pipe.frag");

pub const Instance = instances.Instance;
pub const Axis = instances.Axis;

const Uniforms = struct {
    view: c.GLint,
    projection: c.GLint,
};

pub const Renderer = struct {
    program: shader.Program,
    uniforms: Uniforms,
    cylinder: buffer.Geometry,
    sphere: buffer.Geometry,
    segments: instances.Batch,
    joints: instances.Batch,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Renderer) void {
        self.segments.deinit(self.allocator);
        self.joints.deinit(self.allocator);
        self.cylinder.deinit();
        self.sphere.deinit();
        self.program.deinit();
    }

    pub fn addSegment(self: *Renderer, instance: Instance) !void {
        try self.segments.append(self.allocator, instance);
    }

    pub fn addJoint(self: *Renderer, instance: Instance) !void {
        try self.joints.append(self.allocator, instance);
    }

    /// Empties the scene, keeping both allocations for the next one.
    pub fn clear(self: *Renderer) void {
        self.segments.clear();
        self.joints.clear();
    }

    pub fn isEmpty(self: Renderer) bool {
        return self.segments.count() == 0 and self.joints.count() == 0;
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

    const segments = instances.create();
    const joints = instances.create();
    cylinder.attachInstances(segments);
    sphere.attachInstances(joints);

    setUpPipelineState();
    return .{
        .program = program,
        .uniforms = .{
            .view = program.uniform("u_view"),
            .projection = program.uniform("u_projection"),
        },
        .cylinder = cylinder,
        .sphere = sphere,
        .segments = segments,
        .joints = joints,
        .allocator = allocator,
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

/// Draws one frame: two instanced calls regardless of how full the box is.
pub fn draw(self: *Renderer, width: u31, height: u31, camera: camera_mod.Camera) void {
    c.glViewport(0, 0, width, height);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    instances.upload(&self.segments);
    instances.upload(&self.joints);

    self.program.use();
    self.program.setMat4(self.uniforms.projection, camera.projection);
    self.program.setMat4(self.uniforms.view, camera.view);

    self.cylinder.drawInstanced(self.segments.count());
    self.sphere.drawInstanced(self.joints.count());
}
