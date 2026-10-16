shader_type spatial;
// Rain streaks (world.gd precipitation). Lit, not glowing: on a dark night you
// only see the rain where a light falls on it, as on the menu. Fades out with
// distance (no white wall far off) and is cut away round the camera when
// you're in a cab or cockpit (no rain inside) - storm.gd sets near_cut.
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 col : source_color = vec4(0.72, 0.76, 0.82, 0.32);
uniform float near_cut = 0.0;
uniform float far_fade = 26.0;

void vertex() {
	// billboard round the vertical, like the standard FIXED_Y particles
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(VERTEX);
	if (d < near_cut) {
		discard;
	}
	ALBEDO = col.rgb;
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
	ALPHA = col.a * (1.0 - smoothstep(far_fade * 0.55, far_fade, d)) * smoothstep(near_cut, near_cut + 0.6, d);
}
