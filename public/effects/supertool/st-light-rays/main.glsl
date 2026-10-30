// Imported from SuperTool effects/LightRays.glsl by scripts/import-supertool.mjs
// Light Rays (God Rays)
// Radial blur from a light source position, audio-reactive
// Light intensity and ray length respond to bass/audio
// Ported from DISCO-GLSL-Video-Processor (Effects/LightRays.glsl)

uniform float lightPosX;
uniform float lightPosY;
uniform float lightMovement;
uniform float rayLength;
uniform float audioRayLength;
uniform float numSamples;
uniform float rayDecay;
uniform float brightnessThreshold;
uniform float rayIntensity;
uniform float audioBoost;
uniform vec3  rayColor;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // Original video
    vec3 videoCol = texture(iChannel0, uv).rgb;

    // Audio from FFT + standard uniforms
    float audio = texture(iAudioFFT, vec2(0.15, 0.25)).x;
    float bass = max(texture(iAudioFFT, vec2(0.05, 0.25)).x, audioBand(20.0, 250.0));
    audio = max(audio, audioRMS());

    // Light source position (animated)
    vec2 lightPos = vec2(lightPosX, lightPosY);
    lightPos.x += sin(iTime + bass * 5.0) * lightMovement;
    lightPos.y += cos(iTime * 0.7) * lightMovement * 0.5;

    // Ray direction
    vec2 deltaUv = uv - lightPos;
    float dist = length(deltaUv);

    // Radial blur to create god rays
    vec3 rays = vec3(0.0);
    float weight = 1.0;
    float effectiveRayLength = rayLength + audio * audioRayLength;

    for (float i = 0.0; i < numSamples; i++) {
        float t = i / numSamples;
        vec2 sampleUv = uv - deltaUv * t * effectiveRayLength;

        vec3 sampleCol = texture(iChannel0, sampleUv).rgb;

        // Extract bright areas
        float brightness = dot(sampleCol, vec3(0.299, 0.587, 0.114));
        brightness = smoothstep(brightnessThreshold, 1.0, brightness);

        rays += sampleCol * brightness * weight;
        weight *= rayDecay;
    }

    rays /= numSamples;

    // Distance falloff
    float falloff = 1.0 - smoothstep(0.0, 1.0, dist);
    rays *= falloff;

    // Audio-reactive intensity
    float finalIntensity = rayIntensity + audio * audioBoost;
    rays *= finalIntensity;

    // Apply color tint + additive blend
    vec3 tintedRays = rays * rayColor;
    vec3 col = videoCol + tintedRays * 0.6;

    fragColor = vec4(col, 1.0);
}
