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
    dot_vec2,
}
dot_vec3 :: proc(v0, v1: vec3) -> f32 { return v0.x*v1.x + v0.y*v1.y + v0.z*v1.z }
dot_vec2 :: proc(v0, v1: vec2) -> f32 { return v0.x*v1.x + v0.y*v1.y }

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
    // For scalar types, this is trivially true.
    // For vector types, they should support element-wise operations.
    // The implementation assumes standard lerp behavior: a * (1 - t) + b * t
    return a * (1 - t) + b * t
}

translate :: proc(v: vec3) -> mat4 {
    m := identity()
    m[3][0] = v.x
    m[3][1] = v.y
    m[3][2] = v.z
    return m
}
scale :: proc(s: vec3) -> mat4 {
    m := identity()
    m[0][0] = s.x
    m[1][1] = s.y
    m[2][2] = s.z
    return m
}
rotate :: proc(angle: f32, v: vec3) -> mat4 {
    c := math.cos(angle)
    s := math.sin(angle)
    axis := norm(v)
    t := 1.0 - c

    m : mat4 = {}
    m[0][0] = t * axis.x * axis.x + c
    m[0][1] = t * axis.x * axis.y + s * axis.z
    m[0][2] = t * axis.x * axis.z - s * axis.y
    m[0][3] = 0.0

    m[1][0] = t * axis.x * axis.y - s * axis.z
    m[1][1] = t * axis.y * axis.y + c
    m[1][2] = t * axis.y * axis.z + s * axis.x
    m[1][3] = 0.0

    m[2][0] = t * axis.x * axis.z + s * axis.y
    m[2][1] = t * axis.y * axis.z - s * axis.x
    m[2][2] = t * axis.z * axis.z + c
    m[2][3] = 0.0

    m[3][0] = 0.0
    m[3][1] = 0.0
    m[3][2] = 0.0
    m[3][3] = 1.0

    return m
}

lookat :: proc(eye, center, up: vec3) -> mat4 {
    f := norm(center - eye)
    s := norm(cross(f, up))
    u := cross(s, f)

    m := identity()
    m[0][0] = s.x
    m[1][0] = s.y
    m[2][0] = s.z
    m[0][1] = u.x
    m[1][1] = u.y
    m[2][1] = u.z
    m[0][2] = -f.x
    m[1][2] = -f.y
    m[2][2] = -f.z
    m[3][0] = -dot(s, eye)
    m[3][1] = -dot(u, eye)
    m[3][2] = dot(f, eye)
    
    return m
}

mul :: proc(m0, m1: mat4) -> mat4 {
    m : mat4 = {}
    for i in 0..<4 {
        for j in 0..<4 {
            m[i][j] = m0[i][0]*m1[0][j] +
                      m0[i][1]*m1[1][j] +
                      m0[i][2]*m1[2][j] +
                      m0[i][3]*m1[3][j]
        }
    }
    return m
}

ortho :: proc(l, r, b, t, n, f: f32) -> mat4 {
    m : mat4 = {}
    m[0][0] = 2.0 / (r - l)
    m[1][1] = 2.0 / (t - b)
    m[2][2] = -2.0 / (f - n)
    m[3][0] = -(r + l) / (r - l)
    m[3][1] = -(t + b) / (t - b)
    m[3][2] = -(f + n) / (f - n)
    m[3][3] = 1.0
    return m
}

mod :: proc(x, y: f32) -> f32 {
    return x - y * math.floor(x / y)
}

len_sq_vec2 :: proc(v: vec2) -> f32 {
    return v.x*v.x + v.y*v.y
}

norm_vec2 :: proc(v: vec2) -> vec2 {
    l := math.sqrt(v.x*v.x + v.y*v.y)
    if l != 0 {
        return {v.x/l, v.y/l}
    }
    return {0, 0}
}
