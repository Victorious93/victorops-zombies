shader_type spatial;
// v7.12 last-zombie outline: unshaded additive fresnel rim that pulses, so it reads under bright lamps.
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 rim_color : source_color = vec4(1.0, 0.08, 0.04, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(TIME * 6.2832 * 1.4));
	ALBEDO = rim_color.rgb * (rim * 2.2 + 0.18) * pulse;
}
