// Imported from SuperTool effects/BeatDropShake.glsl by scripts/import-supertool.mjs
// Beat Drop Shake
// Explosive chaotic screen jolt on deep-bass beat drops, with oversize to hide
// black edges, a brightness flash and shake-driven desaturation/red tint.
// Ported from DISCO-GLSL-Video-Processor (Shaders/BeatDropShake.glsl)
// DISCO fed bassLevel/kickLevel/subBassLevel host uniforms; here they come from
// the FFT bands. DISCO's oversizeAmount uniform was auto-calculated and ignored,
// so it was dropped.

uniform float beatThreshold;     // Minimum beat strength to trigger shake
uniform float explosionStrength; // Magnitude of the screen jolt
uniform float dampenRate;        // How fast shaking settles
uniform float randomSeed;        // Seed for shake randomization
uniform float shakeDecay;        // Exponential decay rate for shake
uniform float timeSpeed;         // Overall animation speed multiplier

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

vec2 randomDirection(float seed, float time) {
    vec2 st = vec2(seed, time);
    float angle = random(st) * 6.28318;
    float magnitude = random(st + vec2(1.0, 0.0));
    return vec2(cos(angle), sin(angle)) * magnitude;
}

float detectBeatDrop(float bassEnergy, float kickEnergy, float subBassEnergy, float time) {
    float deepBass = bassEnergy * 0.4 + kickEnergy * 0.4 + subBassEnergy * 0.2;
    if (deepBass < beatThreshold) {
        return 0.0;
    }
    float beatTime = mod(time * 10.0, 1.0);
    return (deepBass - beatThreshold) * exp(-shakeDecay * beatTime);
}

vec2 generateShakeOffset(float beatStrength, float time, float seed) {
    if (beatStrength <= 0.0) {
        return vec2(0.0);
    }
    vec2 shake1 = randomDirection(seed + 1.0, time * 50.0) * beatStrength;
    vec2 shake2 = randomDirection(seed + 2.0, time * 75.0) * beatStrength * 0.7;
    vec2 shake3 = randomDirection(seed + 3.0, time * 100.0) * beatStrength * 0.5;
    vec2 shake4 = randomDirection(seed + 4.0, time * 125.0) * beatStrength * 0.3;
    vec2 totalShake = shake1 + shake2 + shake3 + shake4;
    float dampening = exp(-dampenRate * mod(time, 1.0));
    totalShake *= explosionStrength * dampening;
    return clamp(totalShake, -0.1, 0.1);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bassLevel = audioBand(20.0, 250.0);
    float kickLevel = audioBand(20.0, 80.0);
    float subBassLevel = audioBand(20.0, 50.0);

    float animTime = iTime * timeSpeed;

    float beatStrength = detectBeatDrop(bassLevel, kickLevel, subBassLevel, animTime);
    vec2 shakeOffset = generateShakeOffset(beatStrength, animTime, randomSeed);

    float autoOversizeAmount = 1.0 + (explosionStrength * 0.15);

    vec2 centeredUV = uv - 0.5;
    vec2 shakenUV = centeredUV + shakeOffset;
    vec2 oversizedUV = shakenUV / autoOversizeAmount;
    vec2 finalUV = clamp(oversizedUV + 0.5, 0.0, 1.0);

    vec4 videoColor = texture(iChannel0, finalUV);

    float beatFlash = beatStrength * 0.2;
    videoColor.rgb *= (1.0 + beatFlash);

    float shakeIntensity = length(shakeOffset) * 10.0;
    float desaturation = shakeIntensity * 0.3;
    vec3 gray = vec3(dot(videoColor.rgb, vec3(0.299, 0.587, 0.114)));
    videoColor.rgb = mix(videoColor.rgb, gray, desaturation);

    if (shakeIntensity > 0.5) {
        videoColor.r += shakeIntensity * 0.1;
    }

    videoColor.rgb = clamp(videoColor.rgb, 0.0, 1.2);

    fragColor = videoColor;
}
