// Wet windshield at night (DESIGN_NOTES 188): the world behind the glass,
// fogged and soft, with beads of rain that act as little lenses and runs
// that slide down (and sideways in a gust). Reads the screen behind it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.62, 0.68, 0.76, 1.0);
uniform float haze_lod = 2.6;          // how soft the world looks through the wet glass
uniform float wind = 0.0;              // gust, -1..1: pushes runs sideways
uniform float rain = 1.0;              // 0..1 how hard it's raining
uniform float wet_time = 0.0;          // seconds (driven from script, keeps going while paused)
uniform vec2 glass_size = vec2(1.5, 0.62);
uniform float sheen = 0.35;            // how much the beads catch the cockpit light
uniform float bead_size = 1.0;         // bigger / smaller drops

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Beads sitting on the glass: one per cell, they land, swell and fade.
vec3 beads(vec2 uv, float t, float scale, float seed) {
	vec2 g = uv * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id + seed);
	vec2 c = vec2(hash(id + 3.1 + seed) - 0.5, hash(id + 7.7 + seed) - 0.5) * 0.7;
	float life = fract(t * (0.06 + 0.1 * h) + h);
	float present = step(h, 0.35 + 0.6 * rain);
	float r = mix(0.10, 0.30, hash(id + 1.9 + seed)) * smoothstep(0.0, 0.05, life) * (1.0 - smoothstep(0.6, 1.0, life)) * present;
	vec2 d = (f - c) * vec2(1.0, 1.15);
	float m = smoothstep(r, r * 0.55, length(d));
	return vec3(d * m, m);
}

// Runs: a drop that grows heavy and slides down, leaving a trail.
vec3 runs(vec2 uv, float t) {
	float cols = 16.0;
	// lean with the wind
	uv.x += wind * 0.35 * uv.y;
	float x = uv.x * cols;
	float id = floor(x);
	float fx = fract(x) - 0.5;
	float h = hash(vec2(id, 4.2));
	if (h > 0.25 + 0.55 * rain) return vec3(0.0);
	float speed = 0.10 + 0.30 * h;
	float p = fract(t * speed + h * 7.0);                   // head, 0 top .. 1 bottom
	float wig = sin(uv.y * 38.0 + h * 20.0) * 0.07 + (hash(vec2(id, floor(uv.y * 30.0))) - 0.5) * 0.05;
	float dx = fx - wig;
	vec2 hd = vec2(dx, (uv.y - p) * cols * glass_size.y / glass_size.x * 2.2);
	float head = smoothstep(0.17, 0.08, length(hd));
	float trail = smoothstep(0.06, 0.02, abs(dx)) * step(uv.y, p) * smoothstep(p - 0.45, p, uv.y) * 0.55;
	float m = max(head, trail);
	return vec3(vec2(dx, hd.y * 0.2) * m, m);
}

void fragment() {
	vec2 uv = UV;
	float t = wet_time;
	vec3 b1 = beads(uv * vec2(glass_size.x / glass_size.y, 1.0), t, 26.0 / bead_size, 0.0);
	vec3 b2 = beads(uv * vec2(glass_size.x / glass_size.y, 1.0), t * 1.3, 47.0 / bead_size, 11.0);
	vec3 r1 = runs(uv, t);
	vec2 off = b1.xy * 0.05 + b2.xy * 0.03 + r1.xy * 0.03;
	float drop = clamp(b1.z + b2.z * 0.8 + r1.z, 0.0, 1.0);
	// through clear wet glass the world is hazy; through a bead it's a small sharp, flipped image
	vec2 suv = SCREEN_UV - off * vec2(1.0, -1.0) * 1.6;
	vec3 hazy = textureLod(screen_tex, SCREEN_UV, haze_lod).rgb;
	vec3 sharp = textureLod(screen_tex, suv, 0.6).rgb;
	vec3 col = mix(hazy, sharp * 1.15, drop * 0.9);
	// each bead catches light: a cold rim on top, a warm glint low (the red flood)
	col += vec3(0.16, 0.18, 0.22) * smoothstep(0.0, -0.1, off.y) * drop * sheen * 2.0;
	col += vec3(0.20, 0.07, 0.04) * smoothstep(0.0, 0.1, off.y) * drop * sheen;
	// and the brighter the world behind, the brighter the bead (lights bloom in them)
	col += sharp * drop * sheen * 0.8;
	ALBEDO = col * tint.rgb;
	ALPHA = 1.0;
}
