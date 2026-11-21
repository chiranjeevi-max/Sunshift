// Sunshift — volumetric light shafts.
//
// Apply to a quad / Polygon2D whose UV spans 0..1 across the shaft (u, u=0 and
// u=1 are the long edges) and 0..1 along it (v). Additive blending is baked in
// because these are light shafts over dark geometry; alpha carries the
// intensity profile, so beam_strength is the single lighting knob.
//
// Everything internal is quantised to the 480x270 pixel lattice (pixel_size is
// one pixel in UV, and canvas units are screen pixels at 1:1), so the shaft
// structure and the dust motes never smear across sub-pixels.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 beam_color : source_color = vec4(1.0, 0.820, 0.510, 0.850);
uniform float beam_strength : hint_range(0.0, 3.0) = 1.0;
uniform float time_scale = 1.0;
uniform float pixel_size = 0.0037037037; // 1.0 / 270.0 (defaults must be literals)
uniform float feather = 0.15;

const float REFERENCE_HEIGHT = 270.0;
const float TWO_PI = 6.2831853;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float unit = max(pixel_size * REFERENCE_HEIGHT, 0.0001);
	vec2 wp = floor(VERTEX.xy / unit) * unit;
	float t = TIME * time_scale;

	// Cross-section: soft feathered sides, gentler fade along the shaft ends.
	float u = clamp(UV.x, 0.0, 1.0);
	float v = clamp(UV.y, 0.0, 1.0);
	float across = min(u, 1.0 - u) * 2.0;
	float edge = max(feather, 0.001);
	float body = smoothstep(0.0, edge, across);
	float ends = smoothstep(0.0, edge * 0.6, v) * smoothstep(0.0, edge * 1.4, 1.0 - v);
	float core = body * ends;

	// Diagonal sub-shafts. wp is already whole pixels, so slat is piecewise
	// constant per pixel and the bands break on the lattice, never between it.
	float diag = wp.x * 0.62 + wp.y;
	float slat = 0.5 + 0.5 * sin(diag * (TWO_PI / 28.0) + t * 0.35);
	slat = smoothstep(0.30, 0.70, slat);

	// Dust motes drift up the shaft, one candidate per 3x3 pixel cell.
	vec2 drift = vec2(0.35, -0.80) * t * 7.0;
	vec2 cell = floor((wp + drift) / (unit * 3.0));
	float h = hash21(cell);
	float twinkle = 0.5 + 0.5 * sin(t * (1.2 + h * 2.4) + h * 40.0);
	float mote = step(0.90, h) * smoothstep(0.35, 0.90, twinkle) * body;

	float intensity = core * (0.50 + 0.50 * slat);
	float alpha = beam_color.a * beam_strength * (intensity + mote * 0.90);

	vec3 rgb = beam_color.rgb * (0.82 + 0.30 * slat);
	rgb = mix(rgb, vec3(1.0, 0.97, 0.88), mote * 0.85);
	COLOR = vec4(rgb, clamp(alpha, 0.0, 1.0));
}
