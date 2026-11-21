// Sunshift — journal postcard reveal.
//
// Apply to the postcard Sprite2D/TextureRect. reveal 0 -> 1 sweeps the image in
// radially from seal_center behind a golden wax-seal stamp that grows and then
// settles. Warm paper grain and a soft card vignette sit under the sweep so the
// card reads as a physical keepsake rather than a screenshot.
//
// The seal is sized in texture texels (TEXTURE_PIXEL_SIZE) so it stays round
// and keeps its proportions however the card is scaled in the journal.
shader_type canvas_item;
render_mode unshaded;

uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec2 seal_center = vec2(0.5, 0.85);
uniform float grain_amount : hint_range(0.0, 1.0) = 0.12;
uniform vec3 seal_color : source_color = vec3(0.851, 0.639, 0.243);

const float TWO_PI = 6.2831853;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 modulate = COLOR;
	vec4 texel = texture(TEXTURE, UV);
	vec2 texel_uv = max(TEXTURE_PIXEL_SIZE, vec2(0.0001));

	// Seal space in texels: aspect-correct, so the wax stays a round disc.
	vec2 px = (UV - seal_center) / texel_uv;
	vec2 dir = px + vec2(0.0001, 0.0);
	float r = length(px);
	float angle = atan(dir.y, dir.x);
	float max_r = length(max(seal_center, vec2(1.0) - seal_center) / texel_uv);
	float rr = r / max(max_r, 1.0);

	// --- wax seal ------------------------------------------------------------
	float grow = smoothstep(0.0, 0.72, reveal);
	float seal_radius = 6.0 + 9.0 * grow;
	float lump = 1.0 + 0.055 * sin(angle * 7.0 + 1.3) + 0.035 * sin(angle * 13.0 + 4.1);
	float sr = seal_radius * lump;
	float seal_mask = 1.0 - smoothstep(sr - 1.0, sr + 0.5, r);

	// Pressed details: an inner ring, a raised sun disc and eight rays.
	float inner = smoothstep(sr * 0.62, sr * 0.68, r) * (1.0 - smoothstep(sr * 0.74, sr * 0.80, r));
	float disc = 1.0 - smoothstep(sr * 0.20, sr * 0.25, r);
	float spoke = step(0.5, fract(angle / TWO_PI * 8.0 + 0.5));
	float rays = spoke * smoothstep(sr * 0.30, sr * 0.34, r) * (1.0 - smoothstep(sr * 0.50, sr * 0.55, r));

	float bevel = dot(normalize(dir), vec2(-0.62, -0.78)) * 0.5 + 0.5;
	vec3 wax = seal_color * (0.80 + 0.38 * bevel);
	wax = mix(wax, wax * 1.30, disc + rays * 0.55);
	wax = mix(wax, wax * 0.60, inner);
	wax *= mix(1.0, 0.70, smoothstep(sr * 0.85, sr, r));

	// --- radial reveal -------------------------------------------------------
	float front = smoothstep(0.0, 1.0, reveal) * 1.12;
	float sweep = 1.0 - smoothstep(front - 0.09, front, rr);
	// Golden lip riding the leading edge; it is gone by the time reveal hits 1.
	float lip = exp(-pow((rr - front) / 0.055, 2.0)) * (1.0 - smoothstep(0.92, 1.0, reveal));

	// --- paper ---------------------------------------------------------------
	vec3 col = texel.rgb;
	vec2 cell = floor(SCREEN_UV / SCREEN_PIXEL_SIZE);
	float g1 = hash21(cell) - 0.5;
	float g2 = hash21(cell * 1.37 + 19.0) - 0.5;
	col *= mix(vec3(1.0), vec3(1.05, 1.00, 0.91), 0.55);
	col *= 1.0 + (g1 * 0.6 + g2 * 0.4) * grain_amount * 0.55;
	vec2 q = abs(UV - 0.5) * 2.0;
	col *= mix(1.0, 0.82, smoothstep(0.70, 1.0, max(q.x, q.y)) * 0.5);

	col += vec3(1.0, 0.78, 0.36) * lip * 0.55;
	col = mix(col, wax, seal_mask);

	float alpha = max(sweep * texel.a, max(seal_mask, lip * 0.85));
	COLOR = vec4(col * modulate.rgb, clamp(alpha, 0.0, 1.0) * modulate.a);
}
