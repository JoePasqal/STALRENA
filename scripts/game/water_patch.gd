class_name WaterPatch
extends Node2D
## Вода с неровным берегом: бесшовная текстура + шейдер, который по шумовому расстоянию до прямоугольника
## размывает край (никаких прямых углов/швов). Коллизия/замедление остаются прямоугольником данных.

const MARGIN := 90.0
const SHADER := """
shader_type canvas_item;
uniform sampler2D tex : repeat_enable, filter_linear;
uniform vec2 rect_size;
uniform float seed;
varying vec2 lp;

void vertex() { lp = VERTEX; }

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.2;
}

void fragment() {
	vec2 c = rect_size * 0.5;
	float r = min(c.x, c.y) * 0.55;
	vec2 q = abs(lp - c) - (c - vec2(r));
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	sd += (fbm(lp * 0.011 + 3.7) - 0.5) * 190.0;
	float water_a = 1.0 - smoothstep(-10.0, 10.0, sd);
	float ring_a = (1.0 - smoothstep(2.0, 50.0, sd)) * 0.34;
	vec3 w = texture(tex, lp / 512.0).rgb * 0.88;
	float shore = smoothstep(-34.0, 0.0, sd);
	w = mix(w, vec3(0.26, 0.30, 0.17), shore * 0.38);
	vec3 mud = vec3(0.07, 0.10, 0.05);
	COLOR = vec4(mix(mud, w, water_a), max(water_a * 0.97, ring_a));
}
"""

static var _shader: Shader

var size_px := Vector2(100, 100)


func setup(r: Rect2, seed_v: int) -> void:
	position = r.position
	size_px = r.size
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tex", AssetRegistry.get_texture("water.flooded"))
	mat.set_shader_parameter("rect_size", r.size)
	mat.set_shader_parameter("seed", float(seed_v % 997) * 0.01)
	material = mat
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-MARGIN, -MARGIN), size_px + Vector2(MARGIN, MARGIN) * 2.0), Color.WHITE)
