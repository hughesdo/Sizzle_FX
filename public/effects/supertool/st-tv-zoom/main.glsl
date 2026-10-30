// Imported from SuperTool effects/TVZoom.glsl by scripts/import-supertool.mjs
// TV Zoom
// Cinematic raymarched camera fly-in toward a tablet/TV displaying the underlying video.
// Bezier-curve camera path with 45° yo-yo rotation, chrome spheres orbiting, optional dark-area video transparency.
// Ported from DISCO-GLSL-Video-Processor (Shaders/TVZoom.glsl).
//
// Layer model: single-pass post-process effect.
//   iChannel0 = underlying video layer (system-bound via inputMode "video").
//   iChannel1 = wood-grain floor texture (asset binding from metadata.json).
//   iChannel2 = tablet-body texture (asset binding from metadata.json).
// Procedural fallbacks remain inline so the effect still renders if an asset
// fails to load (matches the DISCO original's `length(texColor) < 0.1` check).

uniform float animationSpeed;          // overall pacing of the zoom cycle
uniform float pauseDuration;           // seconds to dwell at the start position before each fly-in
uniform float cameraHeight;            // vertical offset of the entire camera arc
uniform float zoomIntensity;           // FOV multiplier (1 = DISCO original look)
uniform float enableVideoTransparency; // 0 = off, 1 = on (dark areas blend with blue)
uniform float transparencyThreshold;   // brightness below this fades toward blue

#define PI 3.141593

#define SKY_OBJ     0
#define FLOOR_OBJ   1
#define TABLET_OBJ  2
#define IMAGE_OBJ   3
#define SPHERES_OBJ 4

const vec3  tabPos          = vec3(0.0, 2.3, 0.0);
const float tabWidth        = 3.0;
const float tabHeight       = 2.0;
const float tabletRounding  = 0.3;
const float picWidth        = 0.93;
const float picHeight       = 0.96;
const float normdelta       = 0.002;
const float maxdist         = 50.0;

// Camera state — written by animateCamera(), read by render().
vec3 campos;
vec3 camtarget;
vec3 camdir;

vec3 bezierCurve(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
    float u = 1.0 - t;
    float tt = t * t;
    float uu = u * u;
    return uu * u * p0 + 3.0 * uu * t * p1 + 3.0 * u * tt * p2 + tt * t * p3;
}

void animateCamera() {
    float t = iTime * animationSpeed;
    float cycle = pauseDuration + 4.0;
    float phase = mod(t, cycle);

    vec3 startPos      = vec3(-18.0, 12.0 + cameraHeight, 18.0);
    vec3 controlPoint1 = vec3(-12.0,  9.0 + cameraHeight, 12.0);
    vec3 controlPoint2 = vec3( -6.0,  6.0 + cameraHeight,  6.0);
    vec3 endPos        = vec3( -4.0,  3.5 + cameraHeight,  4.0);

    float animPhase = 0.0;
    if (phase > pauseDuration) {
        float moveTime = phase - pauseDuration;
        float halfCycle = 2.0;
        if (moveTime < halfCycle) {
            animPhase = moveTime / halfCycle;
        } else {
            animPhase = 1.0 - ((moveTime - halfCycle) / halfCycle);
        }
        animPhase = smoothstep(0.0, 1.0, animPhase);
        animPhase = smoothstep(0.0, 1.0, animPhase);
    }

    vec3 baseCampos = bezierCurve(startPos, controlPoint1, controlPoint2, endPos, animPhase);

    // Yo-yo rotation around tablet's Y-axis (0° → -45° → 0°).
    float maxRotation = radians(45.0);
    float rotationAngle = -maxRotation * animPhase;
    vec3 offsetFromTablet = baseCampos - tabPos;
    float c = cos(rotationAngle);
    float s = sin(rotationAngle);
    vec3 rotatedOffset = vec3(
        offsetFromTablet.x * c - offsetFromTablet.z * s,
        offsetFromTablet.y,
        offsetFromTablet.x * s + offsetFromTablet.z * c
    );
    campos = tabPos + rotatedOffset;

    vec3 baseTarget  = vec3(0.0, 2.3, 0.0);
    vec3 closeTarget = vec3(0.0, 2.0, 0.0);
    camtarget = mix(baseTarget, closeTarget, animPhase * 0.3);
    camdir = normalize(camtarget - campos);
}

float map_floor(vec3 pos) {
    return pos.y;
}

float map_tablet(vec3 pos, vec3 orig, vec3 size, float flatn, float r) {
    pos.z *= flatn;
    return length(max(abs(pos - orig) - size, 0.0)) - r;
}

float map_spheres(vec3 pos) {
    pos -= tabPos;
    float minDist = 1000.0;

    float a1 = iTime * 0.3;
    vec3 p1 = vec3(pos.x * cos(a1) - pos.z * sin(a1), pos.y, pos.x * sin(a1) + pos.z * cos(a1));
    p1.x -= 4.5; p1.z *= 1.5;
    minDist = min(minDist, length(p1) - 0.3);

    float a2 = iTime * 0.3 + PI;
    vec3 p2 = vec3(pos.x * cos(a2) - pos.z * sin(a2), pos.y, pos.x * sin(a2) + pos.z * cos(a2));
    p2.x -= 4.5; p2.z *= 1.5;
    minDist = min(minDist, length(p2) - 0.3);

    float a3 = iTime * 0.4;
    vec3 p3 = vec3(pos.x, pos.y * cos(a3) - pos.z * sin(a3), pos.y * sin(a3) + pos.z * cos(a3));
    p3.y -= 2.0; p3.z -= 3.0;
    minDist = min(minDist, length(p3) - 0.25);

    return minDist;
}

vec2 map(vec3 pos) {
    vec2 res = vec2(map_floor(pos), float(FLOOR_OBJ));
    float dt = map_tablet(pos, tabPos, vec3(tabWidth, tabHeight, 0.1), 5.0, tabletRounding);
    if (dt < res.x) res = vec2(dt, float(TABLET_OBJ));
    float ds = map_spheres(pos);
    if (ds < res.x) res = vec2(ds, float(SPHERES_OBJ));
    return res;
}

vec2 trace(vec3 cam, vec3 ray, float maxd) {
    float t = 0.15;
    float objnr = 0.0;
    for (int i = 0; i < 300; ++i) {
        vec3 pos = cam + t * ray;
        vec2 res = map(pos);
        float dist = res.x;
        if (dist > maxd || abs(dist) < 0.0001) break;
        t += dist * 0.1;
        objnr = res.y;
    }
    return vec2(t, objnr);
}

vec3 getNormal(vec3 pos, float e) {
    vec2 q = vec2(0.0, e);
    return normalize(vec3(
        map(pos + q.yxx).x - map(pos - q.yxx).x,
        map(pos + q.xyx).x - map(pos - q.xyx).x,
        map(pos + q.xxy).x - map(pos - q.xxy).x
    ));
}

// Procedural fallbacks — used only when the wood/tablet textures fail to load.
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
vec3 floor_color(vec3 pos) {
    vec3 texColor = texture(iChannel1, pos.xz * 0.1).rgb;
    if (length(texColor) < 0.1) {
        // Procedural fallback (DISCO parity).
        vec2 uv = pos.xz * 0.4;
        float grain = vnoise(vec2(uv.x * 8.0, uv.y * 0.5));
        float rings = sin(uv.x * 1.7 + grain * 1.5) * 0.5 + 0.5;
        texColor = mix(vec3(0.30, 0.18, 0.09), vec3(0.62, 0.40, 0.22),
                       rings * 0.7 + grain * 0.3);
    }
    return texColor;
}

vec3 tablet_color(vec3 pos) {
    vec3 texColor = texture(iChannel2, pos.xy * 0.1).rgb;
    if (length(texColor) < 0.1) {
        texColor = vec3(0.15);
    }
    return texColor;
}

vec3 image_color(vec3 pos) {
    // The system uploads the video-input texture with UNPACK_FLIP_Y_WEBGL=true
    // (GLSLRenderer._uploadVideoInputTexture), so iChannel0 is already in OpenGL
    // bottom-up orientation — no extra Y-flip here. (DISCO's original line
    // `videoUV.y = 1.0 - videoUV.y` compensated for an import path that didn't
    // flip on upload; ours does, so the same line would produce upside-down video.)
    vec2 videoUV = vec2(
        (pos.x - tabPos.x) / (tabWidth * picWidth) * 0.5 + 0.5,
        (pos.y - tabPos.y) / (tabHeight * picHeight) * 0.5 + 0.5
    );

    vec3 videoColor = texture(iChannel0, videoUV).rgb;

    if (enableVideoTransparency > 0.5) {
        float brightness = length(videoColor);
        if (brightness < transparencyThreshold) {
            float alpha = brightness / max(transparencyThreshold, 1e-4);
            videoColor = mix(vec3(0.2, 0.4, 0.8), videoColor, alpha);
        }
    } else {
        if (length(videoColor) < 0.1) {
            videoColor = vec3(0.2, 0.4, 0.8);
        }
    }
    return videoColor;
}

vec3 spheres_color(vec3 pos, vec3 norm, vec3 rayDir) {
    vec3 baseColor = vec3(0.8, 0.85, 0.9);
    vec3 reflected = reflect(rayDir, norm);
    vec3 envColor = vec3(0.1, 0.35, 0.7);
    if (reflected.y > 0.5)        envColor = vec3(0.2, 0.5, 0.9);
    else if (reflected.y < -0.2)  envColor = vec3(0.3, 0.3, 0.4);
    return mix(baseColor, envColor, 0.8);
}

vec3 sky_color(vec3 ray) {
    return vec3(0.1, 0.35, 0.7);
}

vec3 getColor(vec3 norm, vec3 pos, int objnr, vec3 rayDir) {
    if (objnr == FLOOR_OBJ)   return floor_color(pos);
    if (objnr == TABLET_OBJ)  return tablet_color(pos);
    if (objnr == IMAGE_OBJ)   return image_color(pos);
    if (objnr == SPHERES_OBJ) return spheres_color(pos, norm, rayDir);
    return sky_color(rayDir);
}

vec3 lampsShading(vec3 norm, vec3 pos, vec3 ocol) {
    vec3 lampPos = vec3(0.0, 5.0, 5.0);
    vec3 pl = normalize(lampPos - pos);
    return ocol * max(0.0, dot(norm, pl)) + vec3(0.2);
}

vec3 GetCameraRayDir(vec2 vWindow, vec3 vCameraDir, float fov) {
    vec3 vForward = normalize(vCameraDir);
    vec3 vRight   = normalize(cross(vec3(0.0, 1.0, 0.0), vForward));
    vec3 vUp      = normalize(cross(vForward, vRight));
    return normalize(vWindow.x * vRight + vWindow.y * vUp + vForward * fov);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    animateCamera();

    float fov = 4.0 * zoomIntensity;
    vec2 uv = fragCoord / iResolution.xy;
    uv = uv * 2.0 - 1.0;
    uv.x *= iResolution.x / iResolution.y;

    vec3 ray = GetCameraRayDir(uv, camdir, fov);
    vec2 tr  = trace(campos, ray, maxdist);
    float tx = tr.x;
    int objnr = int(tr.y);
    vec3 pos = campos + tx * ray;

    vec3 col;
    if (tx < maxdist) {
        // Promote tablet hits inside the picture rect to IMAGE_OBJ (the video screen).
        if (objnr == TABLET_OBJ &&
            abs(pos.x - tabPos.x) < tabWidth  * picWidth &&
            abs(pos.y - tabPos.y) < tabHeight * picHeight) {
            objnr = IMAGE_OBJ;
        }
        vec3 norm = getNormal(pos, normdelta);
        col = getColor(norm, pos, objnr, ray);
        col = lampsShading(norm, pos, col);
    } else {
        col = sky_color(ray);
    }

    fragColor = vec4(col, 1.0);
}
