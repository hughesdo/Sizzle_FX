// Imported from SuperTool effects/AmigaSinus31.glsl by scripts/import-supertool.mjs
/*
 * Amiga Sinus 3.1 - Enhanced Amiga Demo Collection with Audio Reactivity
 * Adapted for DISCO system by Augment Agent
 *
 * Based on AmigaSinus3.glsl with additional features and improvements
 * Version 3.1 - Enhanced audio reactivity and user controls
 *
 * Original: Amiga_Demos_1.glsl by gPlatl
 * Collection of Amiga based demos...
 *   v0.1  2016-01-31  initial version
 *   v1.0  2016-04-19  first release
 *   v3.1  2025-06-29  DISCO enhanced version
 *
 * Used codes...
 * ReadKey:    https://www.shadertoy.com/view/llVSRm
 * Scroller:   https://www.shadertoy.com/view/MtySzd
 * RGB_Bars:   https://www.shadertoy.com/view/4lVGzc
 * Copper:     https://www.shadertoy.com/view/Md3GRl
 * RubberCube: https://www.shadertoy.com/view/4lt3R7
 * Amigaball:  https://www.shadertoy.com/view/Xd3XWX
 * Greetings:  https://www.shadertoy.com/view/ld2yDz
 */

// SuperTool intake note: ported from DISCO-GLSL-Video-Processor
// (Shaders/AmigaSinus3.1.glsl). #version / standard + audio uniform / in-out decls
// dropped (GLSLRenderer injects standard ones). iChannel0 = layer-below video
// (video-inside-text mask), iChannel1 = Amiga font atlas (declared in the
// metadata.json effect entry channels). DISCO host audio uniforms mapped to the
// injected FFT helpers as globals in mainImage. Unused textLength chunk uniforms
// and scrollText*Length were dropped; the scroll messages are baked (no text UI).
// mainImage reproduces DISCO v_text (y-down) for the text scene via a Y-flip,
// while the video mask samples upright at fragCoord/res.



// User-defined controls (replacing keyboard/mouse input)
uniform float fontSize;           // Font size multiplier for video-inside-text effect (1.0-10.0)
uniform float scrollSpeed1;       // Main scroll text speed (0.1-3.0)
uniform float scrollSpeed2;       // Bottom text scroll speed (0.1-3.0)
uniform float textLength1;        // Main text length for dynamic scrolling
uniform float textLength2;        // Bottom text length for dynamic scrolling

// Editable scroll messages, passed as ASCII char-code arrays (0 = end-of-string).
// Filled from the "text" uniforms scrollText1 / scrollText2 in the metadata
// entry, which the renderer encodes from the user's typed text (SuperTool has
// a text field in the shader-clip properties for these). DISCO generated GLSL
// char macros at compile time; here the equivalent loop reads the array.
// 256 chars per scroll message. Each element of a `uniform int[]` consumes a
// whole GL_MAX_FRAGMENT_UNIFORM_VECTORS slot (drivers do NOT pack 4 ints into a
// vec4 here), so two int[256] arrays already use 512 of the 1024-vector budget.
// 512 each (1024 total) overflowed the limit alongside the other uniforms and
// failed to compile — do not raise this without switching to a packed/texture
// encoding. Keep maxLength in metadata.json in sync with this value.
#define SCROLL_MAX 256
uniform int scrollText1[SCROLL_MAX];   // Main scroll message (ASCII codes)
uniform int scrollText2[SCROLL_MAX];   // Bottom scroll message (ASCII codes)

uniform float sinusAmplitude;     // Sinus wave amplitude (0.0-2.0)
uniform float use3DLighting;      // 3D lighting toggle (0.0=2D, 1.0=3D)
uniform float demoMode;           // Demo selection (0.0=auto, 1.0-4.0=manual)
uniform float backgroundMode;     // Background selection (0.0=auto, 1.0-4.0=manual)
uniform float autoSwitchSpeed;    // Auto demo switch speed (0.1-2.0)

// Main scroll text fill: DISCO always filled the big text with the user's video
// ("video-inside-text"). In SuperTool iChannel0 is the layer BELOW the shader
// clip, so with nothing underneath the text reads as solid black. useVideoFill
// toggles between that video fill and a solid fontColor so it works either way.
uniform vec3 fontColor;           // Solid color for the main text (when not video-filled)
uniform float useVideoFill;       // 0 = solid fontColor, 1 = fill main text with layer-below video

// Audio levels are filled from the injected FFT helpers in mainImage below.



//--- common data ---
float time = 0.0;
// Audio levels (set in mainImage from FFT helpers; read as globals by the demos)
float bassLevel = 0.0, midLevel = 0.0, trebleLevel = 0.0;
float beatLevel = 0.0, kickLevel = 0.0, audioIntensity = 0.0;
bool mousePressed = false;
vec2 pos = vec2(0);      //  0 .. 1
vec2 uv  = vec2(0);      // -1 .. 1
vec2 aspect = vec2(1.0); // R.xy / R.y

vec2 tp  = vec2(0);      // text position
vec3 aColor = vec3(0);

//== font handling =========================================

//--- font data ---
#define FONT_SIZE1 0.40
#define FONT_SIZE2 0.25
#define FONT_SPACE 0.45

const vec2 vFontSize  = vec2(8.0, 15.0);  // multiples of 4x5 work best

//----- access to the image of ascii code characters ------
#define SPACE tp.x-=FONT_SPACE;
#define S(a) c+=fontChar(a);   tp.x-=FONT_SPACE;

#define _note  S(10);
#define _star  S(28);
#define _smily S(29);
#define _ tp.x-=FONT_SPACE;
#define _exc   S(33);
#define _dblq  S(34);  // "
#define _hash  S(35);  // #
#define _doll  S(36);  // $
#define _perc  S(37);  // %
#define _amp   S(38);  // &
#define _apos  S(39);  // '
#define _lpar  S(40);  // (
#define _rpar  S(41);  // )
#define _ast   S(42);  // *
#define _add   S(43);
#define _comma S(44);
#define _sub   S(45);
#define _dot   S(46);
#define _slash S(47);

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
#define _ddot S(58);
#define _sc S(59);
#define _less S(60);
#define _eq S(61);
#define _gr S(62);
#define _qm S(63);
#define _at S(64);
#define _lsq S(91);   // [
#define _bslash S(92); // \
#define _rsq S(93);   // ]
#define _caret S(94); // ^
#define _uscore S(95); // _
#define _bquote S(96); // `
#define _lcurl S(123); // {
#define _pipe S(124);  // |
#define _rcurl S(125); // }
#define _tilde S(126); // ~
#define _mdot  S(183); // ·
#define _rsquo S(180); // ' (right single quotation mark)

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

//----------------------------------------------------------
// return font image intensity of character ch at text position tp
//----------------------------------------------------------
float fontChar(int ch)
{
  // Fixed texture coordinate calculation (same as AmigaSinus1 & 2)
  float x = float(ch - ch/16*16);  // Column (0-15)
  float y = float(ch/16);          // Row (0-15) - correct mapping

  // Atlas cell from the char code. SuperTool uploads the font UNPACK_FLIP_Y'd
  // (image-top at v=1) — the vertical mirror of DISCO's ModernGL upload. Take
  // the row from the top (1.0 - ...) and do NOT pre-flip tp.y, so the correct
  // glyph is selected AND rendered right-side up.
  vec2 texCoord = vec2(0.0625 * (tp.x + x), 1.0 - 0.0625 * (tp.y + y));

  vec4 f = any(lessThan(vec4(tp,1,1), vec4(0,0,tp)))
               ? vec4(0)
               : texture(iChannel1, texCoord);
  if (use3DLighting < 0.5)
    return f.x;   // 2d
  else
    return f.x * (f.y+0.3)*(f.z+0.3)*2.0;   // 3d
}

//----------------------------------------------------------
// render scroll text with audio-reactive sinus amplitude
//----------------------------------------------------------

#define SCROLL_SPEED 2.0
#define SCROLL_LEN 40.
#define SIN_FREQ 0.75
#define SIN_SPEED 3.0

//----------------------------------------------------------
vec3 ScrollText1()
{
  // Use dynamic font size from uniform (larger fontSize = larger text)
  float dynamicFontSize = FONT_SIZE1 * fontSize;
  tp = uv / dynamicFontSize;
  tp.x = 2.0*(tp.x -4.0 +mod(time*SCROLL_SPEED*scrollSpeed1, textLength1));

  // Audio-reactive sinus amplitude
  float audioSinusAmp = sinusAmplitude + bassLevel * 0.5 + beatLevel * 0.3;
  float SIN_AMP = 1.5 * audioSinusAmp / 2.0 - 0.5;
  tp.y += 0.4 + SIN_AMP*sin(tp.x*SIN_FREQ + time*SIN_SPEED + trebleLevel * 2.0);

  float c = 0.0;

  // Render the user's main scroll text from the char-code array (0 ends it).
  for (int k = 0; k < SCROLL_MAX; k++) {
    int ch = scrollText1[k];
    if (ch == 0) break;
    c += fontChar(ch);
    tp.x -= FONT_SPACE;
  }

  // Where the glyphs are solid, fill them either with the layer-below video
  // (video-inside-text) or with the solid fontColor — useVideoFill chooses.
  // `c` carries the per-pixel intensity from fontChar(), which in 3D mode bakes
  // the bevel lighting ( f.x*(f.y+0.3)*(f.z+0.3)*2.0 ). The solid-color path must
  // multiply by `c` to preserve that shading — returning a flat fontColor (as a
  // previous revision did) discards use3DLighting entirely, which is the bug
  // ScrollText2 never had because it returns `c * vec3(...)`.
  if (c >= 0.5) {
    if (useVideoFill > 0.5) {
      // SuperTool video-input is upright at fragCoord/res (no extra Y-flip).
      vec2 videoCoord = gl_FragCoord.xy / iResolution.xy;
      return texture(iChannel0, videoCoord).rgb;
    }
    return fontColor * c;
  }

  // Return background where no text
  return aColor;
}

//----------------------------------------------------------
vec3 ScrollText2()
{
  tp = uv / FONT_SIZE2;  // set font size
  tp.x = 1.8*(tp.x -4.0 +mod(time*SCROLL_SPEED*scrollSpeed2, textLength2));
  tp.y = (uv.y + 0.88) / 0.2;  // set position & font size

  float c = 0.0;

  // Render the user's bottom scroll text from the char-code array (0 ends it).
  for (int k = 0; k < SCROLL_MAX; k++) {
    int ch = scrollText2[k];
    if (ch == 0) break;
    c += fontChar(ch);
    tp.x -= FONT_SPACE;
  }

  // Audio-reactive color with mid-frequency modulation
  vec3 fcol = c * vec3(pos, 0.5+0.5*sin(time + midLevel * 4.0));
  if (c >= 0.5) return fcol;
  return mix (aColor, fcol, c);
}

//----------------------------------------------------------
// render red white blue sinus bars with audio reactivity
//----------------------------------------------------------
vec3 calcSine(float frequency, float amplitude, float shift, float yOffset
             ,vec3 color, float height)
{
  float audioFreq = frequency + audioIntensity * 0.5;
  float audioAmp = amplitude + bassLevel * 0.2;
  float y = sin(time * audioFreq + shift + uv.x) * audioAmp + yOffset;
  return color * smoothstep(height, 0.0, distance(y, uv.y));
}

vec3 RGB_Bars()
{
  return calcSine(2.0, 0.25, 0.0, 0.5, vec3(0.0, 0.0, 1.0), 0.10)      // Blue
       + calcSine(2.6, 0.15, 0.2, 0.5, vec3(1.0, 1.0, 1.0), 0.10)      // White
       + calcSine(0.9, 0.35, 0.5, 0.5, vec3(1.0, 0.0, 0.0), 0.10);     // Red
}

//----------------------------------------------------------
// render Amiga Red and Blues with audio reactivity
//----------------------------------------------------------
vec3 Copper()
{
  float df = time * (0.8 + audioIntensity * 0.4);

  vec3 barColor = vec3(0.0);
  float barsize = 0.04 + beatLevel * 0.02;

  for(float i=0.0; i<0.9; i+=0.08)
  {
    float p = 0.7 + 0.2 * cos(1.8*time+160.*i + kickLevel * 2.0);
    if ((pos.y <= p + barsize) && (pos.y >= p - barsize))
    {
      // Alternate between red and blue bars with white highlights
      float barIndex = floor(i * 12.5); // Convert i to bar index
      vec3 baseColor;

      if (mod(barIndex, 2.0) < 1.0) {
        // Red bars with audio reactivity
        baseColor = vec3(1.0, 0.2 + bassLevel * 0.3, 0.2 + bassLevel * 0.3);
      } else {
        // Blue bars with audio reactivity
        baseColor = vec3(0.2 + trebleLevel * 0.3, 0.2 + midLevel * 0.3, 1.0);
      }

      float intensity = 1.0 - abs(p - pos.y) / barsize;
      barColor = intensity * baseColor;
    }
  }
  return barColor;
}

//----------------------------------------------------------
// Enhanced plasma background with improved algorithm and audio reactivity
// Based on upgraded plasma code with patriotic color scheme
//----------------------------------------------------------
vec3 Plasma()
{
  // Audio-reactive time scaling
  float audioTime = time * (1.0 + audioIntensity * 0.5);

  // Calculate UV coordinates (adapted from fragCoord/iResolution.xy to pos)
  vec2 uv = (pos - 0.5) * 8.0;
  vec2 uv0 = uv;

  // Enhanced plasma algorithm parameters
  float i0 = 1.0;
  float i1 = 1.0 + bassLevel * 0.2;  // Bass affects iteration speed
  float i2 = 1.0;
  float i4 = 0.0;

  // Improved plasma generation loop
  for(int s = 0; s < 7; s++)
  {
    vec2 r;
    r = vec2(cos(uv.y * i0 - i4 + audioTime / i1), sin(uv.x * i0 - i4 + audioTime / i1)) / i2;
    r += vec2(-r.y, r.x) * (0.3 + midLevel * 0.1);  // Mid frequencies affect swirl
    uv.xy += r;

    i0 *= 1.93;
    i1 *= 1.15;
    i2 *= 1.7;
    i4 += 0.05 + 0.1 * audioTime * i1;
  }

  // Enhanced patriotic color generation with audio reactivity
  float r = sin(uv.x - audioTime + bassLevel * 2.0) * 0.5 + 0.5;      // Red with bass
  float b = sin(uv.y + audioTime + trebleLevel * 2.0) * 0.5 + 0.5;    // Blue with treble
  float g = sin((uv.x + uv.y + sin(audioTime * 0.5)) * 0.5 + midLevel * 2.0) * 0.5 + 0.5;  // White/green with mid

  // Patriotic color mixing - emphasize red, white, blue
  vec3 col = vec3(
    r * (0.8 + bassLevel * 0.4),           // Enhanced red with bass boost
    g * (0.6 + midLevel * 0.4),            // White component with mid boost
    b * (0.8 + trebleLevel * 0.4)          // Enhanced blue with treble boost
  );

  return col * 0.9; // Bright and fully visible
}

//----------------------------------------------------------
// Patriotic Twisted Cylinder - Enhanced background effect
//----------------------------------------------------------
#define NUM_FACES 4
#define IN_RADIUS 0.25
#define OUT_RADIUS 0.70
#define CYLINDER_SCROLL_SPEED -0.9
#define COLOR_1 0.8, 0.1, 0.1  // Red
#define COLOR_2 0.1, 0.1, 0.8  // Blue
#define COLOR_3 0.9, 0.9, 0.9  // White

vec4 patrioticSlice(float x0, float x1, vec2 uv)
{
    float u = (uv.x - x0)/(x1 - x0);
    float w = (x1 - x0);
    vec3 col = vec3(0);

    // Red, White, Blue gradient with patriotic transitions and audio reactivity
    float cycle = sin(u * 3.14159 * 2.0 + time * 0.5 + bassLevel * 2.0) * 0.5 + 0.5;
    if (cycle < 0.33) {
        col = mix(vec3(COLOR_1), vec3(COLOR_3), cycle * 3.0);
    } else if (cycle < 0.66) {
        col = mix(vec3(COLOR_3), vec3(COLOR_2), (cycle - 0.33) * 3.0);
    } else {
        col = mix(vec3(COLOR_2), vec3(COLOR_1), (cycle - 0.66) * 3.0);
    }

    // Audio-reactive lighting enhancement
    col *= (w / sqrt(2.0 * IN_RADIUS * IN_RADIUS * (1.0 - cos(6.28318 / float(NUM_FACES))))) * (1.0 + audioIntensity * 0.3);

    // Edges with audio-reactive softness
    col *= smoothstep(0.05, 0.10, u) * smoothstep(0.95, 0.90, u) + 0.5;

    // Checker board pattern with audio-reactive scrolling
    uv.y += time * (CYLINDER_SCROLL_SPEED + midLevel * 0.5);

    // Anti-aliased checker pattern with treble reactivity
    col *= (-1.0 + 2.0 * smoothstep(-0.03, 0.03, sin(u * 3.14159 * 4.0) * cos(uv.y * (16.0 + trebleLevel * 8.0)))) * (1.0/16.0) + 0.7;

    float clip = 0.0;
    float aaSize = 2.0 / 1080.0; // Approximate anti-aliasing
    clip = (1.0 - smoothstep(0.5 - aaSize/w, 0.5 + aaSize/w, abs(u - 0.5))) * step(x0, x1);

    return vec4(col, clip);
}

vec3 PatrioticCylinder()
{
    vec2 res = vec2(1.0, 1.0); // Normalized resolution
    vec2 uv = pos * 2.0 - 1.0; // Convert pos to centered coordinates

    // Polar coordinates
    vec2 uvr = vec2(length(uv), atan(uv.y, uv.x) + 3.14159);
    uvr.x -= OUT_RADIUS;

    vec3 col = vec3(0.05, 0.05, 0.15); // Dark blue background

    // Twisting angle with audio-reactive patriotic motion
    float angle = uvr.y + 2.0 * time + sin(uvr.y * 2.0 + bassLevel * 3.0) * sin(time * 0.7 + midLevel * 2.0) * 3.14159;

    for(int i = 0; i < NUM_FACES; i++)
    {
        float x0 = IN_RADIUS * sin(angle + 6.28318 * (float(i) / float(NUM_FACES)));
        float x1 = IN_RADIUS * sin(angle + 6.28318 * (float(i + 1) / float(NUM_FACES)));

        vec4 face = patrioticSlice(x0, x1, uvr);

        col = mix(col, face.rgb, face.a);
    }

    return col;
}

//----------------------------------------------------------
// RubberCube - Twisted cube with patriotic bars background
// No audio effects - pure visual demo
//----------------------------------------------------------
vec3 cubevec;

// Patriotic sinus bars function
vec3 calcSine(vec2 uv, float frequency, float amplitude, float shift, float offset, vec3 color, float width, float exponent)
{
    float y = sin(time * frequency + shift + uv.x) * amplitude + offset;
    float d = distance(y, uv.y);
    float scale = smoothstep(width, 0.0, distance(y, uv.y));
    return color * scale;
}

// Render patriotic bars background
vec3 PatrioticBars(vec2 f)
{
    vec2 uv = f;
    vec3 color = vec3(0.0);
    // Red, White, Blue bars with patriotic timing
    color += calcSine(uv, 2.0, 0.25, 0.0, 0.5, vec3(0.9, 0.1, 0.1), 0.12, 3.0);      // Red
    color += calcSine(uv, 2.6, 0.15, 0.2, 0.5, vec3(0.9, 0.9, 0.9), 0.1, 1.0);       // White
    color += calcSine(uv, 0.9, 0.35, 0.4, 0.5, vec3(0.1, 0.1, 0.9), 0.1, 1.0);       // Blue
    return color;
}

// Twist function
vec3 Twist(vec3 p)
{
    float f = sin(time/3.0) * 1.45;
    float c = cos(f * p.y);
    float s = sin(f/2.0 * p.y);
    mat2 m = mat2(c, -s, s, c);
    return vec3(m * p.xz, p.y);
}

// Distance function for twisted cube
float CubeDistance(vec3 p)
{
    p = Twist(p);
    cubevec.x = sin(time);
    cubevec.y = cos(time);
    mat2 m = mat2(cubevec.y, -cubevec.x, cubevec.x, cubevec.y);
    p.xy *= m; p.xy *= m; p.yz *= m; p.zx *= m; p.zx *= m; p.zx *= m;
    cubevec = p;
    return length(max(abs(p) - vec3(0.4), 0.0)) - 0.08;
}

// Face pattern function
float FacePattern(vec2 uv)
{
    uv.y = mod(uv.y, 1.0);
    return ((uv.y < uv.x) != (1.0 - uv.y < uv.x)) ? 1.0 : 0.0;
}

// Normal calculation
vec3 getCubeNormal(in vec3 p)
{
    vec2 e = vec2(0.005, -0.005);
    return normalize(
        e.xyy * CubeDistance(p + e.xyy) +
        e.yyx * CubeDistance(p + e.yyx) +
        e.yxy * CubeDistance(p + e.yxy) +
        e.xxx * CubeDistance(p + e.xxx));
}

vec3 RubberCube()
{
    vec2 fragCoord = pos * iResolution.xy;
    float Step = 1.0;
    float Distance = 0.0;
    float Near = -1.0;
    float Far = -1.0;
    vec3 lightPos = vec3(1.5, 0, 0);
    vec2 kp = pos;
    vec2 p = -1.0 + 2.0 * kp;
    float hd = -1.0;
    float ay = max(0.1, 0.5 - time/6.0);

    // Raymarching
    p.x *= iResolution.x / iResolution.y;
    vec3 ro = vec3(0.0, 0.0, 2.1);
    vec3 rd = normalize(vec3(p, -2.0));

    for(int i = 0; i < 256; i++)
    {
        Step = CubeDistance(ro + rd * Distance);
        Distance += Step * 0.5;

        if(Distance > 4.0) break;
        if(Step < 0.001)
        {
            Far = FacePattern(cubevec.yx) + FacePattern(-cubevec.yx) + FacePattern(cubevec.xz) + FacePattern(-cubevec.xz) + FacePattern(cubevec.zy) + FacePattern(-cubevec.zy);
            if(hd < 0.0) hd = Distance;
            if(Near < 0.0) Near = Far;
            Distance += 0.05;
        }
    }

    // Background with patriotic bars
    vec3 Color = PatrioticBars(fragCoord / iResolution.xy);

    // Cube rendering with patriotic colors
    if(Near > 0.0)
    {
        vec3 sp = ro + rd * hd;
        vec3 ld = lightPos - sp;
        float lDist = max(length(ld), 0.001);
        ld /= lDist;
        float atten = 1.0 / (1.0 + lDist * 0.2 + lDist * 0.1);
        float ambience = 0.7;
        vec3 sn = getCubeNormal(sp);
        float diff = min(0.3, max(dot(sn, ld), 0.0));
        float spec = pow(max(dot(reflect(-ld, sn), -rd), 0.0), 32.0);

        // Patriotic cube colors: deep blue to bright white
        Color = Color/5.0 + mix(vec3(0.1, 0.1, 0.8), vec3(1.0, 1.0, 1.0), vec3((Near * 0.45 + Far * Far * 0.04)));

        // Patriotic lighting with red/white/blue tint
        Color = Color * (diff + ambience) + vec3(0.9, 0.7, 1.0) * spec / 1.5;
    }

    // Dark blue zones (patriotic navy) - NO rainbow lines as requested
    if(kp.y < ay || kp.y > 1.0 - ay + 0.006) Color = vec3(0.05, 0.05, 0.25);

    return Color;
}

//----------------------------------------------------------
// Boing - Classic Amiga bouncing ball with checkered pattern
//----------------------------------------------------------
vec3 Boing()
{
    vec2 resolution = iResolution.xy;
    vec2 uv = pos * resolution.y / resolution.y;
    vec2 aspect = resolution / resolution.y;

    // Animation parameters
    vec2 k = vec2(5.0, 5.2);
    float angle = 0.3046;
    float cosA = cos(angle);
    float sinA = sin(angle);
    float center = 0.5;

    // Animated position
    vec2 p = 2.0 * mod(vec2(time), k) / k;
    p = min(p, 2.0 - p);
    p.y *= p.y;
    p = (aspect - center) * p + center * center;

    // Transform coordinates
    vec2 h = (p - vec2(uv.x, 1.0 - uv.y)) * 4.0;
    vec2 m = mat2(cosA, -sinA, sinA, cosA) * h;
    float dist = length(h);

    vec3 color = vec3(0.0); // Default background

    if (dist <= 1.0) {
        // Inside circle - create pattern
        float intensity = 1.5 - dist;
        float pattern = mod(
            floor(2.0 * (5.0 * p.x + m.x / sqrt(1.0 - m.y * m.y))) +
            floor(1.8 * m.y),
            2.0
        );

        if (pattern < center) {
            // White squares
            color = vec3(1.0) * intensity;
        } else {
            // Red squares (classic Amiga Boing Ball colors)
            color = vec3(1.0, 0.0, 0.0) * intensity;
        }
    }

    return color;
}

//----------------------------------------------------------
// Demo mode selection with user controls and auto-switching
//----------------------------------------------------------
#define BACK_DEMOS 4.
#define MAIN_DEMOS 6.

int getDemoMode() {
  if (demoMode >= 1.0 && demoMode <= 4.0) {
    return int(demoMode);  // Manual selection 1-4
  }
  else if (demoMode >= 5.0) {
    // Option 5: Random switching every 5 seconds
    float switchTime = 5.0;
    return int(mod(floor(time / switchTime), MAIN_DEMOS)) + 1;
  }
  // Auto mode (0.0) with user-controlled speed
  float switchTime = 5.0 / autoSwitchSpeed;
  return int(mod(floor(time / switchTime), MAIN_DEMOS)) + 1;
}

int getBackgroundMode() {
  if (backgroundMode >= 1.0 && backgroundMode <= 4.0) {
    return int(backgroundMode);  // Manual selection
  }
  // Auto mode with slightly different timing
  float switchTime = 6.0 / autoSwitchSpeed;
  return int(mod(floor(time / switchTime), BACK_DEMOS)) + 1;
}

vec3 frameDrawing()   // frame and background drawing
{
  float rep = 128.;
  float df = gl_FragCoord.x / rep + time * 5.0;
  if (pos.y < 0.5) df *= -1.0;
  vec3 color = vec3(0.5 + 0.5 * sin(df + 3.1415 + beatLevel)
                   ,0.5 + 0.5 * cos(df + midLevel)
                   ,0.5 + 0.5 * sin(df + trebleLevel));
  if (pos.y > 0.945 && pos.y<0.95)  return color;
  if (pos.y > 0.05  && pos.y<0.055) return color;
  if (pos.y < 0.05  || pos.y>0.95)  return vec3 (0.0, 0.15, 0.25);

  int backDemo = getBackgroundMode();
  if      (backDemo == 1) return vec3(0);
  else if (backDemo == 2) return vec3(0.1); // Simplified starfield
  else if (backDemo == 3) return Plasma();
  else if (backDemo == 4) return PatrioticCylinder();
  return vec3(0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
  vec2 fc = vec2(fragCoord.x, iResolution.y - fragCoord.y);
  time = iTime;
  bassLevel = audioBand(20.0, 250.0);
  midLevel = audioBand(250.0, 4000.0);
  trebleLevel = audioBand(4000.0, 16000.0);
  beatLevel = audioBeatEnergy();
  kickLevel = audioBand(20.0, 80.0);
  audioIntensity = audioRMS();
  mousePressed = (use3DLighting > 0.5);
  pos = fc.xy / iResolution.xy;
  uv = pos * 2.0 - 1.0;
  aspect = iResolution.xy / iResolution.y;

  int mainDemo = getDemoMode();
  aColor = frameDrawing();

  if      (mainDemo == 1) aColor += RGB_Bars();
  else if (mainDemo == 2) aColor += Copper();
  else if (mainDemo == 3) aColor += Plasma(); // Full brightness patriotic plasma
  else if (mainDemo == 4) aColor += vec3(bassLevel, midLevel, trebleLevel) * 0.3;
  else if (mainDemo == 5) aColor += RubberCube(); // Twisted cube with patriotic bars - no audio
  else if (mainDemo == 6) aColor += Boing(); // Classic Amiga bouncing ball

  aColor = ScrollText1();
  aColor = ScrollText2();

  fragColor = vec4(aColor, 1.0);
}
