extends Control
## Minigame "reforçar blindagem": mover 3 placas até os pontos vulneráveis e fixar com E.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const CINZA := Color("#577277")

const VELOCIDADE := 90.0
const DISTANCIA_ENCAIXE := 10.0

var demo := false
var placa_atual := 0
var e_liberado := false
var acabou := false
var mensagem := ""

@onready var textos: Control = $Textos
@onready var cursor_placa: ColorRect = $CursorPlaca
@onready var alvos: Array[ColorRect] = [$Alvo1, $Alvo2, $Alvo3]
@onready var fixas: Array[ColorRect] = [$Fixa1, $Fixa2, $Fixa3]


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	for f in fixas:
		f.visible = false
	cursor_placa.position = Vector2(144, 100)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancelou.emit()
			set_process(false)


func _process(delta: float) -> void:
	if acabou:
		return

	if not e_liberado:
		if not Input.is_action_pressed("usar"):
			e_liberado = true

	if demo:
		_jogar_sozinho(delta)
	else:
		_controles(delta)

	textos.queue_redraw()


func _controles(delta: float) -> void:
	var dir: Vector2 = Input.get_vector("esquerda", "direita", "cima", "baixo")
	cursor_placa.position += dir * VELOCIDADE * delta
	# Limita a placa dentro da parede
	cursor_placa.position.x = clampf(cursor_placa.position.x, 60.0, 228.0)
	cursor_placa.position.y = clampf(cursor_placa.position.y, 42.0, 102.0)

	var centro_placa: Vector2 = cursor_placa.position + cursor_placa.size / 2.0
	var centro_alvo: Vector2 = alvos[placa_atual].position + alvos[placa_atual].size / 2.0

	if centro_placa.distance_to(centro_alvo) <= DISTANCIA_ENCAIXE:
		if Input.is_action_just_pressed("usar") and e_liberado:
			_encaixar_placa()


func _jogar_sozinho(delta: float) -> void:
	var centro_placa: Vector2 = cursor_placa.position + cursor_placa.size / 2.0
	var centro_alvo: Vector2 = alvos[placa_atual].position + alvos[placa_atual].size / 2.0

	cursor_placa.position = cursor_placa.position.move_toward(alvos[placa_atual].position, VELOCIDADE * delta)

	if centro_placa.distance_to(centro_alvo) <= 2.0:
		_encaixar_placa()


func _encaixar_placa() -> void:
	fixas[placa_atual].visible = true
	placa_atual += 1

	if placa_atual >= 3:
		cursor_placa.visible = false
		_terminar("BLINDAGEM REFORCADA")
	else:
		# Reposiciona o cursor no centro para a próxima placa
		cursor_placa.position = Vector2(144, 98)


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "REFORCAR BLINDAGEM", 160, 30, AMARELO)

	if acabou:
		Fonte.centralizado(textos, mensagem, 160, 140, VERDE, 2)
		return

	# Destaca o contorno do alvo atual
	var a: ColorRect = alvos[placa_atual]
	textos.draw_rect(Rect2(a.position.x - 2, a.position.y - 2, a.size.x + 4, a.size.y + 4), AMARELO, false, 1.0)

	var centro_placa: Vector2 = cursor_placa.position + cursor_placa.size / 2.0
	var centro_alvo: Vector2 = a.position + a.size / 2.0
	var alinhado: bool = centro_placa.distance_to(centro_alvo) <= DISTANCIA_ENCAIXE

	if alinhado:
		Fonte.centralizado(textos, "APERTE E PARA PARAFUSAR!", 160, 140, VERDE)
	else:
		Fonte.centralizado(textos, "PLACA %d/3: MOVA ATE O PONTO DESTACADO" % (placa_atual + 1), 160, 140, BRANCO)


func _terminar(texto: String) -> void:
	acabou = true
	mensagem = texto
	textos.queue_redraw()
	await get_tree().create_timer(1.0).timeout
	terminou.emit()


func _criar_teclas() -> void:
	var teclas := {
		"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP], "baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]
	}
	for acao in teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			for k in teclas[acao]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(acao, ev)
