// Imported from SuperTool effects/CandyFlipping.glsl by scripts/import-supertool.mjs
// Candy Flipping
// Psychedelic flow distortion + chromatic aberration + viscosity
// Audio-reactive: bass drives flow, mids drive viscosity, highs drive chroma
// Ported from DISCO-GLSL-Video-Processor (Effects/CandyFlipping.glsl)

uniform float flowIntensity;
uniform float waveFrequency;
uniform float pulseSpeed;
uniform float viscosity;
uniform float chromaticShift;
uniform float audioReactivity;
uniform float timeSpeed;

// Beat detection: sharp attack, exponential decay
float beatPulse(float audioLevel, float time, float decay) {
    float beatTime = mod(time, 1.0);
    return audioLevel * exp(-decay * beatTime);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float animTime = iTime * timeSpeed;

    // Audio
    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);
    float high = audioBand(4000.0, 16000.0);

    // Beat-reactive pulses
    float bassPulse = beatPulse(bass, animTime * 2.0, 3.0);
    float midPulse = beatPulse(mid, animTime * 1.5, 4.0);
    float treblePulse = beatPulse(high, animTime * 4.0, 5.0);

    // Combined audio boost
    float audioBoost = (bass + bassPulse * 0.5 + midPulse * 0.3 + treblePulse * 0.2) * audioReactivity;

    // Flow distortion
    float t = animTime * pulseSpeed;
    float flowX = sin(uv.y * waveFrequency + t) * flowIntensity * 0.05 * (1.0 + audioBoost);
    float flowY = cos(uv.x * waveFrequency + t) * flowIntensity * 0.05 * (1.0 + audioBoost);

    flowX += sin(uv.y * waveFrequency * 2.0 + t * 1.3) * flowIntensity * 0.02 * bassPulse;
    flowY += cos(uv.x * waveFrequency * 1.7 + t * 0.8) * flowIntensity * 0.02 * midPulse;

    vec2 distortedUV = uv + vec2(flowX, flowY);

    // Chromatic aberration
    vec2 chromaticOffset = chromaticShift * vec2(cos(t), sin(t)) * audioBoost;
    chromaticOffset += chromaticShift * 0.5 * vec2(
        sin(t * 2.0) * bassPulse,
        cos(t * 1.5) * treblePulse
    );

    vec4 rChannel = texture(iChannel0, distortedUV + chromaticOffset);
    vec4 gChannel = texture(iChannel0, distortedUV);
    vec4 bChannel = texture(iChannel0, distortedUV - chromaticOffset);

    // Viscosity blending
    float viscosityBlend = smoothstep(0.0, 1.0, sin(t) * 0.5 + 0.5) * viscosity;
    viscosityBlend += mid * audioReactivity * 0.3 * sin(t * 3.0);
    viscosityBlend = clamp(viscosityBlend, 0.0, 1.0);

    vec4 chromaticColor = vec4(rChannel.r, gChannel.g, bChannel.b, 1.0);
    vec4 normalColor = texture(iChannel0, distortedUV);
    vec4 color = mix(chromaticColor, normalColor, viscosityBlend);

    // Beat-reactive color intensity
    float colorIntensity = 1.0 + (bassPulse + midPulse + treblePulse) * audioReactivity * 0.2;
    color.rgb *= colorIntensity;

    // Saturation boost
    float saturationBoost = 1.0 + audioBoost * 0.3;
    vec3 gray = vec3(dot(color.rgb, vec3(0.299, 0.587, 0.114)));
    color.rgb = mix(gray, color.rgb, saturationBoost);

    // Subtle hue shifting
    float hueShift = audioBoost * 0.1 * sin(t * 0.5);
    float s = sin(hueShift), c = cos(hueShift);
    mat3 hueMatrix = mat3(
        vec3(0.299 + 0.701*c + 0.168*s, 0.587 - 0.587*c + 0.330*s, 0.114 - 0.114*c - 0.497*s),
        vec3(0.299 - 0.299*c - 0.328*s, 0.587 + 0.413*c + 0.035*s, 0.114 - 0.114*c + 0.292*s),
        vec3(0.299 - 0.3*c + 1.25*s,   0.587 - 0.588*c - 1.05*s,  0.114 + 0.886*c - 0.203*s)
    );
    color.rgb = color.rgb * hueMatrix;

    color.rgb = clamp(color.rgb, 0.0, 1.5);

    fragColor = color;
}
