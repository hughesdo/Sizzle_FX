// Silhouette Echo: past masks (history alpha) drawn as flat colour, oldest at the back.
uniform int   layers;
uniform int   spacing;
uniform int   palette;
uniform vec3  colorA;
uniform vec3  colorB;
uniform float opacity;
uniform float hueSpeed;
uniform float audioPush;

vec3 hue(float h){ return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 col = texture(iChannel0, uv).rgb;
  float bright = 1.0 + audioPush * uAudio;
  for (int i = 15; i >= 1; i--){
    if (i > layers) continue;
    float t = float(i) / float(layers);            // 1 = oldest
    float m = historyTap(uv, i * spacing).a;
    vec3 c = palette == 0 ? hue(t * 0.8 + iTime * hueSpeed) : palette == 1 ? mix(colorA, colorB, t) : colorA * (1.0 - t * 0.7);
    col = mix(col, c * bright, m * opacity * (1.0 - t * 0.5));
  }
  // the live subject stays in front
  col = mix(col, texture(iChannel0, uv).rgb, maskAt(uv));
  fragColor = vec4(col, 1.0);
}
