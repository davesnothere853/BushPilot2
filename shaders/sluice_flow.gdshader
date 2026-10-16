shader_type spatial;
// Water running down a sluice or chute: ripples travel along it, the riffles
// kick up white water in bands, and it goes brown when there's gravel in it.
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform float mud : hint_range(0.0, 1.0) = 0.0;
uniform float speed = 1.0;
uniform float bands = 18.0;      // riffles along the length

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float rip = sin(uv.y * 60.0 - t * 14.0 + sin(uv.x * 23.0 + t * 2.0) * 1.8) * 0.5 + 0.5;
	rip *= sin(uv.y * 23.0 - t * 9.0 + uv.x * 7.0) * 0.5 + 0.5;
	float riffle = smoothstep(0.75, 1.0, fract(uv.y * bands - t * 0.15)) * 0.8;
	float speck = step(0.985, hash(floor(vec2(uv.x * 40.0, uv.y * 160.0 - t * 30.0))));
	vec3 clear = vec3(0.55, 0.66, 0.72);
	vec3 brown = vec3(0.42, 0.33, 0.22);
	vec3 base = mix(clear, brown, mud);
	vec3 foam = vec3(0.86, 0.86, 0.82);
	vec3 c = base * (0.82 + 0.3 * rip);
	c = mix(c, foam, clamp(riffle * (0.5 + 0.5 * rip) + speck * mud * 0.6, 0.0, 1.0) * 0.55);
	ALBEDO = c;
	ALPHA = mix(0.55, 0.9, mud) + riffle * 0.1;
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
