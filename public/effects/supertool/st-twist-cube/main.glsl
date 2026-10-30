// Imported from SuperTool effects/TwistFMSCat1.glsl by scripts/import-supertool.mjs

// Analys cube
// SuperTool intake note: ported from DISCO-GLSL-Video-Processor (Shaders/Twist-FMSCat1.glsl).
// Original "Analys cube" (c) 2019 FMS_Cat, MIT. #version / standard + audio uniform
// / in-out decls dropped (GLSLRenderer injects standard ones). DISCO host audio
// uniforms bassLevel/midLevel become mutable globals set from audioBand() at the
// top of mainImage (read via getBass/getMid); trebleLevel was unused and dropped.
// iChannel0 = the layer-below video, mapped onto the raymarched cube faces.
// DISCO fragCoord ((v_text.x,1-v_text.y)*res) equals SuperTool raw fragCoord.

// (c) 2019 FMS_Cat, MIT License
// Converted for DISCO - Audio reactive 3D raymarched cube with video texture mapping

// =================================================================================================
// == DISCO UNIFORMS ==============================================================================
// =================================================================================================

// Audio levels — filled from injected FFT helpers in mainImage; read as globals.
float bassLevel = 0.0;
float midLevel = 0.0;

// User-controllable parameters
uniform float cubeSize;
uniform float rotationSpeed;
uniform float twistAmount;
uniform float twistSpeed;
uniform float audioTwistStrength;
uniform float kickEnabled;
uniform float kickStrength;
uniform float deformAmount;
uniform float fractalEnabled;
uniform float fractalIntensity;
uniform float edgeGlow;
uniform float fovPulse;
uniform float fogDensity;
uniform float bpm;


// =================================================================================================
// == INTERNAL CALCULATIONS =======================================================================
// =================================================================================================
#define HALF_PI 1.57079632679
#define PI 3.14159265359
#define TAU 6.28318530718
#define saturate(i) clamp(i, 0., 1.)
#define linearstep(a,b,t) saturate(((t)-(a))/((b)-(a)))

// Raymarch settings
#define MARCH_ITER 64
#define MARCH_EPSILON 1E-4
#define MARCH_NEAR 0.01
#define MARCH_FAR 40.0
#define MARCH_MULP 0.6

// =================================================================================================
// == AUDIO HELPERS (using DISCO uniforms) ========================================================
// =================================================================================================
float getBass() {
    return bassLevel;
}

float getMid() {
    return midLevel;
}

// =================================================================================================
// == COMPUTED VALUES (from uniforms) =============================================================
// =================================================================================================
float BEAT() {
    return iTime * bpm / 60.0;
}

float FX_KICK() {
    return kickEnabled > 0.5 ? kickStrength * exp(-3.0 * mod(BEAT(), 4.0)) : 0.0;
}

float FX_TWIST() {
    return twistAmount * sin(BEAT() * twistSpeed) + audioTwistStrength * getMid();
}

// =================================================================================================
// == COMMON FUNCTIONS ============================================================================
// =================================================================================================
mat2 rotate2D(float t) {
    return mat2(cos(t), -sin(t), sin(t), cos(t));
}

// =================================================================================================
// == CAMERA ======================================================================================
// =================================================================================================
struct Camera {
    vec3 pos;
    vec3 dir;
    vec3 up;
    float roll;
    float fov;
};

Camera newCamera(vec3 pos, vec3 dir) {
    Camera camera;
    camera.pos = pos;
    camera.dir = dir;
    camera.up = vec3(0.0, 1.0, 0.0);
    camera.roll = 0.0;
    camera.fov = 0.5;
    return camera;
}

// =================================================================================================
// == RAY =========================================================================================
// =================================================================================================
struct Ray {
    vec3 orig;
    vec3 dir;
};

Ray newRay(vec3 ori, vec3 dir) {
    Ray ray;
    ray.orig = ori;
    ray.dir = dir;
    return ray;
}

Ray rayFromCamera(Camera camera, vec2 p) {
    vec3 dirX = normalize(cross(camera.dir, camera.up));
    vec3 dirY = cross(dirX, camera.dir);
    vec2 pt = rotate2D(camera.roll) * p;
    return newRay(
        camera.pos,
        normalize(pt.x * dirX + pt.y * dirY + camera.dir / tan(camera.fov))
    );
}

vec3 getRayPosition(Ray ray, float len) {
    return ray.orig + ray.dir * len;
}

// =================================================================================================
// == INTERSECTION ================================================================================
// =================================================================================================
struct Intersection {
    Ray ray;
    float len;
    vec3 pos;
};

Intersection newIntersection(Ray ray, float len) {
    Intersection isect;
    isect.ray = ray;
    isect.len = len;
    isect.pos = getRayPosition(ray, len);
    return isect;
}

// =================================================================================================
// == MARCH RESULT ================================================================================
// =================================================================================================
struct MarchResult {
    float dist;
    vec2 uv;
};

// =================================================================================================
// == DISTANCE FUNCTIONS ==========================================================================
// =================================================================================================
float distFuncBox(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

vec3 deform(vec3 p) {
    vec3 pt = p;

    // Noise deformation (procedural)
    float deformFreq = 3.0;
    float deformSpeed = 1.0;
    pt += deformAmount * (
        vec3(
            sin(deformFreq * pt.x + iTime * deformSpeed) * cos(deformFreq * pt.y),
            sin(deformFreq * pt.y + iTime * deformSpeed) * cos(deformFreq * pt.z),
            sin(deformFreq * pt.z + iTime * deformSpeed) * cos(deformFreq * pt.x)
        ) * 0.5
    );

    // Main spin + twist
    pt.zx = rotate2D(mod(rotationSpeed * iTime + PI, TAU) + FX_TWIST() * pt.y) * pt.zx;

    // Gentle rotation oscillation
    pt.xy = rotate2D(0.6 * sin(0.9 * iTime)) * pt.xy;
    pt.yz = rotate2D(0.6 * sin(1.4 * iTime)) * pt.yz;

    // Kick pulse
    pt -= normalize(pt) * FX_KICK() * sin(15.0 * length(pt) - 40.0 * iTime);

    return pt;
}

MarchResult distFunc(vec3 p) {
    MarchResult result;

    vec3 pt = p;
    pt = deform(pt);
    result.dist = distFuncBox(pt, vec3(cubeSize));

    vec3 spt = vec3(1.0);

    if (fractalIntensity > 0.0 && fractalEnabled > 0.5) {
        vec3 ptIfs = p;
        ptIfs.z = mod(ptIfs.z - 16.0 * iTime + 3.0 * sin(HALF_PI * BEAT() + 0.5), 6.0) - 3.0;

        for (int i = 0; i < 6; i++) {
            float fi = float(i);
            spt *= sign(ptIfs);
            ptIfs = abs(ptIfs) - vec3(3.2, 4.5, 1.2) / max(1E-2, fractalIntensity) * pow(0.5, fi);
            ptIfs.xy = rotate2D(1.1) * ptIfs.xy;
            ptIfs.zx = rotate2D(2.1) * ptIfs.zx;
        }

        ptIfs = deform(ptIfs);

        float distIfs = distFuncBox(ptIfs, vec3(cubeSize));

        if (result.dist < distIfs) {
            spt = vec3(1.0);
        } else {
            result.dist = distIfs;
            pt = ptIfs;
        }
    }

    vec3 abspt = abs(pt);
    float n = max(abspt.x, max(abspt.y, abspt.z));

    result.uv = 0.5 + (
        (n == abspt.z) ? (pt.xy * vec2(sign(pt.z), 1.0)) :
        (n == abspt.x) ? (pt.zy * vec2(-sign(pt.x), 1.0)) :
        (pt.xz * vec2(1.0, -sign(pt.y)))
    ) * spt.x * spt.y * spt.z * 0.5 / cubeSize;

    return result;
}

vec3 normalFunc(vec3 p, float dd) {
    vec2 d = vec2(0.0, dd);
    return normalize(vec3(
        distFunc(p + d.yxx).dist - distFunc(p - d.yxx).dist,
        distFunc(p + d.xyx).dist - distFunc(p - d.xyx).dist,
        distFunc(p + d.xxy).dist - distFunc(p - d.xxy).dist
    ));
}

vec3 normalFunc(vec3 p) {
    return normalFunc(p, MARCH_NEAR);
}

// =================================================================================================
// == MAIN ========================================================================================
// =================================================================================================
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    bassLevel = audioBand(20.0, 250.0);
    midLevel = audioBand(250.0, 4000.0);
    vec2 p = (fragCoord.xy * 2.0 - iResolution.xy) / iResolution.x;

    Camera camera = newCamera(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0));
    camera.fov = 0.6 + fovPulse * fractalIntensity * (0.5 + 0.5 * sin(HALF_PI * BEAT() - 0.5));
    camera.pos.z = 0.5 + 1.5 / camera.fov;

    Ray ray = rayFromCamera(camera, p);

    float rayLen = MARCH_NEAR;
    vec3 rayPos = getRayPosition(ray, rayLen);
    MarchResult result;

    for (int i = 0; i < MARCH_ITER; i++) {
        result = distFunc(rayPos);
        if (abs(result.dist) < MARCH_NEAR) { break; }
        rayLen += result.dist * MARCH_MULP;
        if (MARCH_FAR < rayLen) { break; }
        rayPos = getRayPosition(ray, rayLen);
    }

    if (abs(result.dist) < MARCH_NEAR) {
        vec3 normal = normalFunc(rayPos);
        float edge = linearstep(0.498, 0.499, abs(result.uv.x - 0.5));
        edge += linearstep(0.495, 0.497, abs(result.uv.y - 0.5));
        vec2 uv = result.uv;
        vec4 tex = texture(iChannel0, uv);
        float fog = exp(-fogDensity * max(0.0, rayLen - 3.0));

        // Audio-reactive edge color
        float bass = getBass();
        vec3 edgeColor = 1.0 + (edgeGlow + bass) * sin(
            vec3(0.0, 1.0, 2.0) +
            bass * 3.0 +
            10.0 * length(result.uv - 0.5) -
            10.0 * iTime
        );

        fragColor = vec4(fog * mix(
            0.1 + 0.1 * normal + 0.8 * tex.rgb,
            edgeColor,
            edge
        ), 1.0);
    } else {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    }
}