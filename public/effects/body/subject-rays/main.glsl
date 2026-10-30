// Subject Rays: radial march from each pixel toward a light hidden behind the subject.
// Light = the matte (slightly eroded) seen from the pixel; occluder = nothing (it's a backlight),
// so beams appear around the silhouette and are composited behind the subject.
uniform float rayLength;
uniform float decay;
uniform float intensity;
uniform vec3  color;
uniform float streaks;
uniform vec2  offset;
uniform float audioPush;

float hash(float n){ return fract(sin(n) * 43758.5453); }

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float m0 = maskAt(uv);
  float pump = 1.0 + audioPush * uAudio;
  vec2 src = uMaskCentroid + offset;
  vec2 d = (uv - src) * rayLength * pump / 32.0;
  vec2 p = uv;
  float illum = 0.0, w = 1.0;
  float j = hash(dot(fragCoord, vec2(12.9898, 78.233)));   // dither the march start
  p -= d * j;
  for (int i = 0; i < 32; i++){
    p -= d;
    illum += maskAt(p) * w;
    w *= decay;
  }
  illum /= 12.0;
  // angular streaks so it reads as beams, slowly turning
  vec2 q = (uv - src) * vec2(iResolution.x / iResolution.y, 1.0);
  float ang = atan(q.y, q.x);
  float beam = 0.55 + 0.45 * sin(ang * 14.0 + iTime * 0.4) * sin(ang * 5.0 - iTime * 0.25);
  illum *= mix(1.0, beam, streaks);
  vec3 col = base + color * illum * intensity * pump * (1.0 - m0 * 0.85);
  fragColor = vec4(col, 1.0);
}
