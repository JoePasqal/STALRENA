shader_type canvas_item;
// Мягкое затемнение по краям экрана (атмосфера); не закрывает телеграфы в центре.
uniform float strength = 0.55;
uniform vec3 tint = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.25, 1.0);
	float v = smoothstep(0.38, 0.95, length(d));
	COLOR = vec4(tint, v * strength);
}
