# Fonte de pixel 3x5 desenhada com retângulos (o jogo não usa nenhuma fonte externa).
extends RefCounted

const GLIFOS := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111",
	"0": "111101101101111", "1": "010110010010111", "2": "110001010100111", "3": "110001010001110",
	"4": "101101111001001", "5": "111100110001110", "6": "011100111101111", "7": "111001010010010",
	"8": "111101111101111", "9": "111101111001110",
	".": "000000000000010", "!": "010010010000010", ":": "000010000010000", "-": "000000111000000",
	"/": "001001010100100", "?": "110001010000010", ">": "100010001010100", "'": "010010000000000",
	",": "000000000010100", "+": "000010111010000", " ": "000000000000000",
	"(": "010100100100010", ")": "010001001001010", "|": "010010010010010",
}
const SEM_ACENTO := {"Á": "A", "À": "A", "Â": "A", "Ã": "A", "É": "E", "Ê": "E", "Í": "I", "Ó": "O", "Ô": "O",
	"Õ": "O", "Ú": "U", "Ç": "C"}


static func limpar(t: String) -> String:
	var s := t.to_upper()
	for k in SEM_ACENTO:
		s = s.replace(k, SEM_ACENTO[k])
	return s


static func largura(t: String, esc := 1) -> int:
	return maxi(0, limpar(t).length() * 4 * esc - esc)


static func desenhar(ci: CanvasItem, t: String, pos: Vector2, cor: Color, esc := 1, sombra := true) -> void:
	var s := limpar(t)
	if sombra:
		_linha(ci, s, pos + Vector2(esc, esc), Color(0, 0, 0, cor.a * 0.8), esc)
	_linha(ci, s, pos, cor, esc)


static func centralizado(ci: CanvasItem, t: String, cx: float, y: float, cor: Color, esc := 1) -> void:
	desenhar(ci, t, Vector2(round(cx - largura(t, esc) / 2.0), y), cor, esc)


static func _linha(ci: CanvasItem, s: String, pos: Vector2, cor: Color, esc: int) -> void:
	var x := pos.x
	for ch in s:
		var g: String = GLIFOS.get(ch, GLIFOS["?"])
		for i in 15:
			if g[i] == "1":
				ci.draw_rect(Rect2(x + (i % 3) * esc, pos.y + (i / 3) * esc, esc, esc), cor)
		x += 4 * esc
