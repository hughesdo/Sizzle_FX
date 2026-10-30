// Subject Aura: wide blurred matte, coloured by distance, behind the subject.
uniform float radius;
uniform float intensity;
uniform vec3  colorA;
uniform vec3  colorB;
uniform float flicker;
uniform float audioPush;

float noise(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5), b = fract(sin(dot(i + vec2(1, 0), vec2(127.1, 311.7))) * 43758.5);
  float c = fract(sin(dot(i + vec2(0, 1), vec2(127.1, 311.7))) * 43758.5), d = fract(sin(dot(i + vec2(1, 1), vec2(127.1, 311.7))) * 43758.5);
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  vec2 px = 1.0 / iResolution.xy;
  float pump = 1.0 + audioPush * uAudio;
  float R = radius * (iResolution.y / 1080.0) * pump;
  float near = 0.0, far = 0.0;
  for (int i = 0; i < 40; i++){
    float fi = float(i) + 0.5;
    float d = sqrt(fi / 40.0);
    float a = fi * 2.39996;
    float v = maskAt(uv + vec2(cos(a), sin(a)) * d * R * px);
    far += v; near += v * (1.0 - d);
  }
  far /= 40.0; near /= 20.0;
  vec2 p = (uv - uMaskCentroid) * vec2(iResolution.x / iResolution.y, 1.0);
  float fl = mix(1.0, 0.6 + 0.8 * noise(vec2(atan(p.y, p.x) * 3.0, iTime * 2.0)), flicker);
  vec3 aura = (colorA * clamp(near, 0.0, 1.0) + colorB * far) * intensity * fl * pump;
  vec3 col = base + aura * (1.0 - m0);
  fragColor = vec4(col, 1.0);
}
