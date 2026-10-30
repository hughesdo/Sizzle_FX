// Slice Glitch (after Timewarp post.glsl)
uniform float amount;
uniform float audioPush;
uniform float bands;
uniform float rate;
uniform float rgbTear;

float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float s = clamp(amount + audioPush * uAudio, 0.0, 1.5);
  float band = floor(uv.y * bands);
  float k = floor(iTime * rate) + uSeed * 17.0;
  float h = hash12(vec2(band, k));
  float shift = 0.0;
  if (h > 1.0 - s * 0.6) shift = (hash12(vec2(band, k + 5.0)) - 0.5) * 0.15 * s;
  vec2 u = vec2(fract(uv.x + shift), uv.y);
  float t = shift * rgbTear;
  fragColor = vec4(texture(iChannel0, u + vec2(t, 0.0)).r, texture(iChannel0, u).g, texture(iChannel0, u - vec2(t, 0.0)).b, 1.0);
}
