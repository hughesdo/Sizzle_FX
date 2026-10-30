// Imported from SuperTool amiga-sinus-2/main.glsl
/*
 * Amiga Sinus 2 - Advanced Multi-Layer Sinus Scroller
 * Adapted for DISCO system by Augment Agent
 *
 * Original: AA_Sinus_Scroller.glsl by gPlatl
 * Draw antialiased sinus scroller with lighted characters
 * v1.0  2017-01-27  initial version
 * v2.0  2017-01-28  now 3d lighted
 * v2.1  2018-10-09  Soundcloud music changed
 * v2.2  2024-04-23  fixed text added
 *
 * scroller: https://www.shadertoy.com/view/XtyXzt
 * aa font:  https://www.shadertoy.com/view/4ltXzl
 * 2d & 3d:  https://www.shadertoy.com/view/MtVXRd
 */

// SuperTool intake note: ported from DISCO-GLSL-Video-Processor
// (Shaders/AmigaSinus2.glsl). Standard uniform / #version / in-out declarations
// dropped (injected by GLSLRenderer); iChannel2 is the Amiga font atlas
// (declared in meta.json). No video input, no audio -> generative. DISCO's
// text-input system is replaced by the file's baked default messages, since
// SuperTool has no scroll-text UI. The unused scrollText*Length uniforms were
// removed. mainImage reproduces DISCO's v_text (y-down) coordinate via a Y-flip.

// User-defined controls (replacing mouse input)
uniform float sinusAmplitude;    // Sinus wave amplitude (0.0-2.0)
uniform float use3DLighting;     // 3D lighting toggle (0.0=2D, 1.0=3D)
uniform float scrollSpeed;       // Text scrolling speed (0.1-3.0)

//--- common data ---
float time = 0.0;
vec2 pos = vec2(0);  //  0 .. 1
vec2 uv  = vec2(0);  // -1 .. 1
vec2 tp  = vec2(0);  // text position

//--- font data ---
#define FONT_SIZE1 0.2
#define FONT_SIZE2 0.45
#define FONT_SIZE3 0.3
#define FONT_SPACE 0.45
#define SIN_FREQ 0.75
#define SIN_SPEED 2.0
#define SCROLL_LEN 30.
#define SCROLL_SPEED 2.0

//----- access to the image of ascii code characters ------
#define S(a) cc+=fontChar(a); tp.x-=FONT_SPACE;

#define _note  S(10);
#define _star  S(28);
#define _smily S(29);
#define _    S(32);
#define _exc S(33);
#define _add S(43);
#define _comma S(44);
#define _sub S(45);
#define _dot S(46);
#define _slash S(47);
#define _ddot S(58);
#define _sc   S(59);
#define _less S(60);
#define _eq   S(61);
#define _gr   S(62);
#define _qm   S(63);
#define _at   S(64);

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

// return character intensity of ch at position tp
float fontChar(int ch)
{
  // Fixed texture coordinate calculation (same as AmigaSinus1)
  float x = float(ch - ch/16*16);  // Column (0-15)
  float y = float(ch/16);          // Row (0-15) - correct mapping

  // Atlas cell from the char code. SuperTool uploads the font UNPACK_FLIP_Y'd
  // (image-top at v=1) — the vertical mirror of DISCO's ModernGL upload. Take
  // the row from the top (1.0 - ...) and do NOT pre-flip tp.y, so the correct
  // glyph is selected AND rendered right-side up.
  vec2 texCoord = vec2(0.0625 * (tp.x + x), 1.0 - 0.0625 * (tp.y + y));

  vec4 f = any(lessThan(vec4(tp,1,1), vec4(0,0,tp)))
               ? vec4(0)
               : texture(iChannel2, texCoord);
  if (use3DLighting < 0.5)
    return f.x;   // 2d
  else
    return f.x * (f.y+0.3)*(f.z+0.3)*2.0;   // 3d
}

vec4 ScrollText1()
{
  tp = uv / vec2(0.1, FONT_SIZE1);  // set font size

  // Center horizontally and position at top with padding
  tp.x += 3.5;
  tp.y -= 3.5;

  float cc = 0.0;   // char color

  // Header text (DISCO baked default)
  _T _E _S _T

  return cc * vec4(pos, 0.5, 1.0);
}

vec4 ScrollText2()
{
  tp = uv / FONT_SIZE2;  // set font size
  tp.x = 2.0*(tp.x - 4.0 + mod(time*SCROLL_SPEED*scrollSpeed, SCROLL_LEN));
  float SIN_AMP = (sinusAmplitude - 0.5) * 0.5;  // User-controlled amplitude
  tp.y = tp.y + 0.5 + SIN_AMP*sin(tp.x*SIN_FREQ + time*SIN_SPEED);

  float cc = 0.0;   // char color

  // Main scroll text (DISCO baked default)
  _H _e _l _l _o _ _D _I _S _C _O _exc

  return cc * vec4(pos, 0.5+0.5*sin(2.0*time),1.0);
}

vec4 ScrollText3()
{
  tp = uv / FONT_SIZE3;  // set font size
  tp.x = 2.0*(tp.x-5.8+mod(time*SCROLL_SPEED, SCROLL_LEN));
  tp.y = tp.y + 3.2;

  float cc = 0.0;   // char color

  // Bottom text (DISCO baked default)
  _D _I _S _C _O _ _A _m _i _g _a _ _v _i _b _e _s

  return cc * vec4(pos, 0.5+0.5*sin(time),1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
  // Reproduce DISCO's v_text (y-down) coordinate from gl_FragCoord (y-up).
  vec2 fc = vec2(fragCoord.x, iResolution.y - fragCoord.y);
  time = iTime;
  pos = fc / iResolution.xy; //  0 .. 1
  uv = pos*2.0 - 1.0;        // -1 .. 1

  vec4 bgColor = vec4(0.05, 0.0, 0.18, 1.0);

  fragColor  = bgColor;
  fragColor += ScrollText1();
  fragColor += ScrollText2();
  fragColor += ScrollText3();
}
