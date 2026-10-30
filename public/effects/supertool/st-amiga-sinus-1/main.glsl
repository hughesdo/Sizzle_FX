// Imported from SuperTool amiga-sinus-1/main.glsl
/*
 * Amiga Sinus 1 - Classic Amiga Demo Scene Scroller
 * Adapted for DISCO system by Augment Agent
 *
 * Original: Amiga Scroller with Bouncing Balls by misol101
 * https://www.shadertoy.com/view/ctGfWR
 *
 * AA Sinus Scroller originally by gPlatl
 * Bouncing balls added by misol101
 * Created by misol101 in 2023-12-07
 */

// SuperTool intake note: ported from DISCO-GLSL-Video-Processor
// (Shaders/AmigaSinus1.glsl). Standard uniform / #version / in-out declarations
// were dropped (GLSLRenderer injects them); iChannel0 is the Amiga font atlas
// (declared in meta.json). DISCO's text-input system would replace the macro
// sequence in ScrollText() with the user's typed message — SuperTool has no
// text-input UI, so the file's baked default ("Hello") is rendered. The unused
// iChannel1 ("ball physics buffer") and scrollTextLength uniform were removed
// (the simplified DISCO ball path uses calculateSimpleBall, not a buffer).

// User configurable uniforms
uniform float ballSpeed;       // Ball animation speed multiplier (0.1-3.0)
uniform float sinusAmplitude;  // Sinus wave amplitude for text (0.0-2.0)
uniform float scrollSpeed;     // Text scrolling speed (0.1-3.0)

// Global variables and constants
vec2 pos = vec2(0), uv = vec2(0), tp = vec2(0), normal = vec2(0);

#define SCROLL_LEN 33.
#define SCROLL_SPEED 1.5
#define SCROLL_TIME_MOD(t) mod(t*SCROLL_SPEED, SCROLL_LEN)

#define FONT_SIZE 0.25
#define FONT_SPACE 0.45
#define SIN_FREQ 1.31
#define SIN_SPEED 3.0
#define SIN_AMP 0.75

#define NOF_BALLS 35
#define BALL_SIZE 0.009
#define BALL_GRAVITY 0.1666

// Complete Amiga Font Character Macro System
// Maps user text to correct texture atlas positions
#define SPACE tp.x-=FONT_SPACE;

#define S(a) c+=fontChar(a);   tp.x-=FONT_SPACE;

#define _note  S(10);   //
#define _star  S(28);   // *
#define _smily S(29);
#define _ tp.x-=FONT_SPACE;
#define _exc   S(33);   // !
#define _add   S(43);   // +
#define _comma S(44);   // ,
#define _sub   S(45);   // -
#define _dot   S(46);   // .
#define _slash S(47);   // /

#define _0 S(48);
#define _1 S(49);
#define _2 S(50);
#define _3 S(51);
#define _4 S(52);
#define _5 S(53);
#define _6 S(54);
#define _7 S(55);
#define _8 S(56);
#define _9 S(57);
#define _ddot S(58);   // :
#define _sc   S(59);   // ;
#define _less S(60);   // <
#define _eq   S(61);   // =
#define _gr   S(62);   // >
#define _qm   S(63);   // ?
#define _at   S(64);   // at sign

#define _A S(65);
#define _B S(66);
#define _C S(67);
#define _D S(68);
#define _E S(69);
#define _F S(70);
#define _G S(71);
#define _H S(72);
#define _I S(73);
#define _J S(74);
#define _K S(75);
#define _L S(76);
#define _M S(77);
#define _N S(78);
#define _O S(79);
#define _P S(80);
#define _Q S(81);
#define _R S(82);
#define _S S(83);
#define _T S(84);
#define _U S(85);
#define _V S(86);
#define _W S(87);
#define _X S(88);
#define _Y S(89);
#define _Z S(90);

#define _a S(97);
#define _b S(98);
#define _c S(99);
#define _d S(100);
#define _e S(101);
#define _f S(102);
#define _g S(103);
#define _h S(104);
#define _i S(105);
#define _j S(106);
#define _k S(107);
#define _l S(108);
#define _m S(109);
#define _n S(110);
#define _o S(111);
#define _p S(112);
#define _q S(113);
#define _r S(114);
#define _s S(115);
#define _t S(116);
#define _u S(117);
#define _v S(118);
#define _w S(119);
#define _x S(120);
#define _y S(121);
#define _z S(122);


// Function to get texture position and normal vector
void getTp(float time) {
    tp = uv / FONT_SIZE;
    float ty = tp.y;
    tp.x = 2.0*(tp.x - 4. + mod(time*SCROLL_SPEED*scrollSpeed, SCROLL_LEN));
    float adjustedSinAmp = SIN_AMP * sinusAmplitude;
    tp.y = ty + 2.9 + adjustedSinAmp*sin(tp.x*SIN_FREQ + time*SIN_SPEED);
    normal = vec2(-0.4, cos(tp.x*SIN_FREQ + time*SIN_SPEED));
}

// Character rendering function
float fontChar(int ch) {
    // Keep the working character mapping - don't change x,y calculation
    float x = float(ch - ch/16*16);  // Column (0-15)
    float y = float(ch/16);          // Row (0-15) - this gives correct chars

    // Atlas cell from the char code. SuperTool uploads the font UNPACK_FLIP_Y'd
    // (image-top at v=1) — the vertical mirror of DISCO's ModernGL upload. Take
    // the row from the top (1.0 - ...) and do NOT pre-flip tp.y, so the correct
    // glyph is selected AND rendered right-side up.
    vec2 texCoord = vec2(0.0625 * (tp.x + x), 1.0 - 0.0625 * (tp.y + y));

    vec4 f = any(lessThan(vec4(tp,1,1), vec4(0,0,tp)))
                 ? vec4(0)
                 : texture(iChannel0, texCoord);
    return f.x;
}

// Scroll text function using clean character macros
vec4 ScrollText() {
    getTp(iTime);
    float c = 0.0;

    // Single-spaced text rendering - "Hello" becomes "H e l l o"
    // Just one space between characters for sine wave animation
    _H _e _l _l _o

    return c * vec4(0.36, 0.27, 0.5, 1.) * 1.75;
}

// Sphere rendering with anti-aliasing
vec4 sphere(vec2 fragCoord, vec2 ballPos, float rad, vec4 col, vec4 orgCol, float AA) {
    float dist = distance(fragCoord, ballPos);
    return mix(col, orgCol, smoothstep(rad-iResolution.x*AA, rad, dist));
}

// Ball rendering with multiple spheres for 3D effect
vec4 drawBall(vec2 fragCoord, vec2 ballPos, vec4 col, float rad) {
    vec4 ballCol = vec4(0.95, 0.19, 0.4, 1.);
    col = sphere(fragCoord, ballPos, rad, ballCol * 0.55, col, 0.004);
    col = sphere(fragCoord, ballPos-vec2(rad*0.1,-rad*0.1), rad*0.65, ballCol * 3., col, 0.006);
    return sphere(fragCoord, ballPos-vec2(rad*0.2,-rad*0.2), rad*0.2, ballCol*6.5, col, 0.0015);
}

// Simplified ball physics for DISCO system
vec4 calculateSimpleBall(int ballIndex, float time) {
    float PX = iResolution.x * 0.00125;

    // Simple sinusoidal motion for balls with user-controlled speed
    float phase = float(ballIndex) * 0.5 + time * ballSpeed * 2.0;
    float x = iResolution.x * 0.5 + cos(phase) * iResolution.x * 0.3;
    float y = iResolution.y * 0.6 + sin(phase * 1.3) * iResolution.y * 0.2;

    return vec4(x, y, 0, 0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Reproduce DISCO's coordinate convention (v_text * iResolution.xy, top-left
    // origin / y-down) from SuperTool's gl_FragCoord (y-up) by flipping Y, so
    // the font glyphs render in the same orientation as the original.
    vec2 fc = vec2(fragCoord.x, iResolution.y - fragCoord.y);
    pos = fc / iResolution.xy;
    uv = pos*2.0 - 1.0;

    vec4 col = vec4(0.05, 0., 0.18, 1.);

    // Render scrolling text in specific area
    if (uv.y < -0.3 && uv.y > -0.9) {
        col = max(ScrollText(), col);
    }

    vec4 oldCol = col;

    // Draw bouncing balls with simplified physics
    for (int i = 0; i < NOF_BALLS; i++) {
        vec4 ball = calculateSimpleBall(i, iTime);
        if (distance(fc.xy, ball.xy) < iResolution.x * BALL_SIZE) {
            col = drawBall(fc, ball.xy, col, iResolution.x * BALL_SIZE);
            // Fade in/out effects for balls
            col = mix(oldCol, col, clamp(SCROLL_TIME_MOD(iTime), 0., 0.5) * 2.);
            col = mix(oldCol, col, clamp(SCROLL_LEN-2.0-SCROLL_TIME_MOD(iTime), 0., 3.) * 0.333);
        }
    }

    fragColor = col;
}
