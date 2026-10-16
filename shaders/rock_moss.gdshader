shader_type spatial;
// Rock with moss (DESIGN_NOTES 235): the Blender-built rocks and cliffs have no
// UVs, so the photo-scan rock is projected from three sides (triplanar, world
// space) with its normal map; moss and forest litter settle on the tops and
// ledges (upward faces), patchy; dark wet streaks run down the faces.
uniform sampler2D rock_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_m = 4.0;          // metres a tile
uniform float moss_m = 2.5;
uniform vec3 rock_tint : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 moss_tint : source_color = vec3(0.55, 0.68, 0.38);
uniform float moss_amount = 0.6;     // 0 bare (high, dry) .. 1 the mossy gorge floor
uniform float streaks = 0.5;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack(vec4 t) { return t.xyz * 2.0 - 1.0; }

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 uvx = wpos.zy / rock_m;
	vec2 uvy = wpos.xz / rock_m;
	vec2 uvz = wpos.xy / rock_m;
	vec3 rc = texture(rock_c, uvx).rgb * w.x + texture(rock_c, uvy).rgb * w.y + texture(rock_c, uvz).rgb * w.z;
	// a second, larger scale breaks up the tiling
	rc = mix(rc, texture(rock_c, wpos.xz / (rock_m * 5.7)).rgb * w.y + texture(rock_c, wpos.zy / (rock_m * 5.3)).rgb * w.x + texture(rock_c, wpos.xy / (rock_m * 5.9)).rgb * w.z, 0.35);
	vec3 tx = unpack(texture(rock_n, uvx));
	vec3 ty = unpack(texture(rock_n, uvy));
	vec3 tz = unpack(texture(rock_n, uvz));
	// whiteout blend of the three projected normal maps into world space
	vec3 nx = vec3(0.0, tx.y, tx.x) * sign(n.x);
	vec3 ny = vec3(ty.x, 0.0, ty.y) * sign(n.y);
	vec3 nz = vec3(tz.x, tz.y, 0.0) * sign(n.z);
	vec3 rn = normalize(n + (nx * w.x + ny * w.y + nz * w.z) * 0.9);
	// moss: on faces turned up, patchy (the moss texture's own light/dark), more low down
	vec3 mc = texture(moss_c, wpos.xz / moss_m).rgb;
	float patch = texture(moss_c, wpos.xz / (moss_m * 9.0)).g;
	float up = smoothstep(0.35, 0.8, rn.y);
	float m = clamp(up * smoothstep(0.25, 0.6, patch + moss_amount * 0.5) * moss_amount * 1.6, 0.0, 1.0);
	vec3 mn = unpack(texture(moss_n, wpos.xz / moss_m));
	vec3 nrm = normalize(mix(rn, normalize(n + vec3(mn.x, 0.0, mn.y) * 0.6), m));
	// wet streaks down the steep faces
	float st = texture(rock_c, vec2(wpos.x * 0.15 + wpos.z * 0.15, wpos.y * 0.012)).r;
	float wet = (1.0 - abs(n.y)) * smoothstep(0.45, 0.7, st) * streaks;
	vec3 col = rc * rock_tint * (1.0 - wet * 0.45);
	col = mix(col, mc * moss_tint, m);
	ALBEDO = clamp(col, vec3(0.0), vec3(0.95));
	ROUGHNESS = mix(0.88, 0.95, m) - wet * 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
