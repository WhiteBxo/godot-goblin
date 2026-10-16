shader_type canvas_item;
render_mode unshaded;

// Source artwork stays untouched. Suppress only the baked neutral checkerboard.
void fragment() {
	vec3 source_rgb = texture(TEXTURE, UV).rgb;
	float darkest = min(source_rgb.r, min(source_rgb.g, source_rgb.b));
	float lightest = max(source_rgb.r, max(source_rgb.g, source_rgb.b));
	if (darkest > 0.65 && lightest - darkest < 0.08) {
		COLOR.a = 0.0;
	}
}
