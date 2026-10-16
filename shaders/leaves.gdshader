shader_type spatial;
// Leaf-cluster cards on the deciduous trees: alpha-cut leaves, light through them
// from behind, the crown swaying in the wind, every card fluttering on its own,
// and the fall: each card turns green -> its autumn colours -> brown on its own
// schedule (custom.a), then its leaves drop one by one until the branch is bare.
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 wind = vec2(0.9, 0.35);       // direction * strength
uniform float tree_height = 12.0;
uniform float crown_round = 0.75;          // how much the cards' light follows the round crown
uniform float autumn = 0.0;                // 0 summer .. 0.5 full colour .. 0.85 brown .. 1.2 bare
uniform vec3 c_summer : source_color = vec3(0.30, 0.42, 0.16);
uniform vec3 c_early : source_color = vec3(0.62, 0.62, 0.18);
uniform vec3 c_peak : source_color = vec3(0.90, 0.62, 0.12);
uniform vec3 c_late : source_color = vec3(0.78, 0.25, 0.10);
uniform vec3 c_dead : source_color = vec3(0.45, 0.30, 0.16);

varying vec3 v_tint;
varying float v_a;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = NODE_POSITION_WORLD;
	float h = clamp((w.y - root.y) / tree_height, 0.0, 1.2);
	float ph = dot(root.xz, vec2(0.13, 0.17));
	float t = TIME;
	float ws = length(wind);
	float rock = sin(t * 0.9 + ph) * 0.6 + sin(t * 2.1 + ph * 1.7) * 0.25 + 0.6;
	vec3 lean = vec3(wind.x, 0.0, wind.y) * rock * h * h * 0.35;
	float cph = dot(w, vec3(1.7, 2.3, 1.1));
	vec3 flutter = vec3(sin(t * 6.0 + cph), sin(t * 7.3 + cph * 1.3) * 0.6, cos(t * 5.2 + cph)) * 0.035 * (0.3 + ws);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(lean + flutter * h, 0.0)).xyz;
	vec3 outward = INSTANCE_CUSTOM.rgb * 2.0 - 1.0;
	NORMAL = normalize(mix(NORMAL, outward, crown_round));
	// this card's own place in the season (the sunny outside of the crown turns first)
	v_a = autumn + (INSTANCE_CUSTOM.a - 0.5) * 0.5;
	v_tint = COLOR.rgb;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(leaf_tex, UV);
	// dropping: leaves (cells of the card) go one by one past full brown
	float gone = clamp((v_a - 0.85) / 0.35, 0.0, 1.0);
	if (hash(floor(UV * 7.0) + COLOR.rg * 13.0) < gone) {
		discard;
	}
	float a = clamp(v_a, 0.0, 1.0);
	vec3 col = c_summer;
	col = mix(col, c_early, smoothstep(0.05, 0.3, a));
	col = mix(col, c_peak, smoothstep(0.25, 0.5, a));
	col = mix(col, c_late, smoothstep(0.5, 0.7, a));
	col = mix(col, c_dead, smoothstep(0.7, 0.9, a));
	// some leaves on a card run ahead of the others: a speckle of the next colour
	float sp = hash(floor(UV * 11.0) + 3.1);
	col = mix(col, mix(c_peak, c_late, a), step(0.82, sp) * smoothstep(0.02, 0.2, a) * 0.6);
	ALBEDO = c.rgb * col * v_tint * 1.6;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.72;
	SPECULAR = 0.25;
	BACKLIGHT = col * v_tint * 0.5;     // sun through the leaves
}
