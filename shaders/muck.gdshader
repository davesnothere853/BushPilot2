shader_type spatial;
// Mud caked on a vehicle (DESIGN_NOTES 109): drawn over its own materials as
// an overlay. Heaviest low down and on the wheels, splashed edges higher up,
// flat polyart blotches (no texture). `muck` 0 clean .. 1 plastered.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;

uniform float muck = 0.0;
uniform float base_y = 0.0;      // (unused now: height comes from the vehicle's own frame)
uniform mat4 veh_inv = mat4(1.0); // world -> the vehicle's frame, so the mud rides along with it
uniform float reach = 0.9;       // how high it gets when fully plastered, m
uniform vec3 col_wet : source_color = vec3(0.22, 0.17, 0.12);
uniform vec3 col_dry : source_color = vec3(0.45, 0.38, 0.30);

// The cab, in the vehicle's frame: inside it only the outside skin (faces
// pointing out through a side or down under the floor) takes mud - not the
// seats, the dash, the floor or the inside of the doors. lo > hi: no cab.
uniform vec3 cab_lo = vec3(1.0);
uniform vec3 cab_hi = vec3(-1.0);
uniform bool spin_mode = false;  // on a tyre: the mud is stuck to the tyre and turns with it
varying vec3 wp;
varying vec3 mp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mp = VERTEX;
}

void fragment() {
	if (spin_mode) {
		// clods packed in the tread and smeared over the sidewall, in the
		// tyre's own frame so they go round with it
		float t1 = vnoise(mp.xy * 9.0 + mp.z * 3.0);
		float t2 = vnoise(mp.zy * 14.0 + 7.0);
		float cov = step(1.0 - muck * 1.15, 0.55 * t1 + 0.45 * t2);
		ALBEDO = mix(col_wet, col_dry, step(0.6, t2)) * (0.85 + 0.3 * t1);
		ROUGHNESS = 0.95;
		ALPHA = cov * 0.95 * step(0.02, muck);
	} else {
		vec3 lp = (veh_inv * vec4(wp, 1.0)).xyz;     // where on the truck this is
		float h = lp.y;
		float n = vnoise(lp.xz * 2.3 + vec2(lp.y * 3.1, 0.0));
		float n2 = vnoise(lp.zx * 7.0 + vec2(0.0, lp.y * 5.0));
		float line = muck * reach + (n - 0.5) * 0.35 * muck;
		float cover = step(h, line);
		// splats a little above the line
		cover = max(cover, step(0.78, n2) * step(h, line + 0.35 * muck) * step(0.15, muck));
		float age = clamp(h / max(line, 0.01), 0.0, 1.0);
		vec3 c = mix(col_wet, col_dry, floor(age * 2.0 + n) / 2.0);
		ALBEDO = c * (0.85 + 0.3 * n);
		ROUGHNESS = 0.95;
		ALPHA = cover * 0.95 * step(0.02, muck);
	}
}
