// Frame Echo: decaying copies of earlier frames from the history ring.
// History holds the ORIGINAL source frames, so this composes over the chain input.
uniform int   echoes;
uniform int   spacing;
uniform float decay;
uniform float audioPush;
uniform int   mode;

vec3 hue(float h){ return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float d = clamp(decay + audioPush * uAudio, 0.0, 0.99);
  vec3 acc = base; float wsum = 1.0, w = 1.0;
  vec3 lit = base;
  for (int i = 1; i <= 15; i++){
    if (i > echoes) break;
    w *= d;
    vec3 h = historyTap(uv, i * spacing).rgb;
    if (mode == 2) h *= mix(vec3(1.0), hue(float(i) / float(echoes) + iTime * 0.1) * 1.5, 0.8);
    acc += h * w; wsum += w;
    lit = max(lit, h * w);
  }
  fragColor = vec4(mode == 0 ? acc / wsum : lit, 1.0);
}
