// Imported from SuperTool effects/CameraShake.glsl by scripts/import-supertool.mjs
// Camera Shake
// Drum-triggered camera shake — kick and snare hits jolt the frame in random
// directions with a brief flash and vignette. Auto-oversamples to hide edges.
// Ported from DISCO-GLSL-Video-Processor (Shaders/CameraShake.glsl)
// DISCO fed beatIntensity/kickLevel/snareLevel host uniforms; here they come
// from the FFT bands (snare ~ 2-5kHz, kick ~ sub-bass, beat ~ beat energy).

uniform float shakeIntensity;   // Overall shake strength multiplier
uniform float beatDecay;        // How fast beat impacts decay
uniform float beatThreshold;    // Minimum beat strength to trigger shake
uniform float maxShakeRadius;   // Maximum shake distance from center

float random(float x) {
    return fract(sin(x * 12.9898) * 43758.5453);
}

float drumBeatShake(float beatStrength, float time, float randomSeed) {
    if (beatStrength < beatThreshold) return 0.0;
    float timeSinceBeat = mod(time, 1.0);
    float beatImpulse = beatStrength * exp(-beatDecay * timeSinceBeat);
    float randomDir = (random(floor(time) + randomSeed) - 0.5) * 2.0;
    float shake = beatImpulse * randomDir * shakeIntensity;
    return clamp(shake, -maxShakeRadius, maxShakeRadius);
}

float getBeatMoment(float beatStrength, float time) {
    float timeSinceBeat = mod(time, 1.0);
    return beatStrength * exp(-beatDecay * timeSinceBeat);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float beatIntensity = audioBeatEnergy() * 2.0;
    float kickLevel = audioBand(20.0, 80.0);
    float snareLevel = audioBand(2000.0, 5000.0);

    float drumTime = iTime * 2.5;
    float totalDrumEnergy = max(kickLevel, snareLevel) * beatIntensity;

    float drumShakeX = drumBeatShake(totalDrumEnergy, drumTime, 1.0);
    float drumShakeY = drumBeatShake(totalDrumEnergy, drumTime, 2.0);

    float kickTime = iTime * 1.8;
    float snareTime = iTime * 3.2;

    float kickShakeX = drumBeatShake(kickLevel * beatIntensity, kickTime, 3.0) * 0.8;
    float kickShakeY = drumBeatShake(kickLevel * beatIntensity, kickTime, 4.0) * 0.8;

    float snareShakeX = drumBeatShake(snareLevel * beatIntensity, snareTime, 5.0) * 0.6;
    float snareShakeY = drumBeatShake(snareLevel * beatIntensity, snareTime, 6.0) * 0.6;

    float xShake = drumShakeX + kickShakeX + snareShakeX;
    float yShake = drumShakeY + kickShakeY + snareShakeY;

    vec2 shakenUV = uv + vec2(xShake, yShake);

    float autoOversample = 1.0 + (shakeIntensity * 0.1);
    vec2 center = vec2(0.5);
    vec2 oversampledUV = (shakenUV - center) / autoOversample + center;

    vec3 color = texture(iChannel0, oversampledUV).rgb;

    float drumFlash = getBeatMoment(totalDrumEnergy, drumTime);
    float kickFlash = getBeatMoment(kickLevel * beatIntensity, kickTime);
    float snareFlash = getBeatMoment(snareLevel * beatIntensity, snareTime);

    float totalFlash = 1.0 + (drumFlash + kickFlash * 0.8 + snareFlash * 0.6) * 0.3;
    color *= totalFlash;

    vec2 vignetteCenter = uv - 0.5;
    float vignette = 1.0 - dot(vignetteCenter, vignetteCenter) * 0.2;
    color *= vignette;

    fragColor = vec4(color, 1.0);
}
