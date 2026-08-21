#version 300 es

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;

uniform mat4 u_model_view;
uniform mat4 u_projection;

out vec3 v_view_normal;

void main() {
    vec4 view_position = u_model_view * vec4(a_position, 1.0);

    // The model-view carries only rotation and translation, never a
    // non-uniform scale, so its upper-left 3x3 doubles as the normal matrix.
    v_view_normal = mat3(u_model_view) * a_normal;

    gl_Position = u_projection * view_position;
}
