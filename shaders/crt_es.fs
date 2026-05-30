#version 100
// Web (GLSL ES 100) variant of the CRT / neon-glow post-process.
precision mediump float;

varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 u_resolution;

void main() {
    vec2 uv = fragTexCoord;
    vec2 texel = 1.0 / u_resolution;

    float ca = 0.6 * texel.x;
    vec3 col;
    col.r = texture2D(texture0, uv + vec2(ca, 0.0)).r;
    col.g = texture2D(texture0, uv).g;
    col.b = texture2D(texture0, uv - vec2(ca, 0.0)).b;

    vec3 b = vec3(0.0);
    b += texture2D(texture0, uv + texel * vec2( 1.5,  1.5)).rgb;
    b += texture2D(texture0, uv + texel * vec2(-1.5,  1.5)).rgb;
    b += texture2D(texture0, uv + texel * vec2( 1.5, -1.5)).rgb;
    b += texture2D(texture0, uv + texel * vec2(-1.5, -1.5)).rgb;
    b *= 0.25;
    float lum = dot(b, vec3(0.299, 0.587, 0.114));
    b *= smoothstep(0.45, 0.9, lum);
    col += b * 0.5;

    float scan = 0.92 + 0.08 * sin(uv.y * u_resolution.y * 3.14159);
    col *= scan;

    vec2 d = uv - 0.5;
    float vig = smoothstep(0.85, 0.35, dot(d, d) * 2.2);
    col *= mix(0.72, 1.0, vig);

    gl_FragColor = vec4(col, 1.0) * fragColor;
}
