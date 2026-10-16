shader_type canvas_item;

// Generated art contains translucent fringe pixels. Keep a single opaque silhouette.
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	if (COLOR.a < alpha_cutoff) {
		discard;
	}
	COLOR.a = 1.0;
}
