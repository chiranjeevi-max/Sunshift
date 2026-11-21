// Sunshift — cloth and foliage sway.
//
// Vertex displacement only, so it composes with any sprite or Polygon2D that
// carries UVs. The horizontal offset grows with how far a vertex sits above
// anchor_y (in UV, 0 = top of the art) and is snapped to whole pixels, so the
// silhouette keeps its pixel-art steps. A vertex at or below anchor_y gets
// exactly 0 offset — that is what keeps an awning welded to its rail.
shader_type canvas_item;

uniform float sway_amount = 2.0;
uniform float sway_speed = 1.0;
uniform float anchor_y = 0.7;
uniform bool anchor_top = false;
uniform float pixel_size = 0.0037037037; // 1.0 / 270.0 (defaults must be literals)
uniform float gust = 0.0;

// pixel_size is one screen pixel in UV; local units are screen pixels for art
// drawn 1:1 at 480x270, so 270 * pixel_size is the snap grid in local units.
const float REFERENCE_HEIGHT = 270.0;

void vertex() {
	float anchor = max(anchor_y, 0.0001);
	// anchor_top covers cloth that hangs from a rail: the welded edge is the top
	// of the art and the lift grows downward toward the free hem.
	float lift;
	if (anchor_top) {
		lift = clamp((UV.y - anchor) / max(1.0 - anchor, 0.0001), 0.0, 1.0);
	} else {
		lift = clamp((anchor - UV.y) / anchor, 0.0, 1.0);
	}
	float t = TIME * sway_speed;

	float wave = sin(t * 1.9 + UV.y * 4.0 + UV.x * 2.4) * 0.55
		+ sin(t * 3.7 - UV.y * 2.0 + UV.x * 5.1) * 0.30;
	// gust leans the whole sheet and surges slowly, so it reads even in a still.
	float surge = gust * (0.62 + 0.38 * sin(t * 0.45 + UV.x * 1.3 + 1.1));

	float snap = max(pixel_size * REFERENCE_HEIGHT, 0.0001);
	float offset = (wave * sway_amount + surge * sway_amount * 1.8) * lift;
	VERTEX.x += floor(offset / snap + 0.5) * snap;
}
