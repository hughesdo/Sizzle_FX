// Imported from SuperTool effects/EasyBeats.glsl by scripts/import-supertool.mjs
// Easy Beats
// All-in-one beat reactor: kick shake, beat color-pop, bass zoom-pulse and
// treble sparkle, with auto energy compensation and a vignette.
// Ported from DISCO-GLSL-Video-Processor (Shaders/EasyBeats.glsl)
// DISCO fed bass/mid/treble/beat/kick host uniforms; here they come from the
// FFT bands (beat -> audioBeatEnergy).

uniform float intensity;     // Overall effect intensity (0=off, 1=normal, 2=intense)
uniform float shakeAmount;   // Screen shake strength
uniform float colorPop;      // Color enhancement on beats

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    float bassLevel = audioBand(20.0, 250.0);
    float midLevel = audioBand(250.0, 4000.0);
    float trebleLevel = audioBand(4000.0, 16000.0);
    float beatLevel = audioBeatEnergy();
    float kickLevel = audioBand(20.0, 80.0);

    vec2 shakeOffset = vec2(0.0);

    float kickStrength = kickLevel * intensity;
    if (kickStrength > 0.3) {
        float shakeTime = iTime * 50.0;
        vec2 shakeDir = vec2(
            sin(shakeTime + kickStrength * 10.0),
            cos(shakeTime * 1.3 + kickStrength * 15.0)
        );
        shakeOffset = shakeDir * kickStrength * shakeAmount * 0.02;
        shakeOffset = clamp(shakeOffset, -0.05, 0.05);
    }

    vec2 shakenUV = uv + shakeOffset;
    vec3 color = texture(iChannel0, shakenUV).rgb;

    float beatPulse = beatLevel * intensity;
    if (beatPulse > 0.4) {
        color = pow(color, vec3(0.8));
        color *= (1.0 + beatPulse * colorPop * 0.5);
        color.r *= (1.0 + bassLevel * colorPop * 0.2);
        color.g *= (1.0 + midLevel * colorPop * 0.2);
        color.b *= (1.0 + trebleLevel * colorPop * 0.2);
    }

    float bassPulse = bassLevel * intensity;
    if (bassPulse > 0.3) {
        vec2 center = vec2(0.5);
        vec2 centeredUV = uv - center;
        float zoomFactor = 1.0 + bassPulse * 0.02;
        vec2 zoomedUV = centeredUV / zoomFactor + center;
        vec3 zoomedColor = texture(iChannel0, zoomedUV + shakeOffset).rgb;
        color = mix(color, zoomedColor, bassPulse * 0.5);
    }

    float treblePulse = trebleLevel * intensity;
    if (treblePulse > 0.5) {
        float noise = random(uv + iTime * 0.1);
        if (noise > (1.0 - treblePulse * 0.1)) {
            color += vec3(treblePulse * colorPop * 0.3);
        }
    }

    float totalEnergy = (bassLevel + midLevel + trebleLevel) / 3.0;
    if (totalEnergy < 0.3) {
        color *= (1.0 + (0.3 - totalEnergy) * intensity * 0.2);
    }
    if (totalEnergy > 0.8) {
        color *= (1.0 - (totalEnergy - 0.8) * 0.3);
    }

    vec2 vignetteUV = uv - 0.5;
    float vignette = 1.0 - dot(vignetteUV, vignetteUV) * 0.3;
    color *= vignette;

    color = clamp(color, 0.0, 2.0);

    fragColor = vec4(color, 1.0);
}
