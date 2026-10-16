shader_type spatial;
// Lakes and sea. Cold northern water: clear in the shallows (you see the
// stones and silt through it, tinted as it deepens), near black in the deep,
// with the sky in it at a glance. Wind ripples, foam where it meets the shore,
// and the waves that planes and boats make (scripts/waves.gd) rolling across it.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.012, 0.035, 0.045);
uniform vec3 scatter : source_color = vec3(0.035, 0.11, 0.115);
uniform vec3 absorb = vec3(0.60, 0.20, 0.15);    // per metre of water: red goes first
uniform float clarity = 1.0;                     // higher = murkier
uniform float chop = 1.0;                        // wind strength 0..2
uniform vec2 wind_dir = vec2(0.8, 0.6);          // where the wind blows to
uniform float shore_foam = 1.0;

uniform vec4 wave_src[64];
uniform int wave_count = 0;
uniform float wave_time = 0.0;

// The moving patch near the camera (world.gd): real waves in the geometry, and
// the flat lake and sea leave a hole for it. A lake patch is clipped to that
// lake's shoreline.
uniform bool displace = false;
uniform vec2 hole_center = vec2(0.0);
uniform float hole_r = 0.0;
uniform vec2 patch_center = vec2(0.0);
uniform float patch_r = 80.0;
uniform vec4 lake_shape = vec4(0.0);          // centre x, z, radius, seed (radius 0 = sea)

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Slope of one train of waves: direction, wavelength (m), height (m), speed factor.
vec2 train(vec2 p, vec2 d, float len, float amp, float t) {
	float k = 6.2832 / len;
	float c = sqrt(9.81 / k);
	return d * amp * k * cos(k * dot(d, p) - c * k * t);
}

// The wakes (scripts/waves.gd): height, and its slope in x and z.
vec3 wakes(vec2 p) {
	float h = 0.0;
	vec2 gr = vec2(0.0);
	for (int i = 0; i < wave_count; i++) {
		vec4 s = wave_src[i];
		vec2 dv = p - s.xy;
		float d = length(dv);
		float age = wave_time - s.z;
		float r = 3.2 * age;
		float w = 2.5 + 0.08 * r;
		float u = d - r;
		if (abs(u) > 3.0 * w) {
			continue;
		}
		float fall = s.w / sqrt(1.0 + 0.25 * r) * clamp(1.0 - age / 75.0, 0.0, 1.0) * smoothstep(0.0, 10.0, r);
		float env = exp(-u * u / (w * w));
		float sn = sin(0.97 * u);
		float cs = cos(0.97 * u);
		h += fall * env * sn;
		float dh = fall * env * (-2.0 * u / (w * w) * sn + 0.97 * cs);
		gr += dh * dv / max(d, 0.01);
	}
	return vec3(h, gr);
}

// Wind swell: a few long, low trains. Height and slope.
vec3 swell(vec2 p, float t) {
	vec2 wd = normalize(wind_dir);
	vec2 wp = vec2(-wd.y, wd.x);
	float amp = 0.02 + 0.07 * chop;
	vec3 o = vec3(0.0);
	vec2 dirs[3] = vec2[3](wd, normalize(wd + wp * 0.5), normalize(wd - wp * 0.4));
	float lens[3] = float[3](14.0, 8.5, 5.5);
	float amps[3] = float[3](1.0, 0.6, 0.35);
	for (int i = 0; i < 3; i++) {
		float k = 6.2832 / lens[i];
		float c = sqrt(9.81 / k);
		float ph = k * dot(dirs[i], p) - c * k * t;
		float a = amp * amps[i];
		o.x += a * sin(ph);
		o.yz += dirs[i] * a * k * cos(ph);
	}
	return o;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (displace) {
		// Fades to flat at the patch edge, where it meets the still water.
		float edge = 1.0 - smoothstep(patch_r * 0.6, patch_r * 0.95, length(wpos.xz - patch_center));
		float h = (wakes(wpos.xz).x + swell(wpos.xz, TIME).x) * edge;
		VERTEX.y += h;
		wpos.y += h;
	}
}

void fragment() {
	vec2 p = wpos.xz;
	if (hole_r > 0.0 && length(p - hole_center) < hole_r) {
		discard;
	}
	if (displace && lake_shape.z > 0.0) {
		vec2 dv = p - lake_shape.xy;
		float a = atan(dv.y, dv.x);
		float r = lake_shape.z * (1.0 + 0.22 * sin(3.0 * a + lake_shape.w) + 0.12 * sin(5.0 * a + lake_shape.w * 2.3)) * 1.12 + 40.0;
		if (length(dv) > r) {
			discard;
		}
	}
	float dist = length(VERTEX);
	float t = TIME;
	float near = clamp(1.0 - dist / 2600.0, 0.0, 1.0);
	float fine = clamp(1.0 - dist / 420.0, 0.0, 1.0);

	// Wind ripples: a few trains roughly downwind, finer ones fading with distance.
	vec2 wd = normalize(wind_dir);
	vec2 wp = vec2(-wd.y, wd.x);
	float a = 0.012 + 0.03 * chop;
	vec2 g = vec2(0.0);
	g += train(p, wd, 9.0, a * 1.0, t);
	g += train(p, normalize(wd + wp * 0.45), 5.3, a * 0.7, t);
	g += train(p, normalize(wd - wp * 0.6), 3.7, a * 0.5, t);
	g += train(p, normalize(wd + wp * 1.3), 2.1, a * 0.3, t) * fine;
	g *= near;
	// Cat's-paws: gusty patches of tiny ripples drifting downwind.
	vec2 q = p * 0.9 - wd * t * 1.4;
	float paws = smoothstep(0.35, 0.8, vnoise(p * 0.015 - wd * t * 0.05)) * chop;
	float e = 0.25;
	float n0 = vnoise(q);
	vec2 dn = vec2(vnoise(q + vec2(e, 0.0)) - n0, vnoise(q + vec2(0.0, e)) - n0) / e;
	g += dn * (0.03 + 0.1 * paws) * fine;
	vec2 q2 = p * 2.3 + wp * t * 0.9 - wd * t * 0.6;
	float m0 = vnoise(q2);
	vec2 dm = vec2(vnoise(q2 + vec2(e, 0.0)) - m0, vnoise(q2 + vec2(0.0, e)) - m0) / e;
	g += dm * (0.018 + 0.03 * chop) * fine;

	// Waves made by planes and boats, and (on the near patch) the swell.
	vec3 wk = wakes(p);
	float wake_h = wk.x;
	vec2 wake_g = wk.yz;
	if (displace) {
		float edge = 1.0 - smoothstep(patch_r * 0.6, patch_r * 0.95, length(p - patch_center));
		wake_g += swell(p, t).yz * edge;
	}
	g += wake_g;

	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	NORMAL = nv;

	// What is under the surface, and how much water we look through to see it.
	float zs = texture(depth_tex, SCREEN_UV).r;
	vec4 vb = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zs, 1.0);
	vb.xyz /= vb.w;
	vec3 bottom = (INV_VIEW_MATRIX * vec4(vb.xyz, 1.0)).xyz;
	float depth_v = max(wpos.y - bottom.y, 0.0);
	float path = max(length(vb.xyz) - dist, 0.0);

	// Bend the view through the ripples, but never pick up things in front of the water.
	vec2 ruv = SCREEN_UV + nw.xz * 0.035 * clamp(depth_v, 0.0, 1.5) * near;
	float zr = texture(depth_tex, ruv).r;
	vec4 vr = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, zr, 1.0);
	vr.xyz /= vr.w;
	if (length(vr.xyz) < dist) {
		ruv = SCREEN_UV;
	}
	vec3 below = texture(screen_tex, ruv).rgb;
	float through = min(path * 0.5 + depth_v * 0.7, 60.0);
	vec3 trans = exp(-absorb * clarity * through);

	// Foam: a lacy line where it laps the shore (more when waves arrive), and on wake crests.
	float lace = vnoise(p * 1.6 + vec2(t * 0.25, -t * 0.18)) * vnoise(p * 0.45 - vec2(t * 0.06));
	float wash = 0.25 + 2.5 * clamp(abs(wake_h), 0.0, 0.3) + 0.15 * chop;
	float foam = (1.0 - smoothstep(0.0, wash, depth_v)) * smoothstep(0.12, 0.35, lace) * shore_foam;
	foam += smoothstep(0.05, 0.16, wake_h) * smoothstep(0.2, 0.5, lace);
	foam = clamp(foam * near, 0.0, 0.9);

	float facing = clamp(dot(nv, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	vec3 body = mix(scatter, deep, clamp(through / 18.0, 0.0, 1.0));
	ALBEDO = mix(body * (1.0 - trans), vec3(0.85, 0.88, 0.9), foam);
	EMISSION = below * trans * (1.0 - fres) * (1.0 - foam);
	ROUGHNESS = mix(0.02 + 0.05 * chop * vnoise(p * 0.08 + t * 0.02), 0.7, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	// Melt into the ground at the very edge instead of a hard line.
	ALPHA = clamp(depth_v / 0.06, 0.0, 1.0);
}
