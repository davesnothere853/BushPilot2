shader_type spatial;
// Turns a cloth texture into worn leather: keeps the folds and seams from the
// texture's light and dark, but colours it brown and gives it a soft sheen.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 leather : source_color = vec3(0.42, 0.26, 0.16);
uniform float contrast = 1.6;

void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb;
	float lum = dot(t, vec3(0.299, 0.587, 0.114));
	float shade = clamp(0.5 + (lum - 0.18) * contrast * 2.0, 0.35, 1.25);
	ALBEDO = leather * shade;
	ROUGHNESS = mix(0.38, 0.62, 1.0 - shade * 0.7);
	SPECULAR = 0.45;
}
