// Imported from SuperTool liquid-paint-v2/buffer_a.glsl
// Liquid Paint V2 — flockaroo "single pass CFD" reworked as a video effect.
//
// Fluid algorithm: created by florian berger (flockaroo) - 2016.
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported.
// Source: https://www.shadertoy.com/view/MsGSRd  ("single pass CFD")
//
// This is the SAME rotational self-advection CFD as the "Spill" generative
// shader. The ONLY change vs. Spill's Buffer A is the seed line: instead of
// seeding a static image on the first frames, the live timeline clip
// (iChannel2 = "video-input") is continuously melted into the fluid, so the
// paint keeps flowing out of the moving footage. That keeps V2 honest to the
// flockaroo basis instead of the hand-rolled curl-noise feedback of V1.
//
// SuperTool runtime adaptations (it supplies neither iChannelResolution[] nor a
// keyboard channel): Res = iResolution.xy, Res1 = vec2(256.0) for the noise.
// Channels: iChannel0 = BufferA (self-feedback), iChannel1 = RGBA noise,
//           iChannel2 = live clip ("video-input").

#define RotNum 5
//#define SUPPORT_EVEN_ROTNUM

#define Res  iResolution.xy
#define Res1 vec2(256.0)

uniform float injectAmount;  // how strongly the live clip melts into the fluid

const float ang = 2.0*3.1415926535/float(RotNum);
mat2 m = mat2(cos(ang),sin(ang),-sin(ang),cos(ang));
mat2 mh = mat2(cos(ang*0.5),sin(ang*0.5),-sin(ang*0.5),cos(ang*0.5));

vec4 randS(vec2 uv)
{
    return texture(iChannel1,uv*Res.xy/Res1.xy)-vec4(0.5);
}

float getRot(vec2 pos, vec2 b)
{
    vec2 p = b;
    float rot=0.0;
    for(int i=0;i<RotNum;i++)
    {
        rot+=dot(texture(iChannel0,fract((pos+p)/Res.xy)).xy-vec2(0.5),p.yx*vec2(1,-1));
        p = m*p;
    }
    return rot/float(RotNum)/dot(b,b);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 pos = fragCoord.xy;
    float rnd = randS(vec2(float(iFrame)/Res.x,0.5/Res1.y)).x;

    vec2 b = vec2(cos(ang*rnd),sin(ang*rnd));
    vec2 v=vec2(0);
    float bbMax=0.7*Res.y; bbMax*=bbMax;
    for(int l=0;l<20;l++)
    {
        if ( dot(b,b) > bbMax ) break;
        vec2 p = b;
        for(int i=0;i<RotNum;i++)
        {
#ifdef SUPPORT_EVEN_ROTNUM
            v+=p.yx*getRot(pos+p,-mh*b);
#else
            // this is faster but works only for odd RotNum
            v+=p.yx*getRot(pos+p,b);
#endif
            p = m*p;
        }
        b*=2.0;
    }

    fragColor=texture(iChannel0,fract((pos+v*vec2(-1,1)*2.0)/Res.xy));

    // add a little "motor" in the center (flockaroo) — keeps the fluid churning
    vec2 scr=(fragCoord.xy/Res.xy)*2.0-vec2(1.0);
    fragColor.xy += (0.01*scr.xy / (dot(scr,scr)/0.1+0.3));

    // EFFECT MODE: continuously melt the live clip into the fluid.
    // (Spill seeds a static image only on the first frames; here we keep feeding
    // the moving clip so the paint flows out of the footage.)
    vec3 vid = texture(iChannel2, fragCoord.xy/Res.xy).rgb;
    if (iFrame <= 4) {
        fragColor = vec4(vid, 1.0);                       // seed from the clip
    } else {
        fragColor.rgb = mix(fragColor.rgb, vid, injectAmount);
        fragColor.a = 1.0;
    }
}
