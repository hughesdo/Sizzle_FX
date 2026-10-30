// Imported from SuperTool liquid-paint-v2/main.glsl
// Liquid Paint V2 — Image (composite).
//
// flockaroo's gradient/normal-based lighting of the advected fluid
// (iChannel0 = BufferA). Lighting: florian berger (flockaroo) 2016,
// CC BY-NC-SA 3.0. Source: https://www.shadertoy.com/view/MsGSRd
//
// SuperTool addition (non-destructive — the fluid sim is untouched): a colour
// stage that turns flockaroo's shiny "molten water" into oil-slick PAINT. The
// CFD averages neighbouring colours toward grey, and the original white
// specular washes highlights out, so here we (1) lift saturation, (2) add an
// iridescent sheen whose hue follows the fluid's flow direction, and (3) tint
// the specular by the paint colour instead of pure white. Set saturation = 1
// and iridescence = 0 to get the plain flockaroo look back.

uniform float videoMix;     // 0 = pure paint, 1 = crisp clip
uniform float saturation;   // paint colour saturation lift
uniform float iridescence;  // oil-slick sheen from the fluid flow (0 = off)

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0*d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float getVal(vec2 uv)
{
    return length(texture(iChannel0,uv).xyz);
}

vec2 getGrad(vec2 uv,float delta)
{
    vec2 d=vec2(delta,0);
    return vec2(
        getVal(uv+d.xy)-getVal(uv-d.xy),
        getVal(uv+d.yx)-getVal(uv-d.yx)
    )/delta;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord.xy / iResolution.xy;

    vec2 grad = getGrad(uv, 1.0/iResolution.y);
    vec3 n = normalize(vec3(grad, 150.0));
    vec3 light = normalize(vec3(1,1,2));
    float diff = clamp(dot(n,light), 0.5, 1.0);
    float spec = clamp(dot(reflect(light,n), vec3(0,0,-1)), 0.0, 1.0);
    spec = pow(spec, 36.0) * 1.6;   // a touch softer than flockaroo's 2.5

    // --- paint colour stage (non-destructive) ---
    vec3 base = texture(iChannel0, uv).xyz;
    vec3 hsv = rgb2hsv(base);
    hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);   // recover colour the CFD greyed out
    vec3 col = hsv2rgb(hsv);

    // oil-slick sheen: hue follows the fluid's flow (gradient) direction,
    // drifting slowly so the colours marble over time.
    float dir = atan(grad.y, grad.x) / 6.2831853 + 0.5;     // 0..1
    vec3 sheen = hsv2rgb(vec3(fract(dir + 0.02*iTime), 0.9, 1.0));
    col = mix(col, col*sheen + sheen*0.15, iridescence);

    // flockaroo lighting, with the specular tinted by the paint colour so the
    // highlights stay vivid instead of blowing out to white.
    vec3 paint = col*diff + spec*mix(vec3(1.0), col, 0.6);

    vec3 clip = texture(iChannel1, uv).rgb;
    fragColor = vec4(mix(paint, clip, clamp(videoMix, 0.0, 1.0)), 1.0);
}
