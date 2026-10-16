shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Trees drawn in bulk. The vertex colour marks what each part is:
// red channel 1 = foliage, 0 = trunk; green channel = shade within the tree.
// The per-tree colour (from the MultiMesh) adds variety between neighbours.

uniform vec3 foliage : source_color = vec3(0.10, 0.22, 0.11);
uniform vec3 trunk : source_color = vec3(0.26, 0.19, 0.13);
uniform float snow = 0.0;

varying vec3 tint;
varying float is_leaf;
varying float shade;
varying float up_facing;

void vertex() {
	is_leaf = COLOR.r;
	shade = COLOR.g;
	tint = INSTANCE_CUSTOM.rgb;
	up_facing = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

void fragment() {
	vec3 leaf = foliage * (0.75 + 0.5 * tint.r) * (0.8 + 0.4 * shade);
	leaf = mix(leaf, vec3(0.80, 0.84, 0.90), snow * smoothstep(0.30, 0.75, up_facing) * 0.55 + snow * 0.12);
	ALBEDO = mix(trunk, leaf, is_leaf);
	ROUGHNESS = 0.95;
}
