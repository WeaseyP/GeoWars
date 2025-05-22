//------------------------------------------------------------------------------
//  math.odin
//
//  The Odin glsl math package doesn't use the same conventions as
//  HandmadeMath in the original sokol samples, so just replicate
//  HandmadeMath to be consistent.
//------------------------------------------------------------------------------
package sokol_math

import "core:math"

TAU :: 6.28318530717958647692528676655900576
PI  :: 3.14159265358979323846264338327950288

vec2 :: distinct [2]f32
vec3 :: distinct [3]f32
vec4 :: distinct [4]f32
mat4 :: distinct [4][4]f32

radians :: proc (degrees: f32) -> f32 { return degrees * TAU / 360.0 }

up :: proc () -> vec3 { return { 0.0, 1.0, 0.0 } }

dot :: proc{
    dot_vec3,
}
dot_vec3 :: proc(v0, v1: vec3) -> f32 { return v0.x*v1.x + v0.y*v1.y + v0.z*v1.z }

len :: proc{
    len_vec3,
}
len_vec3 :: proc(v: vec3) -> f32 { return math.sqrt(dot(v, v)) }

norm :: proc {
    norm_vec3,
}
norm_vec3 :: proc(v: vec3) -> vec3 {
    l := len(v)
    if (l != 0) {
        return { v.x/l, v.y/l, v.z/l }
    }
    else {
        return {}
    }
}

cross :: proc {
    cross_vec3,
}
cross_vec3 :: proc(v0, v1: vec3) -> vec3 {
    return {
        (v0.y * v1.z) - (v0.z * v1.y),
        (v0.z * v1.x) - (v0.x * v1.z),
        (v0.x * v1.y) - (v0.y * v1.x),
    }
}
angle_to_vec2 :: proc "contextless" (angle_radians: f32) -> vec2 {
    // Use core:math's functions unless your 'm' package redefines them for f32
    c := math.cos(angle_radians) 
    s := math.sin(angle_radians)
    // Assuming vec2 is defined as [2]f32 or similar struct in your 'm' package
    return vec2{c, s}; 
}

dist_sq_vec2 :: proc(a, b: vec2) -> f32 {
    diff_x := a.x - b.x
    diff_y := a.y - b.y
    return diff_x * diff_x + diff_y * diff_y
}

identity :: proc {
    identity_mat4,
}
identity_mat4 :: proc() -> mat4 {
    m : mat4 = {}
    m[0][0] = 1.0
    m[1][1] = 1.0
    m[2][2] = 1.0
    m[3][3] = 1.0
    return m
}

persp :: proc {
    persp_mat4,
}
persp_mat4 :: proc(fov, aspect, near, far: f32) -> mat4 {
    m := identity()
    t := math.tan(fov * (PI / 360))
    m[0][0] = 1.0 / t
    m[1][1] = aspect / t
    m[2][3] = -1.0
    m[2][2] = (near + far) / (near - far)
    m[3][2] = (2.0 * near * far) / (near - far)
    m[3][3] = 0
    return m
}
lerp :: proc "contextless" (a, b: $T, t: $E) -> (x: T) {
    // Ensure T supports multiplication with (1-t) and t, and addition.
    // Ensure E can be subtracted from 1.
    // For f32, this works perfectly.
    return a*(1-t) + b*t;
}

lookat :: proc {
    lookat_mat4,
}
lookat_mat4 :: proc(eye, center, up: vec3) -> mat4 {
    m := mat4 {}
    f := norm(center - eye)
    s := norm(cross(f, up))
    u := cross(s, f)

    m[0][0] = s.x
    m[0][1] = u.x
    m[0][2] = -f.x

    m[1][0] = s.y
    m[1][1] = u.y
    m[1][2] = -f.y

    m[2][0] = s.z
    m[2][1] = u.z
    m[2][2] = -f.z

    m[3][0] = -dot(s, eye)
    m[3][1] = -dot(u, eye)
    m[3][2] = dot(f, eye)
    m[3][3] = 1.0

    return m
}
hash11 :: proc(p: f32) -> f32 {
    // GLSL: fract(sin(p * 78.233) * 43758.5453);
    h := math.sin(p * 78.233) * 43758.5453;
    return h - math.floor(h); // Odin equivalent of fract()
}

rotate :: proc{
    rotate_mat4,
}
rotate_mat4 :: proc (angle: f32, axis_unorm: vec3) -> mat4 {
    m := identity()

    axis := norm(axis_unorm)
    sin_theta := math.sin(radians(angle))
    cos_theta := math.cos(radians(angle))
    cos_value := 1.0 - cos_theta;

    m[0][0] = (axis.x * axis.x * cos_value) + cos_theta
    m[0][1] = (axis.x * axis.y * cos_value) + (axis.z * sin_theta)
    m[0][2] = (axis.x * axis.z * cos_value) - (axis.y * sin_theta)
    m[1][0] = (axis.y * axis.x * cos_value) - (axis.z * sin_theta)
    m[1][1] = (axis.y * axis.y * cos_value) + cos_theta
    m[1][2] = (axis.y * axis.z * cos_value) + (axis.x * sin_theta)
    m[2][0] = (axis.z * axis.x * cos_value) + (axis.y * sin_theta)
    m[2][1] = (axis.z * axis.y * cos_value) - (axis.x * sin_theta)
    m[2][2] = (axis.z * axis.z * cos_value) + cos_theta

    return m
}
// Add this procedure for Orthographic Projection
ortho :: proc {
    ortho_mat4,
}
ortho_mat4 :: proc (left, right, bottom, top, near, far: f32) -> mat4 {
    m := identity() // Start with identity

    // Calculate differences
    rl := right - left
    tb := top - bottom
    fn := far - near

    // Set the specific elements for orthographic projection
    // Assuming column-major layout as suggested by mul_mat4
    m[0][0] = 2.0 / rl
    m[1][1] = 2.0 / tb
    m[2][2] = -2.0 / fn // Use -2.0 for right-handed coords (like OpenGL/Sokol default)
    m[3][0] = -(right + left) / rl
    m[3][1] = -(top + bottom) / tb
    m[3][2] = -(far + near) / fn
    // m[3][3] remains 1.0 from identity

    return m
}
vec2_zero :: proc() -> vec2 { return {0.0, 0.0} }

dot_vec2 :: proc(a, b: vec2) -> f32 {
    return a.x * b.x + a.y * b.y
}

len_sq_vec2 :: proc(v: vec2) -> f32 { // Length squared (cheaper than len)
    return dot_vec2(v, v)
}

len_vec2 :: proc(v: vec2) -> f32 {
    return math.sqrt(len_sq_vec2(v))
}

norm_vec2 :: proc(v: vec2) -> vec2 { // Normalize
    l := len_vec2(v)
    if l > 0.00001 { // Avoid division by zero
        inv_l := 1.0 / l
        return v * inv_l
    } else {
        return {0.0, 0.0}
    }
}

// Add this procedure for Scaling
scale :: proc {
    scale_mat4,
}
scale_mat4 :: proc (v: vec3) -> mat4 {
    m := identity() // Start with identity

    // Set diagonal elements for scaling
    m[0][0] = v.x
    m[1][1] = v.y
    m[2][2] = v.z
    // m[3][3] remains 1.0 from identity

    return m
}

translate :: proc{
    translate_mat4,
}
translate_mat4 :: proc (translation: vec3) -> mat4 {
    m := identity()
    m[3][0] = translation.x
    m[3][1] = translation.y
    m[3][2] = translation.z
    return m
}

mul :: proc{
    mul_mat4,
}
mul_mat4 :: proc (left, right: mat4) -> mat4 {
    m := mat4 {}
    for col := 0; col < 4; col += 1 {
        for row := 0; row < 4; row += 1 {
            m[col][row] = left[0][row] * right[col][0] +
                          left[1][row] * right[col][1] +
                          left[2][row] * right[col][2] +
                          left[3][row] * right[col][3];
        }
    }
    return m
}
