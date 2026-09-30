shader_type canvas_item;
// The supplied RGB logo contains a pale checkerboard. Key only neutral paper
// at display time; retain the original asset, dark ink, gold and vermilion.
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float paper = min(ink.r, min(ink.g, ink.b));
	ink.a *= 1.0 - smoothstep(0.72, 0.89, paper);
	COLOR = ink;
}
