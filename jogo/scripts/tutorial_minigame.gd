extends Control
## Tutorial de primeira vez de um minigame: aparece por cima do jogo antes do minigame abrir, só na primeira vez que o
## jogador faz aquela tarefa (fica guardado em user://tutoriais.cfg; o menu de pausa pode zerar).
## Mostra a ilustração da tarefa (assets/tutoriais/<id>.png, 120x80), os passos de como jogar com as teclas desenhadas
## como teclas de teclado ([E], [W]...) e um fato real: por que os astronautas fazem isso de verdade, com a fonte.
## Textos em dados/tutoriais.json, por id (o nome da cena do minigame sem "minigame_": agua, algas, tanques...).
## E / Enter / clique (ao soltar, para o minigame não começar com a tecla apertada) começa; Esc ou X volta ao jogo.

signal continuar
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const ARQUIVO_DADOS := "res://dados/tutoriais.json"
const ARQUIVO_VISTOS := "user://tutoriais.cfg"
const PASTA_ARTE := "res://assets/tutoriais/"

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const FUNDO_2 := Color("#202e37")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const VERDE_LIMA := Color("#a8ca58")
const AZUL_CLARO := Color("#73bed3")
const VERMELHO := Color("#a53030")

const PAINEL := Rect2(8, 5, 304, 170)
const ARTE := Rect2(18, 22, 120, 80)
const PASSOS := Rect2(146, 24, 158, 80)          # coluna dos passos (como jogar)
const FATO := Rect2(16, 112, 288, 40)            # caixa do fato real (até 3 linhas)
const BOTAO_X := Rect2(296, 9, 8, 8)
const ESPERA := 0.35                             # a tecla que abriu a tarefa não pode já começar

static var _dados := {}

var id := ""
var t := 0.0
var armado := false                              # E apertado com o tutorial aberto: começa quando soltar
var armado_clique := false                       # o mesmo para o clique
var info := {}
var arte: Texture2D


## Id do tutorial de um minigame a partir do caminho da cena ("res://cenas/minigame_agua.tscn" -> "agua").
static func id_de(caminho: String) -> String:
	return caminho.get_file().get_basename().trim_prefix("minigame_")


static func dados() -> Dictionary:
	if _dados.is_empty() and FileAccess.file_exists(ARQUIVO_DADOS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO_DADOS))
		if d is Dictionary:
			_dados = d
	return _dados


static func tem(id_: String) -> bool:
	return dados().has(id_)


static func ja_visto(id_: String) -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(ARQUIVO_VISTOS) == OK and bool(cfg.get_value("vistos", id_, false))


static func marcar_visto(id_: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ARQUIVO_VISTOS)
	cfg.set_value("vistos", id_, true)
	cfg.save(ARQUIVO_VISTOS)


## Esquece os tutoriais vistos (todos voltam a aparecer na primeira vez de cada minigame).
static func zerar() -> void:
	var cfg := ConfigFile.new()
	cfg.save(ARQUIVO_VISTOS)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	size = Vector2(320, 180)
	info = dados().get(id, {})
	var c := PASTA_ARTE + id + ".png"
	arte = load(c) if ResourceLoader.exists(c) else null


func _input(ev: InputEvent) -> void:
	if t < ESPERA:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if BOTAO_X.grow(1).has_point(get_local_mouse_position()):
			cancelou.emit()
		else:
			armado_clique = true
	elif ev.is_action_pressed("ui_cancel"):
		cancelou.emit()


func _process(delta: float) -> void:
	t += delta
	if t >= ESPERA and Input.is_action_just_pressed("usar"):
		armado = true
	if armado and not Input.is_action_pressed("usar"):
		armado = false
		continuar.emit()
	elif armado_clique and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		armado_clique = false
		continuar.emit()
	queue_redraw()


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.78))
	_moldura()
	Fonte.centralizado(self, str(info.get("titulo", id.to_upper())), 160, PAINEL.position.y + 5, AMARELO)
	_botao_x()
	_arte()
	_passos()
	_fato()
	var pisca := fmod(t, 1.0) < 0.7
	if pisca or armado:
		Fonte.desenhar(self, "PRESS", Vector2(PAINEL.position.x + 10, 164), AMARELO)
		var x := PAINEL.position.x + 10 + Fonte.largura("PRESS ")
		x += _tecla("E", Vector2(x, 162))
		Fonte.desenhar(self, " TO START", Vector2(x, 164), AMARELO)
	var volta := "ESC: BACK"
	Fonte.desenhar(self, volta, Vector2(PAINEL.end.x - 10 - Fonte.largura(volta), 164), METAL)


func _moldura() -> void:
	var p := PAINEL
	draw_rect(p, PRETO)
	draw_rect(p.grow(-1), CINZA)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(p.size.x - 2, 1)), METAL_CLARO)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(1, p.size.y - 2)), METAL)
	draw_rect(Rect2(p.position + Vector2(2, p.size.y - 2), Vector2(p.size.x - 3, 1)), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(p.size.x - 2, 2), Vector2(1, p.size.y - 3)), CINZA_ESC)
	for c in [Vector2(3, 3), Vector2(p.size.x - 6, 3), Vector2(3, p.size.y - 6), Vector2(p.size.x - 6, p.size.y - 6)]:
		draw_rect(Rect2(p.position + c, Vector2(3, 3)), METAL)
		draw_rect(Rect2(p.position + c + Vector2.ONE, Vector2.ONE), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(8, 3), Vector2(p.size.x - 16, 10)), FUNDO)
	draw_rect(Rect2(p.position + Vector2(8, 155), Vector2(p.size.x - 16, 11)), FUNDO)


func _botao_x() -> void:
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)


func _arte() -> void:
	draw_rect(ARTE.grow(2), PRETO)
	draw_rect(ARTE.grow(1), METAL)
	if arte:
		draw_texture_rect(arte, ARTE, false)
	else:
		draw_rect(ARTE, FUNDO_2)
		Fonte.centralizado(self, "?", ARTE.get_center().x, ARTE.get_center().y - 2, CINZA)


func _passos() -> void:
	Fonte.desenhar(self, "HOW TO PLAY", PASSOS.position, AZUL_CLARO)
	var y := PASSOS.position.y + 10
	for p in info.get("passos", []):
		draw_rect(Rect2(PASSOS.position.x, y + 2, 2, 2), AMARELO)
		y = _texto_com_teclas(str(p), Vector2(PASSOS.position.x + 5, y), PASSOS.size.x - 5, BRANCO_SUJO)
		y += 3


func _fato() -> void:
	var fato := str(info.get("fato", ""))
	if fato == "":
		return
	var r := FATO
	draw_rect(r, PRETO)
	draw_rect(r.grow(-1), FUNDO)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), FUNDO_2)
	Fonte.desenhar(self, "REAL FACT", r.position + Vector2(5, 4), VERDE_LIMA)
	var y := r.position.y + 13
	for l in _quebrar(fato, r.size.x - 10):
		Fonte.desenhar(self, l, Vector2(r.position.x + 5, y), BRANCO)
		y += 7
	var fonte := str(info.get("fonte", ""))
	if fonte != "":
		var f := "SOURCE: " + fonte
		Fonte.desenhar(self, f, Vector2(r.end.x - 5 - Fonte.largura(f), r.position.y + 4), CINZA)


## Escreve um texto quebrando em linhas de até `largura` px; palavras entre colchetes ([E], [W]) viram teclas.
## Devolve o y da linha seguinte.
func _texto_com_teclas(texto: String, pos: Vector2, largura: float, cor: Color) -> float:
	var x := pos.x
	var y := pos.y
	var palavras := texto.split(" ", false)
	for i in palavras.size():
		var p: String = palavras[i]
		var eh_tecla := p.begins_with("[") and p.find("]") > 1
		var resto := ""
		var w := 0.0
		if eh_tecla:
			var fim := p.find("]")
			resto = p.substr(fim + 1)
			w = Fonte.largura(p.substr(1, fim - 1)) + 5 + Fonte.largura(resto)
		else:
			w = Fonte.largura(p)
		var junto := w                           # a tecla não fica no fim da linha longe da palavra seguinte
		if eh_tecla and i + 1 < palavras.size() and not palavras[i + 1].begins_with("["):
			junto += 4 + Fonte.largura(palavras[i + 1])
		if x > pos.x and x + junto > pos.x + largura:
			x = pos.x
			y += 9
		if eh_tecla:
			var fim := p.find("]")
			x += _tecla(p.substr(1, fim - 1), Vector2(x, y - 2))
			if resto != "":
				Fonte.desenhar(self, resto, Vector2(x, y), cor)
				x += Fonte.largura(resto)
		else:
			Fonte.desenhar(self, p, Vector2(x, y), cor)
			x += w
		x += 4
	return y + 9


## Desenha uma tecla do teclado com o rótulo; devolve a largura ocupada.
func _tecla(rotulo: String, pos: Vector2) -> float:
	var w := Fonte.largura(rotulo) + 4
	var r := Rect2(pos, Vector2(w, 9))
	draw_rect(r, PRETO)
	draw_rect(r.grow(-1), CINZA_ESC)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(w - 2, 1)), METAL)
	draw_rect(Rect2(r.position + Vector2(1, 7), Vector2(w - 2, 1)), FUNDO_2)
	Fonte.desenhar(self, rotulo, pos + Vector2(2, 2), BRANCO, 1, false)
	return w + 1


func _quebrar(texto: String, largura: float) -> Array[String]:
	var res: Array[String] = []
	var atual := ""
	for p in texto.split(" ", false):
		var tentativa: String = p if atual == "" else atual + " " + p
		if Fonte.largura(tentativa) > largura and atual != "":
			res.append(atual)
			atual = p
		else:
			atual = tentativa
	if atual != "":
		res.append(atual)
	return res


## Para a cena rodar sozinha (teste): no jogo, quem cria as teclas é o mapa.
func _criar_teclas() -> void:
	var teclas := {"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT], "cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN], "usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]}
	for acao in teclas:
		if InputMap.has_action(acao):
			continue
		InputMap.add_action(acao)
		for k in teclas[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(acao, ev)
