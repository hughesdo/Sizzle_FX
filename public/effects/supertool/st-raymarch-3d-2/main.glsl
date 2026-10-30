// Imported from SuperTool effects/3DRaymarching2.glsl by scripts/import-supertool.mjs
// SuperTool intake note: ported from DISCO-GLSL-Video-Processor (Shaders/3DRaymarching2.glsl).
// #version / standard uniform / in-out decls dropped (GLSLRenderer injects them).
// iChannel0 = the layer-below video on a raymarched box with a camera that flies
// in to fill the screen. DISCO correctedUV (v_text.x,1-v_text.y) == SuperTool's
// fragCoord/res, so its fragCoord maps directly to the mainImage param. Not
// audio-reactive; the 8 controls are tunable uniforms.



// User-configurable uniforms for 3D control
uniform float cameraSpeed;      // Speed of camera animation
uniform float rotationAmount;   // Amount of rotation movement
uniform float fovVariation;     // Field of view variation
uniform float colorIntensity;   // Color brightness multiplier
uniform float glowStrength;     // Glow effect strength
uniform float timeSpeed;        // Overall animation speed
uniform float starDensity;      // Star field density
uniform float boxSize;          // Size of the video display box


const float PI = 3.1415926;

// Distance function for a box (from Shadertoy)
float sdBox(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

// Union operation for combining shapes
vec2 opU(vec2 a, vec2 b) {
    return a.x < b.x ? a : b;
}

// Camera setup function
mat3 setCamera(in vec3 ro, in vec3 ta, float cr) {
    vec3 cw = normalize(ta - ro);
    vec3 cp = vec3(sin(cr), cos(cr), 0.0);
    vec3 cu = normalize(cross(cw, cp));
    vec3 cv = cross(cu, cw);
    return mat3(cu, cv, cw);
}

// Easing functions from easings.net
float outPow(float x, float p) {
    x = clamp(x, 0.0, 1.0);
    return 1.0 - pow(1.0 - x, p);
}

float inPow(float x, float p) {
    x = clamp(x, 0.0, 1.0);
    return pow(x, p);
}

float outElastic(float x) {
    const float c4 = (2.0 * PI) / 3.0;
    return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * c4) + 1.0;
}

// Additional smooth easing functions for natural transitions
float easeInOutCubic(float x) {
    x = clamp(x, 0.0, 1.0);
    return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0;
}

float easeOutQuart(float x) {
    x = clamp(x, 0.0, 1.0);
    return 1.0 - pow(1.0 - x, 4.0);
}

// Star field generation
float stars(vec3 p, float t) {
    float d = 9999.9;
    for (float i = 0.0; i < 4.0; i++) {
        vec3 offset = vec3(i * 1.4, i * 1.2, i * -0.5) * starDensity;
        float grid = length(mod(p + offset, 4.0) - 2.0);
        d = min(grid - 0.08, d);
    }
    return d;
}

// Scene mapping function - defines the 3D geometry
vec2 map(vec3 p, float t, float currentBoxSize) {
    // Video display box with dynamic size
    vec2 res = vec2(sdBox(p + vec3(0.0, 0.0, 0.1), vec3(currentBoxSize, currentBoxSize, 0.05)), 1.5);
    // Star field
    res = opU(res, vec2(stars(p, t), 0.5));
    return res;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{

    vec2 uv = fragCoord / iResolution.xy;
    vec2 q = (fragCoord.xy - 0.5 * iResolution.xy) / iResolution.y;

    // Apply time speed multiplier
    float animTime = iTime * timeSpeed;
    float mod2 = mod(animTime, 2.0);
    float mod4 = mod(animTime, 4.0);
    
    // ENHANCED SMOOTH TRANSITION SYSTEM WITH FULL LOOP
    // Total cycle: 10 seconds (1.5s grow + 4.5s hold + 4s original loop)
    float totalCycle = 10.0;
    float cycle = mod(animTime, totalCycle);
    
    // Phase timing
    float growthDuration = 1.5;   // Smooth growth to full screen
    float holdDuration = 4.5;     // Hold full screen for video viewing
    float loopDuration = 4.0;     // Complete original loop with color changes
    
    // Calculate smooth transition factor for close-up
    float transitionFactor = 0.0;
    
    if (cycle <= growthDuration) {
        // Phase 1: Growing to full screen (0.0 to 1.5 seconds)
        float growthProgress = cycle / growthDuration;
        transitionFactor = easeInOutCubic(growthProgress);
    } else if (cycle <= (growthDuration + holdDuration)) {
        // Phase 2: Holding at full screen (1.5 to 6.0 seconds)
        transitionFactor = 1.0;
    } else {
        // Phase 3: Fade back and complete original loop (6.0 to 10.0 seconds)
        float loopProgress = (cycle - growthDuration - holdDuration) / loopDuration;
        // Smooth fade back to normal 3D view
        transitionFactor = 1.0 - easeInOutCubic(loopProgress);
    }

    // Main camera animation with user controls (original 3D movement)
    float xrot = (4.0 - outElastic(0.3 * mod4) * 4.0) * rotationAmount;
    float yrot = (16.0 - outPow(mod4 * 2.0, 3.0) * 16.0 - inPow(mod2 - 1.0, 5.0) * 16.0) * rotationAmount;
    float zrot = mod4 > 2.0
        ? (8.0 - outPow(mod2, 4.0) * 8.0) * rotationAmount
        : sin(animTime * PI) * 0.5 * rotationAmount;

    // Flip motion every 2 iterations
    if (mod(animTime, 8.0) > 4.0) {
        xrot *= -1.0;
        yrot *= -1.0;
        zrot *= -1.0;
    }

    // Apply camera speed and FOV variation
    xrot *= cameraSpeed;
    yrot *= cameraSpeed;
    zrot *= cameraSpeed;

    // Normal 3D camera position and FOV
    float normalFov = (sin(animTime * PI) * fovVariation + 0.7);
    vec3 normalRo = vec3(xrot, yrot, normalFov);
    
    // Close-up camera position and FOV (for full screen video)
    vec3 closeRo = vec3(0.0, 0.0, -0.2);  // Close to the video box
    float closeFov = 0.05;                // Tight field of view for full screen
    
    // SMOOTH INTERPOLATION between normal and close-up camera
    vec3 ro = mix(normalRo, closeRo, transitionFactor);
    float fov = mix(normalFov, closeFov, transitionFactor);
    float cameraRotation = mix(zrot, 0.0, transitionFactor); // Reduce rotation during close-up
    
    // Smooth box size transition - make the video box grow during transition
    float dynamicBoxSize = mix(boxSize, boxSize * 2.0, transitionFactor * 0.5);
    
    // Set up camera with smooth interpolation
    mat3 ca = setCamera(ro, vec3(0.0), cameraRotation);
    vec3 rd = ca * normalize(vec3(q, fov));

    // Raymarching with configurable glow and dynamic box size
    vec2 h; 
    vec3 p;
    float t = 0.1;
    const int iters = 20;
    const float tmax = 22.0;

    for (int i = 0; i < iters && t < tmax; i++) {
        p = ro + rd * t;
        h = map(p, animTime, dynamicBoxSize);
        if (abs(h.x) < 0.001) {
            break;
        }
        t += h.x;
    }
    
    // ORIGINAL COLOR GENERATION WITH FULL LOOP CYCLE
    // This preserves the red/blue background transitions from the original
    vec4 red = vec4(1.0, uv.y, 0.5, 1.0) * colorIntensity;
    vec4 blu = vec4(0.0, uv.y, 1.0, 1.0) * colorIntensity;
    float fog = min(10.0, (2.0 + 6.0 * mod2) * glowStrength) / t;
    vec4 color = (mod4 > 2.0 ? blu : red) * fog;

    if (h.y > 1.0) {
        // Video display on the 3D box
        vec2 size = vec2(textureSize(iChannel0, 0));
        vec2 videoUV = vec2(p.x * size.y / size.x, p.y);
        fragColor = texture(iChannel0, 0.5 + videoUV);
    } else {
        // Background and stars with original color cycling
        fragColor = color;
    }
}
