#version 330
// Subtle CRT / neon-glow post-process for the geometric look:
// chromatic aberration + bright-pass bloom + scanlines + vignette.
// Desktop (GLSL 330) variant. See crt_es.fs for the web (GLSL ES 100) variant.

in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 u_resolution; // game render size (e.g. 480x270)
out vec4 finalColor;

void main() {
    vec2 uv = fragTexCoord;
    vec2 texel = 1.0 / u_resolution;

    // chromatic aberration
    float ca = 0.6 * texel.x;
    vec3 col;
    col.r = texture(texture0, uv + vec2(ca, 0.0)).r;
    col.g = texture(texture0, uv).g;
    col.b = texture(texture0, uv - vec2(ca, 0.0)).b;

    // bright-pass bloom from four diagonal taps
    vec3 b = vec3(0.0);
    b += texture(texture0, uv + texel * vec2( 1.5,  1.5)).rgb;
    b += texture(texture0, uv + texel * vec2(-1.5,  1.5)).rgb;
    b += texture(texture0, uv + texel * vec2( 1.5, -1.5)).rgb;
    b += texture(texture0, uv + texel * vec2(-1.5, -1.5)).rgb;
    b *= 0.25;
    float lum = dot(b, vec3(0.299, 0.587, 0.114));
    b *= smoothstep(0.45, 0.9, lum);
    col += b * 0.5;

    // scanlines (tied to game pixels)
    float scan = 0.92 + 0.08 * sin(uv.y * u_resolution.y * 3.14159);
    col *= scan;

    // vignette
    vec2 d = uv - 0.5;
    float vig = smoothstep(0.85, 0.35, dot(d, d) * 2.2);
    col *= mix(0.72, 1.0, vig);

    finalColor = vec4(col, 1.0) * fragColor;
}
