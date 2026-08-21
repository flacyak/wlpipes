#version 300 es
precision highp float;

in vec3 v_view_normal;
in vec3 v_color;
out vec4 frag_color;

// Ported from the fixed-function setup in the original OpenGL screensaver
// (xscreensaver's pipes.c keeps the same values).
const vec3  material_ambient  = vec3(0.2);   // GL's default GL_AMBIENT
const vec3  material_specular = vec3(0.7);   // front_specular
const float shininess         = 60.0;        // front_shininess
const vec3  global_ambient    = vec3(0.5);   // lmodel_ambient

// Positions with w = 0 in the original, i.e. directional lights. Note only
// GL_LIGHT0 gets a specular term: OpenGL defaults light 0's specular to white
// and every other light's to black, and the original never overrides it. That
// asymmetry is what gives the pipes a single clean highlight.
const vec3 light0_direction = vec3( 1.0,  1.0, 1.0);
const vec3 light0_ambient   = vec3(0.4);
const vec3 light0_diffuse   = vec3(1.0);
const vec3 light0_specular  = vec3(1.0);

const vec3 light1_direction = vec3(-1.0, -1.0, 1.0);
const vec3 light1_ambient   = vec3(0.2);
const vec3 light1_diffuse   = vec3(0.5);
const vec3 light1_specular  = vec3(0.0);

// GL_LIGHT_MODEL_LOCAL_VIEWER is left false in the original, so the eye
// direction is a constant +z in view space rather than a per-pixel vector.
const vec3 eye_direction = vec3(0.0, 0.0, 1.0);

vec3 lightContribution(vec3 normal, vec3 direction, vec3 ambient, vec3 diffuse, vec3 specular) {
    vec3 light = normalize(direction);
    float lambert = max(dot(normal, light), 0.0);

    vec3 result = ambient * material_ambient + diffuse * v_color * lambert;
    if (lambert > 0.0) {
        vec3 halfway = normalize(light + eye_direction);
        float highlight = pow(max(dot(normal, halfway), 0.0), shininess);
        result += specular * material_specular * highlight;
    }
    return result;
}

void main() {
    vec3 normal = normalize(v_view_normal);

    // GL_LIGHT_MODEL_TWO_SIDE is true in the original: the open ends of a tube
    // show their inner wall, which must be lit as though it faced us.
    if (!gl_FrontFacing) {
        normal = -normal;
    }

    vec3 color = global_ambient * material_ambient;
    color += lightContribution(normal, light0_direction, light0_ambient, light0_diffuse, light0_specular);
    color += lightContribution(normal, light1_direction, light1_ambient, light1_diffuse, light1_specular);

    frag_color = vec4(color, 1.0);
}
