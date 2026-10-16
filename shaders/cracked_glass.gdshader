// Cracked glass (DESIGN_NOTES 199): a spider web round each impact - radial
// cracks running out, rings round the middle, a crushed white patch at the
// centre. Up to 4 hits, in the mesh's own space (vehicle_damage sets them).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.10, 0.13, 0.15, 0.40);
uniform int hits = 0;
uniform vec3 hit0;
uniform vec3 hit1;
uniform vec3 hit2;
uniform vec3 hit3;
uniform float amount = 0.5;        // 0..1 how far the cracks have run

varying vec3 lpos;
varying vec3 lnrm;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

float web(vec3 c, float seed) {
	vec3 n = normalize(lnrm);
	vec3 t = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 b = cross(n, t);
	vec3 d = lpos - c;
	vec2 p = vec2(dot(d, t), dot(d, b));
	float r = length(p);
	float reach = mix(0.15, 0.9, amount);
	if (r > reach) return 0.0;
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	// radial cracks: 18 of them, each wandering a little with distance
	float k = a * 18.0 + sin(r * 23.0 + seed) * 0.12 + sin(r * 61.0 + seed * 3.0) * 0.05;
	float cell = floor(k);
	float len = mix(0.4, 1.0, hash(cell + seed)) * reach;
	float radial = (1.0 - smoothstep(0.0, 0.035 + 0.004 / max(r, 0.01), abs(fract(k) - 0.5) * 2.0 * r * 4.0)) * step(r, len);
	// rings: a few broken circles near the middle
	float ring_k = r * 26.0 + hash(cell * 1.7 + seed) * 0.8;
	float ring = (1.0 - smoothstep(0.0, 0.07, abs(fract(ring_k) - 0.5))) * step(r, reach * 0.45) * step(0.5, hash(floor(ring_k) * 3.1 + cell + seed));
	float crush = 1.0 - smoothstep(0.0, 0.035, r);
	return clamp(max(max(radial, ring * 0.8), crush), 0.0, 1.0) * (1.0 - smoothstep(reach * 0.85, reach, r));
}

void fragment() {
	float c = 0.0;
	if (hits > 0) c = max(c, web(hit0, 1.0));
	if (hits > 1) c = max(c, web(hit1, 7.0));
	if (hits > 2) c = max(c, web(hit2, 13.0));
	if (hits > 3) c = max(c, web(hit3, 19.0));
	ALBEDO = mix(tint.rgb, vec3(0.92, 0.95, 0.96), c);
	ALPHA = mix(tint.a, 0.95, c);
	ROUGHNESS = mix(0.04, 0.5, c);
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
