shader_type spatial;
// v7.14 zombie rim + wound sheen overlay. Unshaded and lamp-independent, so warm lamps can never
// tint the skin orange (the v7.13 rim experiment). Cool moonlight edge + a few wet dark-red wound
// patches placed in object space (they stay put on the body as it animates). One cheap pass.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 rim_color : source_color = vec4(0.55, 0.66, 0.78, 1.0);
uniform float rim_strength = 0.22;
uniform float wound = 0.0;          // 0 healthy .. 1 near death
uniform float wound_seed = 0.0;
varying vec3 opos;
void vertex() { opos = VERTEX; }
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y);
	return mix(a, b, f.z);
}
void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 3.0) * rim_strength;
	float n = vnoise(opos * 5.5 + vec3(wound_seed));
	float patch = smoothstep(0.78 - wound * 0.18, 0.86 - wound * 0.18, n) * step(0.01, wound);
	// wet sheen: brighter glint on the patch edge that faces the camera
	float wet = pow(ndv, 6.0) * 0.35;
	vec3 blood = vec3(0.16, 0.012, 0.01) + vec3(0.3, 0.05, 0.04) * wet;
	ALBEDO = mix(rim_color.rgb, blood, patch);
	ALPHA = clamp(max(rim, patch * (0.55 + wound * 0.3)), 0.0, 0.85);
}
