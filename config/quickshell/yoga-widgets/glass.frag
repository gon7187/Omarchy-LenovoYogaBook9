// Liquid-glass edge for the widget cards.
//
// A layer surface cannot read the pixels behind it, but these cards sit on the
// background layer, so what is behind them is always the wallpaper — which we
// can sample directly. `src` is the wallpaper drawn at screen size; uvOffset
// and uvScale carry the card's place in it, so the sampled pixels line up with
// what Hyprland is painting underneath.
//
// The edge of a thick glass slab bends light: the closer to the rim, the
// stronger the bend, and the three channels bend by slightly different amounts.
// That refraction plus a normal-dependent rim highlight and a slow travelling
// sheen is what reads as glass.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // card size, px
    vec2 uvOffset;    // card origin inside the wallpaper texture
    vec2 uvScale;     // card size inside the wallpaper texture
    float radius;     // corner radius, px
    float edge;       // how far in from the rim the lens reaches, px
    float strength;   // peak refraction, px
    float phase;      // 0..1, drives the travelling sheen
    float sheen;      // sheen amount
    float rainbow;    // iridescence amount
};

layout(binding = 1) uniform sampler2D src;

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 halfSize = size * 0.5;
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    float d = sdRoundBox(p, halfSize, radius);

    // Outside the rounded rectangle nothing is drawn; the 1px band is the
    // antialiased border.
    float inside = 1.0 - smoothstep(-1.0, 0.0, d);
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }

    // Surface normal from the distance field: points out of the nearest edge.
    vec2 h = vec2(1.0, 0.0);
    vec2 grad = vec2(sdRoundBox(p + h.xy, halfSize, radius) - sdRoundBox(p - h.xy, halfSize, radius),
                     sdRoundBox(p + h.yx, halfSize, radius) - sdRoundBox(p - h.yx, halfSize, radius));
    vec2 n = normalize(grad + vec2(1e-6));

    // 1 at the rim, 0 once `edge` px inside.
    float lens = pow(clamp(1.0 + d / edge, 0.0, 1.0), 2.2);

    vec2 push = n * (strength * lens) / size * uvScale;
    vec2 uv = uvOffset + qt_TexCoord0 * uvScale;
    vec3 col = vec3(texture(src, uv - push * 1.08).r,
                    texture(src, uv - push).g,
                    texture(src, uv - push * 0.92).b);

    // Rim light: bright where the edge faces the top-left, as if lit from there.
    vec2 lightDir = normalize(vec2(-0.55, -0.83));
    float facing = clamp(dot(n, lightDir), 0.0, 1.0);
    float rim = lens * lens * facing;

    // Iridescence: the bent edge splits the rim light into a soft spectrum.
    float a = atan(n.y, n.x);
    vec3 tint = 0.5 + 0.5 * cos(vec3(0.0, 2.094, 4.188) + a * 1.7 + phase * 6.283);
    col += rainbow * lens * (tint - 0.5);
    col += rim * 0.24;

    // Travelling sheen: a soft diagonal band crossing the card.
    float band = (qt_TexCoord0.x + qt_TexCoord0.y) * 0.5;
    float pos = fract(phase);
    float dist = abs(fract(band - pos + 0.5) - 0.5);
    col += sheen * smoothstep(0.22, 0.0, dist) * (0.55 + 0.45 * lens);

    // The lens is only visible near the rim; the middle stays clear so the
    // Hyprland blur below shows through.
    float glow = sheen * smoothstep(0.22, 0.0, dist);
    float alpha = inside * clamp(lens * 0.34 + rim * 0.18 + glow, 0.0, 1.0);
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
