// Imported from SuperTool liquid-paint/buffer_b.glsl
// ============================================
// BUFFER B - Liquid Paint (fluid advection of the live clip)
// ============================================
//
// Concept inspired by the advection-feedback look of Shadertoy MsGSRd
// ("My Trippy Butt Hole"): https://www.shadertoy.com/view/MsGSRd
// This is an original implementation — a divergence-free curl-noise flow
// field advects the accumulated paint each frame (semi-Lagrangian pull),
// the fresh video frame is continuously re-injected so the paint is always
// "melting" out of the live clip, and audio pumps the churn. No source
// texture from the original shader is used; the seed is the timeline clip.

#version 330 core

uniform sampler2D iChannel0;  // Self-feedback (Buffer B previous frame) = accumulated paint
uniform sampler2D iChannel1;  // Fresh video frame (Buffer A)
uniform vec3 iResolution;
uniform float iTime;

// Tweakable parameters (defaults in meta.json)
uniform float flowScale;        // Spatial frequency of the swirls (bigger = smaller swirls)
uniform float flowSpeed;        // Base advection speed
uniform float turbulence;       // Extra domain-warp chaos in the flow field
uniform float paintPersistence; // Feedback retention (how long smears live, 0..0.99)
uniform float injectAmount;     // How strongly the live clip re-seeds the paint (0 = pure runaway)
uniform float audioFlow;        // How much bass/RMS pumps the flow speed
uniform float colorBleed;       // Hue drift / saturation lift as paint ages

in vec2 fragCoord;
out vec4 fragColor;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// Curl of a scalar potential -> divergence-free (incompressible) flow.
vec2 curl(vec2 p) {
    float e = 0.01;
    float nx1 = fbm(p + vec2(0.0, e));
    float nx2 = fbm(p - vec2(0.0, e));
    float ny1 = fbm(p + vec2(e, 0.0));
    float ny2 = fbm(p - vec2(e, 0.0));
    return vec2(nx1 - nx2, ny2 - ny1) / (2.0 * e);
}

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main()
{
    vec2 uv = fragCoord / iResolution.xy;
    float asp = iResolution.x / iResolution.y;

    float bass = audioBand(20.0, 200.0);
    float rms = audioRMS();

    // Animated curl-noise flow field. Aspect-correct the sample coords so the
    // swirls stay round instead of stretching on wide frames. A second curl
    // term warps the domain for marbled, turbulent veining.
    vec2 q = vec2(uv.x * asp, uv.y) * flowScale + vec2(0.0, iTime * 0.05);
    vec2 flow = curl(q + turbulence * curl(q * 0.5 + iTime * 0.03));

    // Audio pumps the churn so the paint surges on the beat.
    float speed = flowSpeed * (1.0 + audioFlow * (bass * 1.5 + rms * 0.5));

    // Semi-Lagrangian advection: pull paint from upstream in uv space.
    vec2 flowStep = flow * speed * 0.0015;
    vec3 advected = texture(iChannel0, uv - flowStep).rgb;

    // Near-lossless persistence: this is the paint's "breath". With a long
    // memory the curl flow has time to actually move and liquefy the smear over
    // many frames instead of it dying ~5 frames (~80ms) in. The brightness is
    // held in check below by the additive-injection balance, not by this decay.
    advected *= paintPersistence;

    // Age the paint colour for that oil-slick richness as it flows. Over a long
    // persistence this hue drift accumulates into colours the raw clip never had.
    if (colorBleed > 0.0) {
        vec3 h = rgb2hsv(advected);
        h.x = fract(h.x + colorBleed * 0.02);
        h.y = clamp(h.y * (1.0 + colorBleed * 0.3), 0.0, 1.0);
        advected = hsv2rgb(h);
    }

    // Re-inject the live clip ADDITIVELY (not as a mix toward video). A mix
    // pulled every pixel back to the raw frame each step, so the buffer froze
    // into a dimmed copy of the clip ~1s in and could never build richer paint.
    // Additive seeding lets the clip keep feeding pigment into the flow while
    // the paint accumulates; the steady state is ~video*injectAmount/(1-persistence),
    // so with the meta.json defaults (≈1.0) brightness self-limits near the clip.
    vec3 video = texture(iChannel1, uv).rgb;
    vec3 result = advected + video * injectAmount;

    // Seed straight from the clip on the first frames (feedback buffer is empty).
    if (iFrame < 2) result = video;

    fragColor = vec4(clamp(result, 0.0, 1.0), 1.0);
}
