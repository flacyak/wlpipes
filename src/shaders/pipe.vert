#version 300 es

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;

// Per instance, stepped once per segment rather than once per vertex.
layout(location = 2) in vec3 a_center;
layout(location = 3) in vec3 a_color;
layout(location = 4) in uint a_axis;

uniform mat4 u_view;
uniform mat4 u_projection;

out vec3 v_view_normal;
out vec3 v_color;

// Pipe segments are always axis aligned, so the instance carries an axis index
// instead of a model matrix. Both branches are proper rotations of the meshes'
// local +z onto the target axis, so normals rotate the same way as positions.
vec3 orient(vec3 v, uint axis) {
    if (axis == 0u) return vec3(v.z, v.y, -v.x);  // +z onto +x
    if (axis == 1u) return vec3(v.x, v.z, -v.y);  // +z onto +y
    return v;                                      // already along +z
}

void main() {
    vec3 world_position = orient(a_position, a_axis) + a_center;
    vec3 world_normal = orient(a_normal, a_axis);

    // The view matrix carries only rotation and translation, never a
    // non-uniform scale, so its upper-left 3x3 doubles as the normal matrix.
    v_view_normal = mat3(u_view) * world_normal;
    v_color = a_color;

    gl_Position = u_projection * u_view * vec4(world_position, 1.0);
}
