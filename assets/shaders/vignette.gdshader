shader_type canvas_item;
render_mode unshaded;

// Closing-in darkness driven by the guard's composure and by anything latched
// onto them. intensity 0 = clear view, 1 = a keyhole of sight.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.05, 0.0, 0.02, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.0, 1.14));
	// The clear window shrinks as things get bad, and breathes with the pulse.
	float inner = 0.56 - intensity * 0.42 - pulse * 0.05;
	float v = smoothstep(inner, 0.88, d);
	COLOR = vec4(tint.rgb, v * (0.32 + intensity * 0.62));
}