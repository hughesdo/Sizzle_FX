// Film Grade (tone + grain after Timewarp final.glsl)
uniform float exposure;
uniform float saturation;
uniform float warmth;
uniform float shoulder;
uniform float vignette;
uniform float grain;

float hash13(vec3 p){ p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 c = texture(iChannel0, uv).rgb * exp2(exposure);
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(vec3(l), c, saturation);
  // split tone: cool shadows, warm highlights
  vec3 warm = vec3(1.06, 0.99, 0.9), cool = vec3(0.92, 0.98, 1.08);
  c *= mix(mix(vec3(1.0), cool, warmth), mix(vec3(1.0), warm, warmth), smoothstep(0.1, 0.7, l));
  // soft shoulder
  vec3 rolled = c / (1.0 + c * 0.6);
  c = mix(c, rolled * 1.35, shoulder);
  // vignette
  vec2 p = (uv - 0.5) * vec2(iResolution.x / iResolution.y, 1.0);
  c *= 1.0 - vignette * smoothstep(0.35, 1.05, length(p));
  // grain sized for 1080p regardless of output size
  vec2 g = floor(fragCoord * (1080.0 / iResolution.y));
  float n = hash13(vec3(g, float(iFrame) + uSeed * 31.0)) - 0.5;
  c += n * grain * (0.6 + 0.4 * (1.0 - l));
  fragColor = vec4(max(c, 0.0), 1.0);
}
