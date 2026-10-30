// Duotone
uniform vec3  shadow;
uniform vec3  highlight;
uniform float contrast;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  vec3 c = texture(iChannel0, uv).rgb;
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  l = clamp((l - 0.5) * contrast + 0.5 + audioPush * uAudio * 0.5, 0.0, 1.0);
  fragColor = vec4(mix(shadow, highlight, smoothstep(0.0, 1.0, l)), 1.0);
}
