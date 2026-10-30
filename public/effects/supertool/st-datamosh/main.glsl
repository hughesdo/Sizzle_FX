// Imported from SuperTool effects/Datamosh.glsl by scripts/import-supertool.mjs
// Datamosh
// Simulated video-compression corruption — block displacement, motion smear,
// channel shift and quantization. Bass triggers, general energy drives it.
// Ported from DISCO-GLSL-Video-Processor (Shaders/Datamosh.glsl)
// DISCO sampled an audio texture; here general/bass come from the FFT bands.

uniform float glitchThreshold;
uniform float blockSizeMin;
uniform float blockSizeMax;
uniform float displacementH;
uniform float displacementV;
uniform float smearAmount;
uniform float smearSamples;
uniform float colorShift;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float audio = audioRMS();
    float bass = audioBand(20.0, 250.0);

    float glitchTrigger = step(glitchThreshold, bass);
    float glitchIntensity = audio * glitchTrigger;

    vec2 blockUv = uv;
    float blockSize = blockSizeMin + hash21(floor(iTime * 5.0) * vec2(1.0)) * (blockSizeMax - blockSizeMin);

    if (glitchIntensity > 0.3) {
        vec2 blockId = floor(uv / blockSize);
        float blockRand = hash21(blockId + floor(iTime * 10.0));

        if (blockRand > 0.7) {
            blockUv.x += (blockRand - 0.5) * displacementH * glitchIntensity;
        }
        if (blockRand > 0.85) {
            blockUv.y += (blockRand - 0.5) * displacementV * glitchIntensity;
        }
    }

    vec3 col = texture(iChannel0, blockUv).rgb;

    if (glitchIntensity > 0.4) {
        vec2 smearDir = vec2(1.0, 0.0);
        float smearAmt = glitchIntensity * smearAmount;

        vec3 smear = vec3(0.0);
        int samples = int(smearSamples);
        for (int i = 0; i < samples; i++) {
            smear += texture(iChannel0, blockUv + smearDir * smearAmt * float(i)).rgb;
        }
        smear /= float(samples);

        col = mix(col, smear, glitchIntensity * 0.6);
    }

    if (glitchIntensity > 0.5) {
        float shift = glitchIntensity * colorShift;
        col.r = texture(iChannel0, blockUv + vec2(shift, 0.0)).r;
        col.b = texture(iChannel0, blockUv - vec2(shift, 0.0)).b;
    }

    if (glitchIntensity > 0.6) {
        float levels = 8.0 - glitchIntensity * 4.0;
        col = floor(col * levels) / levels;
    }

    fragColor = vec4(col, 1.0);
}
