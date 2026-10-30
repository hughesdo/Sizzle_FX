// Light Bars (after Timewarp post.glsl uBar/uBar2), animated sweep.
uniform int   count;
uniform float width;
uniform float angle;
uniform float speed;
uniform float strength;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  float aspect = iResolution.x / iResolution.y;
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
  vec3 col = texture(iChannel0, uv).rgb;
  vec2 d = vec2(cos(angle), sin(angle));
  float reach = 0.5 * (abs(d.x) * aspect + abs(d.y)) + width * 2.0;
  float A = clamp(strength + audioPush * uAudio, 0.0, 1.0);
  for (int b = 0; b < 4; b++){
    if (b >= count) break;
    float fb = float(b);
    float pos = fract(iTime * speed * (1.0 + 0.37 * fb) + fb * 0.41 + uSeed * 0.13) * 2.0 - 1.0;
    float s = dot(p, d) - pos * reach;
    float m = smoothstep(width, width * 0.75, abs(s));
    vec3 barC = vec3(1.0, 0.97, 0.9) - col * 0.12;
    col = mix(col, barC, m * A);
    col += vec3(0.2, 1.0, 0.9) * exp(-abs(s - width) / 0.004) * 0.6 * A;
    col += vec3(1.0, 0.3, 0.6) * exp(-abs(s + width) / 0.004) * 0.6 * A;
    col += vec3(1.0, 0.95, 0.9) * exp(-abs(s) / (width * 3.0)) * 0.25 * A;
  }
  fragColor = vec4(col, 1.0);
}
