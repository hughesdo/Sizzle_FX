// Lightning Bolt (after Timewarp post.glsl uBolt)
uniform float threshold;
uniform float strength;
uniform float rate;
uniform float tilt;
uniform vec3  color;
uniform float always;

float hash11(float p){ p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 col = texture(iChannel0, uv).rgb;
  float on = always > 0.5 ? 1.0 : clamp((uAudio - threshold) / max(1e-3, 1.0 - threshold), 0.0, 1.0);
  if (on <= 0.001){ fragColor = vec4(col, 1.0); return; }
  vec2 p = (uv - 0.5) * vec2(iResolution.x / iResolution.y, 1.0);
  float k = floor(iTime * rate) + uSeed;
  float ang = tilt + (hash11(k * 0.37) - 0.5) * 0.6;
  vec2 q = mat2(cos(ang), sin(ang), -sin(ang), cos(ang)) * p;
  float y = 0.0, amp = 0.12, fr = 4.0;
  for (int i = 0; i < 5; i++){ y += (noise(vec2(q.x * fr, k + float(i) * 7.0)) - 0.5) * amp; amp *= 0.55; fr *= 2.1; }
  float d = abs(q.y - y);
  float bolt = exp(-d / 0.003) + exp(-d / 0.04) * 0.4;
  float yb = y + (noise(vec2(q.x * 9.0, k + 40.0)) - 0.5) * 0.15 * smoothstep(-0.1, 0.4, q.x);
  bolt += (exp(-abs(q.y - yb) / 0.002) + exp(-abs(q.y - yb) / 0.02) * 0.3) * smoothstep(-0.1, 0.3, q.x) * 0.7;
  col += color * bolt * strength * on * smoothstep(0.9, 0.3, abs(q.x));
  fragColor = vec4(col, 1.0);
}
