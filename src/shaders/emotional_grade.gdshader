// Sunshift — full-screen emotional colour grade.
//
// Applied to a ColorRect that covers the whole 480x270 viewport, on the
// topmost CanvasLayer. Reads the frame with a screen-texture sampler.
//
// Compatibility renderer: screen textures have no mip chain there, so the
// bloom is a fixed 9-tap ring of pixel-offset fetches with nearest filtering
// instead of textureLod(). Nearest filtering also keeps the halo on the
// pixel lattice, which is what pixel art wants.
//
// Blacks: every grade term is a multiply (or a highlight-weighted bloom that
// is zero at luma 0), so pure black stays pure black at warmth_factor == 0.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

uniform float warmth_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 shadow_cool = vec3(0.101, 0.137, 0.227);
uniform vec3 shadow_warm = vec3(0.231, 0.149, 0.220);
uniform vec3 highlight_cool = vec3(0.580, 0.639, 0.721);
uniform vec3 highlight_warm = vec3(1.0, 0.820, 0.502);
uniform float bloom_strength : hint_range(0.0, 2.0) = 0.35;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// Bright-pass weighted sample: dark pixels contribute nothing to the bloom.
vec3 bright_tap(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	return c * smoothstep(0.60, 0.95, dot(c, LUMA));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 src = texture(screen_tex, uv);
	vec3 base = src.rgb;
	float luma = dot(base, LUMA);
	float warmth = clamp(warmth_factor, 0.0, 1.0);

	// Shadow tint. Normalised by its own luma so it tints rather than darkens;
	// a multiply can never lift black off zero.
	vec3 shadow_tint = mix(shadow_cool, shadow_warm, warmth);
	shadow_tint /= max(dot(shadow_tint, LUMA), 0.001);
	float shadow_mask = (1.0 - smoothstep(0.03, 0.55, luma)) * 0.85;

	// Highlight tint, weighted so it only reaches pixels that already carry light.
	vec3 high_tint = mix(highlight_cool, highlight_warm, warmth);
	high_tint /= max(dot(high_tint, LUMA), 0.001);
	float high_mask = smoothstep(0.22, 0.80, luma) * 0.75;

	vec3 col = base;
	col *= mix(vec3(1.0), shadow_tint, shadow_mask);
	col *= mix(vec3(1.0), high_tint, high_mask);
	col *= mix(vec3(1.0), vec3(1.05, 1.0, 0.92), warmth);

	// Bloom: centre plus a 1px cross and a 3px diagonal ring.
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 bloom = bright_tap(uv) * 0.20;
	bloom += (bright_tap(uv + vec2(px.x, 0.0)) + bright_tap(uv - vec2(px.x, 0.0))
		+ bright_tap(uv + vec2(0.0, px.y)) + bright_tap(uv - vec2(0.0, px.y))) * 0.12;
	vec2 far = px * 3.0;
	bloom += (bright_tap(uv + far) + bright_tap(uv - far)
		+ bright_tap(uv + vec2(far.x, -far.y)) + bright_tap(uv - vec2(far.x, -far.y))) * 0.08;
	vec3 bloom_tint = mix(vec3(0.65, 0.78, 1.0), vec3(1.0, 0.80, 0.48), warmth);
	col += bloom * bloom_tint * bloom_strength;

	// Vignette. Cools and deepens at twilight, warms and settles at golden hour.
	vec2 vc = (uv - vec2(0.5, 0.52)) * vec2(1.0, 1.25);
	float vig = smoothstep(0.30, 0.80, length(vc));
	vec3 vig_tint = mix(vec3(0.62, 0.72, 1.0), vec3(1.0, 0.66, 0.36), warmth);
	col *= mix(vec3(1.0), vig_tint, vig * vignette_strength * (0.8 + 0.4 * warmth));

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), src.a);
}
