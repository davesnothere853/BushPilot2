shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
// "Painted" look (The Long Dark style): the frame is smoothed into flat patches
// of colour (a cheap Kuwahara filter keeps the edges crisp), the colours are
// pulled toward a muted, cold-and-warm palette, and dark outlines are drawn
// where the depth jumps. Drawn on a full-screen quad in front of the camera.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float radius = 2.0;          // brush size in pixels at 720 lines (scaled with the screen)
uniform float strength = 1.0;        // 0 = off, 1 = full look
uniform vec3 shadow_tint = vec3(0.26, 0.31, 0.42);
uniform vec3 light_tint = vec3(1.04, 0.96, 0.84);
uniform float outline = 0.55;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	// Kuwahara: of the four quadrants round the pixel, take the mean of the
	// one with the least variance.
	vec3 m[4];
	vec3 s[4];
	for (int k = 0; k < 4; k++) { m[k] = vec3(0.0); s[k] = vec3(0.0); }
	int r = int(clamp(radius * VIEWPORT_SIZE.y / 720.0 + 0.5, 1.0, 4.0));
	float n = float((r + 1) * (r + 1));
	for (int j = -r; j <= 0; j++) {
		for (int i = -r; i <= 0; i++) {
			vec3 c0 = textureLod(screen_tex, uv + vec2(float(i), float(j)) * px, 0.0).rgb;
			vec3 c1 = textureLod(screen_tex, uv + vec2(float(-i), float(j)) * px, 0.0).rgb;
			vec3 c2 = textureLod(screen_tex, uv + vec2(float(i), float(-j)) * px, 0.0).rgb;
			vec3 c3 = textureLod(screen_tex, uv + vec2(float(-i), float(-j)) * px, 0.0).rgb;
			m[0] += c0; s[0] += c0 * c0;
			m[1] += c1; s[1] += c1 * c1;
			m[2] += c2; s[2] += c2 * c2;
			m[3] += c3; s[3] += c3 * c3;
		}
	}
	vec3 col = vec3(0.0);
	float best = 1e9;
	for (int k = 0; k < 4; k++) {
		vec3 mean = m[k] / n;
		vec3 var3 = abs(s[k] / n - mean * mean);
		float v = var3.r + var3.g + var3.b;
		if (v < best) { best = v; col = mean; }
	}
	vec3 orig = textureLod(screen_tex, uv, 0.0).rgb;
	// Palette: muted, shadows cool and blue, lights warm.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(lum);
	col = mix(grey, col, 0.78);
	col *= mix(shadow_tint * 2.2, light_tint, smoothstep(0.08, 0.7, lum));
	// A few soft bands of value, like paint laid in layers.
	float bands = 7.0;
	float q = floor(lum * bands + 0.5) / bands;
	col *= mix(1.0, (q + 0.02) / max(lum, 0.02), 0.25);
	// Outlines where the depth steps (near objects only).
	float d0 = lin_depth(uv, INV_PROJECTION_MATRIX);
	float dx = lin_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float dy = lin_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float edge = (abs(dx - d0) + abs(dy - d0)) / max(d0, 0.5);
	float line = smoothstep(0.04, 0.12, edge) * (1.0 - smoothstep(300.0, 1500.0, d0));
	col *= 1.0 - line * outline;
	// Paper grain.
	float g = fract(sin(dot(floor(FRAGCOORD.xy * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
	col *= 0.97 + 0.06 * g;
	ALBEDO = mix(orig, col, strength);
}
