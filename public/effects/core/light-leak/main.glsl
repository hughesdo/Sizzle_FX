// Light Leak: two soft blobs that wander along the frame edges, screened over the image.
uniform vec3  colorA;
uniform vec3  colorB;
uniform float amount;
uniform float size;
uniform float speed;
uniform float audioPush;

// a point that travels around the frame border (t in 0..1 loops)
vec2 edgePath(float t){
  t = fract(t) * 4.0;
  if (t < 1.0) return vec2(t, 0.0);
  if (t < 2.0) return vec2(1.0, t - 1.0);
  if (t < 3.0) return vec2(3.0 - t, 1.0);
  return vec2(0.0, 4.0 - t);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 base = texture(iChannel0, uv).rgb;
  float asp = iResolution.x / iResolution.y;
  float pump = 1.0 + audioPush * uAudio;
  float T = iTime * speed * 0.25 + uSeed * 0.013;
  vec2 pa = edgePath(T), pb = edgePath(T * 0.73 + 0.5);
  vec2 da = (uv - pa) * vec2(asp, 1.0), db = (uv - pb) * vec2(asp, 1.0);
  float s = size * (0.9 + 0.2 * sin(iTime * 0.7));
  float ga = exp(-dot(da, da) / (s * s * 0.5));
  float gb = exp(-dot(db, db) / (s * s * 0.35));
  // a faint streak across the frame, like light hitting the film gate
  float streak = exp(-pow((uv.y - 0.5 - 0.35 * sin(T * 6.2832)) * 6.0, 2.0)) * 0.25;
  vec3 leak = (colorA * (ga + streak) + colorB * gb) * amount * pump;
  vec3 col = 1.0 - (1.0 - base) * (1.0 - clamp(leak, 0.0, 1.0));   // screen
  fragColor = vec4(col, 1.0);
}
