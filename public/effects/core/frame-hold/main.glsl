// Choppy / Frame Hold: show the frame from the start of each hold window.
// Note: reads the ORIGINAL source frames from history (effects below this lane are skipped while held).
uniform int   hold;
uniform float audioPush;

void mainImage(out vec4 fragColor, in vec2 fragCoord){
  vec2 uv = fragCoord / iResolution.xy;
  int h = clamp(hold + int(floor(audioPush * uAudio * 8.0)), 1, HISTORY_DEPTH - 1);
  int ago = iFrame % h;
  fragColor = ago == 0 ? texture(iChannel0, uv) : vec4(historyTap(uv, ago).rgb, 1.0);
}
