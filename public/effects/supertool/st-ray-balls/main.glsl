// Imported from SuperTool effects/RayBalls.glsl by scripts/import-supertool.mjs
// SuperTool intake note: ported from DISCO-GLSL-Video-Processor (Shaders/RayBalls.glsl).
// #version / standard uniform / in-out decls dropped (GLSLRenderer injects them).
// iChannel0 = the layer-below video, camera-locked (billboard) onto an orbiting
// ray-traced ball among reflective spheres on a checker floor. SuperTool's
// gl_FragCoord is already upright, so no Y-flip is applied. Not audio-reactive.



// Simple user controls (non-audio-reactive)
uniform float ballSpeed;        // Speed of video ball animation
uniform float ballSize;         // Size multiplier for video ball
uniform float videoReflectivity; // Controls video ball reflectivity (0.0-1.0)


// Original ray tracing structures (simplified)
struct Ray {
    vec3 origin;
    vec3 direction;
};

struct Light {
    vec3 color;
    vec3 direction;
};

struct Material {
    vec3 color;
    float diffuse;
    float specular;
    bool isVideoBall;
};

struct Intersect {
    float len;
    vec3 normal;
    Material material;
};

struct Sphere {
    float radius;
    vec3 position;
    Material material;
};

struct Plane {
    vec3 normal;
    Material material;
};

const float epsilon = 0.001;
const int iterations = 6;
const float exposure = 0.08;  // brightened — Shadertoy-tuned lighting
const float gamma = 1.2;
const float intensity = 7.0;
const vec3 ambient = vec3(0.6, 0.8, 1.0) * intensity / gamma;

Light light;
Intersect miss = Intersect(0.0, vec3(0.0), Material(vec3(0.0), 0.0, 0.0, false));

// Continuous orbit animation - no entry/exit phases
vec3 getVideoBallPosition(float time) {
    float animTime = time * ballSpeed;

    // Dynamic orbit radius that scales with ball size to prevent collisions
    float videoBallRadius = 3.0 * ballSize;

    // Base orbit radius (8.0) + extra clearance based on ball size
    // At ballSize=1.0: orbit radius = 8.0 (perfect for default)
    // At ballSize=2.0: orbit radius = 11.0 (3.0 extra clearance)
    float orbitRadius = 8.0 + (videoBallRadius - 3.0);

    // Continuous orbit - radius and height scale with ball size
    float angle = animTime * 0.5; // Orbit speed
    float x = cos(angle) * orbitRadius;
    float z = sin(angle) * orbitRadius;

    // Y position scales with ball size to maintain clearance above other spheres
    // Base Y=6.0 for ballSize=1.0, higher for larger balls
    float y = 6.0 + (videoBallRadius - 3.0) * 1.0; // Height increases 1:1 with radius growth

    return vec3(x, y, z);
}

float getVideoBallSize(float time) {
    // Constant size - no growing/shrinking animation
    return 3.0 * ballSize;
}

Intersect intersect(Ray ray, Sphere sphere) {
    vec3 oc = sphere.position - ray.origin;
    float l = dot(ray.direction, oc);
    float det = pow(l, 2.0) - dot(oc, oc) + pow(sphere.radius, 2.0);
    if (det < 0.0) return miss;

    float len = l - sqrt(det);
    if (len < 0.0) len = l + sqrt(det);
    if (len < 0.0) return miss;

    vec3 norm = (ray.origin + len * ray.direction - sphere.position) / sphere.radius;
    return Intersect(len, norm, sphere.material);
}

Intersect intersect(Ray ray, Plane plane) {
    float len = -dot(ray.origin, plane.normal) / dot(ray.direction, plane.normal);
    if (len < 0.0) return miss;

    vec3 hitp = ray.origin + ray.direction * len;
    float m = mod(hitp.x, 2.0);
    float n = mod(hitp.z, 2.0);
    float d = 1.0;
    if ((m > 1.0 && n > 1.0) || (m < 1.0 && n < 1.0)) {
        d *= 0.5;
    }

    plane.material.color *= d;
    return Intersect(len, plane.normal, plane.material);
}

// Get current camera position for camera-locked texture calculations
vec3 getCurrentCameraPos() {
    // Use same dynamic camera distance calculation as main()
    float maxVideoBallRadius = 3.0 * ballSize;
    float maxOrbitRadius = 8.0 + (maxVideoBallRadius - 3.0);
    float maxExtent = maxOrbitRadius + maxVideoBallRadius;
    float radius = max(18.0, maxExtent * 1.3);

    float camX = radius * sin(iTime * 0.2);
    float camZ = radius * cos(iTime * 0.2);
    return vec3(camX, 2.5, camZ);
}

Intersect trace(Ray ray) {
    // Original spheres exactly as in the original
    Sphere sphere0 = Sphere(2.0, vec3(-3.0 - sin(iTime), 3.0 + sin(iTime), 0), Material(vec3(1.0, 0.0, 0.0), 0.05, 0.01, false));
    Sphere sphere1 = Sphere(3.0, vec3(3.0 + cos(iTime), 3.0, 0), Material(vec3(0.0, 0.0, 1.0), 0.05, 0.01, false));
    Sphere sphere2 = Sphere(1.0, vec3(0.5, 1.0, 6.0), Material(vec3(1.0, 1.0, 1.0), 0.001, 0.1, false));

    // Video ball with higher orbit - non-reflective material for clear video visibility
    vec3 videoBallPos = getVideoBallPosition(iTime);
    float videoBallRadius = getVideoBallSize(iTime);
    // Video ball material with user-controllable reflectivity
    Sphere videoBall = Sphere(videoBallRadius, videoBallPos, Material(vec3(1.0, 1.0, 1.0), 1.0, videoReflectivity, true));

    Intersect closest = intersect(ray, Plane(vec3(0, 1, 0), Material(vec3(1.0, 1.0, 1.0), 0.4, 0.9, false)));

    // Check each sphere individually like the original
    Intersect hit0 = intersect(ray, sphere0);
    if ((hit0.material.diffuse > 0.0 || hit0.material.specular > 0.0) &&
        (closest.material.diffuse <= 0.0 && closest.material.specular <= 0.0 || hit0.len < closest.len)) {
        closest = hit0;
    }

    Intersect hit1 = intersect(ray, sphere1);
    if ((hit1.material.diffuse > 0.0 || hit1.material.specular > 0.0) &&
        (closest.material.diffuse <= 0.0 && closest.material.specular <= 0.0 || hit1.len < closest.len)) {
        closest = hit1;
    }

    Intersect hit2 = intersect(ray, sphere2);
    if ((hit2.material.diffuse > 0.0 || hit2.material.specular > 0.0) &&
        (closest.material.diffuse <= 0.0 && closest.material.specular <= 0.0 || hit2.len < closest.len)) {
        closest = hit2;
    }

    // Check video ball and apply camera-locked texture
    Intersect hitVideo = intersect(ray, videoBall);
    if ((hitVideo.material.diffuse > 0.0 || hitVideo.material.specular > 0.0) &&
        (closest.material.diffuse <= 0.0 && closest.material.specular <= 0.0 || hitVideo.len < closest.len)) {
        closest = hitVideo;

        // CAMERA-LOCKED VIDEO TEXTURE (Billboard Style)
        vec3 hitPoint = ray.origin + hitVideo.len * ray.direction;
        vec3 cameraPos = getCurrentCameraPos();
        vec3 toCamera = normalize(cameraPos - videoBallPos);

        // Create camera-facing coordinate system
        vec3 up = vec3(0.0, 1.0, 0.0);
        vec3 right = normalize(cross(up, toCamera));
        vec3 forward = toCamera;
        up = cross(forward, right); // Recompute up to ensure orthogonality

        // Get surface point relative to ball center
        vec3 localPoint = hitPoint - videoBallPos;

        // Project onto camera-facing plane
        float u = 0.5 + dot(localPoint, right) / (videoBallRadius * 2.0);
        float v = 0.5 + dot(localPoint, up) / (videoBallRadius * 2.0);  // SuperTool video is upright (DISCO Flip-V removed)

        // Clamp UV coordinates to valid range
        u = clamp(u, 0.0, 1.0);
        v = clamp(v, 0.0, 1.0);

        // Sample video texture with camera-locked coordinates
        vec3 videoColor = texture(iChannel0, vec2(u, v)).rgb;

        // Ensure video is visible - add fallback for debugging
        if (length(videoColor) < 0.01) {
            // Fallback: bright magenta to indicate texture sampling issue
            videoColor = vec3(1.0, 0.0, 1.0);
        }

        closest.material.color = videoColor;
    }

    return closest;
}

vec3 radiance(Ray ray) {
    vec3 color = vec3(0.);
    vec3 fresnel = vec3(1.0);
    vec3 mask = vec3(1.0);
    Intersect hit;
    vec3 reflection;
    vec3 spotLight;

    for (int i = 0; i <= iterations; ++i) {
        hit = trace(ray);
        if (hit.material.diffuse > 0.0 || hit.material.specular > 0.0) {
            vec3 r0 = hit.material.color.rgb + hit.material.specular;
            float hv = clamp(dot(hit.normal, -ray.direction), 0.0, 1.0);
            fresnel = r0 + (1.0 - r0) * pow(1.0 - hv, 5.0);

            // ENHANCED LIGHTING FOR VIDEO BALL (no shadow check)
            if (hit.material.isVideoBall) {
                // Video ball gets enhanced lighting without shadow calculation
                float lightDot = max(0.5, dot(hit.normal, light.direction));
                color += lightDot * light.color * hit.material.color.rgb * hit.material.diffuse * (1.0 - fresnel) * mask;
                // Add extra ambient for video visibility
                color += hit.material.color.rgb * ambient * 0.3 * mask;
            } else {
                // ORIGINAL SHADOW CALCULATION FOR NON-VIDEO OBJECTS
                if (trace(Ray(ray.origin + hit.len * ray.direction + epsilon * light.direction, light.direction)).material.diffuse == 0.0) {
                    color += clamp(dot(hit.normal, light.direction), 0.0, 1.0) * light.color
                           * hit.material.color.rgb * hit.material.diffuse
                           * (1.0 - fresnel) * mask;
                }
                // Ambient fill: non-video objects (checker floor, the matte
                // spheres) were lit ONLY by the direct shadowed diffuse term —
                // the video ball alone got an ambient term, so everything else
                // read near-black. Give them the same sky-ambient fill light.
                color += hit.material.color.rgb * ambient * 0.3 * mask;
            }

            mask *= fresnel;
            reflection = reflect(ray.direction, hit.normal);
            ray = Ray(ray.origin + hit.len * ray.direction + epsilon * reflection, reflection);
        } else {
            // Sharp black horizon - only add spotlight if looking directly at sun
            spotLight = vec3(1e6) * pow(abs(dot(ray.direction, light.direction)), 250.0);

	    // Bad inject here:
            // Balanced ambient for black horizon while maintaining scene brightness
            // vec3 backgroundAmbient = ambient * 0.15;  // Slightly higher for better overall brightness
            // color += mask * (backgroundAmbient + spotLight);
	    color *= mask * (ambient + spotLight);
            break;
        }
    }
    return color;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // SuperTool gl_FragCoord is already upright — no Y-flip (was rendering upside-down).
    vec2 fc = fragCoord;
    light.color = vec3(1.0) * intensity;
    // 1:30 PM sun position - high but slightly angled from southwest
    light.direction = normalize(vec3(-2.5, 8.0, 3.0));

    // Use original coordinate system like the original shader
    vec2 uv = fc / iResolution.xy - vec2(0.5);
    uv.x *= iResolution.x / iResolution.y;

    // Dynamic camera distance to accommodate variable ball sizes
    // Calculate max extent of video ball (orbit + ball radius)
    float maxVideoBallRadius = 3.0 * ballSize;
    float maxOrbitRadius = 8.0 + (maxVideoBallRadius - 3.0);
    float maxExtent = maxOrbitRadius + maxVideoBallRadius;

    // Camera distance = max extent * 1.3 for comfortable viewing (minimum 18.0)
    float radius = max(18.0, maxExtent * 1.3);
    float camX = radius * sin(iTime * 0.2);
    float camZ = radius * cos(iTime * 0.2);
    vec3 camPos = vec3(camX, 2.5, camZ);
    vec3 target = vec3(0.0, 2.5, 0.0);
    vec3 forward = normalize(target - camPos);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 up = cross(forward, right);
    vec3 rayDir = normalize(uv.x * right + uv.y * up + forward);
    Ray ray = Ray(camPos, rayDir);
    fragColor = vec4(pow(radiance(ray) * exposure, vec3(1.0 / gamma)), 1.0);
}
