// Imported from SuperTool effects/BeatFlash.glsl by scripts/import-supertool.mjs
// Beat Flash
// Psychedelic flashes on beat hits — brief color inversions, chromatic
// aberration, exposure bloom and posterize bursts.
// Ported from DISCO-GLSL-Video-Processor (Shaders/BeatFlash.glsl)
// DISCO fed beatAmplitude/kickLevel/bassLevel host uniforms; here they come
// from the injected audio helpers (beat energy + sub-bass/bass FFT bands).

uniform float beatSensitivity;  // Threshold for triggering visual flash (0.0-1.0)
uniform float flashStrength;    // Intensity of color inversion and effects
uniform float flashDecay;       // How quickly the effect fades (1=slow, 10=fast)
uniform float chromaticOffset;  // RGB channel separation amount
uniform float exposureBoost;    // Brightness boost during flash
uniform float bloomIntensity;   // White bloom effect strength
uniform float posterizeLevel;   // Posterization effect strength
uniform float timeSpeed;        // Overall animation speed multiplier

// Beat detection function - creates sharp flash impulses
float detectBeatFlash(float beatAmp, float kickEnergy, float bassEnergy, float time) {
    float combinedBeat = beatAmp * 0.6 + kickEnergy * 0.3 + bassEnergy * 0.1;

    if (combinedBeat < beatSensitivity) {
        return 0.0;
    }

    float flashTime = mod(time * 15.0, 1.0); // 15Hz flash detection rate
    float flashImpulse = (combinedBeat - beatSensitivity) * exp(-flashDecay * flashTime);

    return clamp(flashImpulse, 0.0, 1.0);
}

vec3 invertColors(vec3 color, float strength) {
    vec3 inverted = vec3(1.0) - color;
    return mix(color, inverted, strength);
}

vec3 posterize(vec3 color, float levels) {
    if (levels <= 1.0) return color;
    return floor(color * levels) / levels;
}

vec3 adjustExposure(vec3 color, float exposure) {
    return color * pow(2.0, exposure);
}

vec3 addBloom(vec3 color, float intensity) {
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    return color + vec3(luminance) * intensity;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float beatAmplitude = audioBeatEnergy();
    float kickLevel = audioBand(20.0, 80.0);
    float bassLevel = audioBand(20.0, 250.0);

    float animTime = iTime * timeSpeed;

    float flashIntensity = detectBeatFlash(beatAmplitude, kickLevel, bassLevel, animTime);

    // Chromatic aberration sampling during the flash
    vec2 chromaticOffsetAmount = vec2(chromaticOffset) * flashIntensity * flashStrength;
    vec4 rChannel = texture(iChannel0, uv + chromaticOffsetAmount);
    vec4 gChannel = texture(iChannel0, uv);
    vec4 bChannel = texture(iChannel0, uv - chromaticOffsetAmount);
    vec3 chromaticColor = vec3(rChannel.r, gChannel.g, bChannel.b);

    vec3 normalColor = texture(iChannel0, uv).rgb;

    vec3 flashColor = chromaticColor;

    if (flashIntensity > 0.0) {
        flashColor = invertColors(flashColor, flashIntensity * flashStrength * 0.8);

        float exposureAmount = exposureBoost * flashIntensity * flashStrength;
        flashColor = adjustExposure(flashColor, exposureAmount);

        float bloomAmount = bloomIntensity * flashIntensity * flashStrength;
        flashColor = addBloom(flashColor, bloomAmount);

        float posterizeLevels = mix(256.0, posterizeLevel, flashIntensity * flashStrength);
        flashColor = posterize(flashColor, posterizeLevels);

        float desaturation = flashIntensity * 0.3;
        vec3 gray = vec3(dot(flashColor, vec3(0.299, 0.587, 0.114)));
        flashColor = mix(flashColor, gray, desaturation);

        flashColor.b += flashIntensity * 0.1;
        flashColor.r -= flashIntensity * 0.05;
    }

    float flashBlend = flashIntensity * flashStrength;
    vec3 finalColor = mix(normalColor, flashColor, flashBlend);

    // Brief white flash overlay for extra punch
    if (flashIntensity > 0.7) {
        float whiteFlash = (flashIntensity - 0.7) * 3.33;
        finalColor = mix(finalColor, vec3(1.0), whiteFlash * flashStrength * 0.3);
    }

    // Subtle vignette during flash for focus
    if (flashIntensity > 0.0) {
        vec2 center = uv - 0.5;
        float vignette = 1.0 - dot(center, center) * flashIntensity * 0.5;
        finalColor *= vignette;
    }

    // Film grain during flash
    if (flashIntensity > 0.0) {
        float grain = fract(sin(dot(uv * animTime, vec2(12.9898, 78.233))) * 43758.5453);
        grain = (grain - 0.5) * flashIntensity * 0.1;
        finalColor += grain;
    }

    finalColor = clamp(finalColor, 0.0, 2.0);

    fragColor = vec4(finalColor, 1.0);
}
