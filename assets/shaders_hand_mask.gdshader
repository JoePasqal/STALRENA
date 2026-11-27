shader_type canvas_item;
// Показывает только область вокруг сокета руки: перчатки/рукав героя рисуются поверх накладки брони.
uniform vec2 center_px = vec2(128.0, 128.0);   // в пикселях текстуры (с учётом клетки атласа)
uniform float radius_px = 34.0;
uniform float feather_px = 5.0;

void fragment() {
	vec2 px = UV * vec2(textureSize(TEXTURE, 0));
	float d = distance(px, center_px);
	COLOR.a *= 1.0 - smoothstep(radius_px - feather_px, radius_px, d);
}
