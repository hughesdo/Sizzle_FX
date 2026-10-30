// Imported from SuperTool effects/ParticleBurst.glsl by scripts/import-supertool.mjs
// Particle Burst
// Bass-triggered fireworks — bursts of audio-colored particles fly outward and
// fade, blended over the video. Heavy: numBursts x numParticles per pixel.
// Ported from DISCO-GLSL-Video-Processor (Shaders/ParticleBurst.glsl)
// DISCO sampled an audio texture; here bass/mid/high come from the FFT bands.

uniform float burstFrequency;
uniform float numBursts;
uniform float numParticles;
uniform float particleSpeed;
uniform float particleSize;
uniform float beatThreshold;
uniform float particleIntensity;
uniform float blendAmount;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(443.897, 441.423, 437.195));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3 col = texture(iChannel0, uv).rgb;

    float bass = audioBand(20.0, 250.0);
    float mid = audioBand(250.0, 4000.0);
    float high = audioBand(4000.0, 16000.0);

    float beat = smoothstep(beatThreshold, 1.0, bass);

    vec3 particles = vec3(0.0);

    for (float i = 0.0; i < numBursts; i++) {
        float burstTime = iTime - i * 0.3;
        float burstId = floor(burstTime * burstFrequency);

        vec2 spawnPos = hash22(vec2(burstId, i));

        for (float j = 0.0; j < numParticles; j++) {
            vec2 particleId = vec2(burstId * numParticles + j, i);

            vec2 randomDir = hash22(particleId) * 2.0 - 1.0;
            randomDir = normalize(randomDir);

            float speed = particleSpeed * (0.3 + hash21(particleId) * 0.3);

            float life = fract(burstTime * burstFrequency);

            vec2 particlePos = spawnPos + randomDir * speed * life;

            float size = particleSize * (1.0 - life) * (1.0 + beat * 2.0);

            float dist = length(uv - particlePos);

            float brightness = smoothstep(size, 0.0, dist);

            vec3 particleColor = vec3(
                bass * 2.0,
                mid * 2.0,
                high * 2.0
            );

            particles += particleColor * brightness * particleIntensity * (1.0 - life);
        }
    }

    float particleAlpha = length(particles) * blendAmount;
    col = col * (1.0 - particleAlpha) + particles;

    fragColor = vec4(col, 1.0);
}
