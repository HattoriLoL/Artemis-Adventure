extends Control
## Minigame "reabastecer água": segurar E para encher até a faixa limite do galão.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const CINZA := Color("#577277")

const ALTURA_MAXIMA := 44.0
const FAIXA_MIN := 0.78
const FAIXA_MAX := 0.95

var nivel := 0.0
var demo := false
var e_liberado := false
var acabou := false
var transbordou := false
var mensagem := ""

@onready var textos: Control = $Textos
@onready var jato: ColorRect = $Jato
@onready var galao: ColorRect = $Galao
@onready var agua_node: ColorRect = $Galao/Agua


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	jato.visible = false
	_atualizar_visual()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancelou.emit()
			set_process(false)


func _process(delta: float) -> void:
	if acabou:
		return

	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true

	var enchendo := false
	if demo:
		if nivel < (FAIXA_MIN + FAIXA_MAX) / 2.0:
			enchendo = true
		else:
			_verificar_resultado()
	else:
		enchendo = Input.is_action_pressed("usar") and e_liberado and not transbordou
		if Input.is_action_just_released("usar") and e_liberado:
			_verificar_resultado()

	jato.visible = enchendo

	if enchendo:
		nivel += 0.40 * delta
		if nivel >= 1.0:
			nivel = 1.0
			transbordou = true
			_esvaziar_por_transbordo()

	if transbordou:
		nivel = maxf(0.50, nivel - 0.60 * delta)
		if nivel <= 0.50:
			transbordou = false

	_atualizar_visual()
	textos.queue_redraw()


func _verificar_resultado() -> void:
	if nivel >= FAIXA_MIN and nivel <= FAIXA_MAX:
		_terminar("RESERVATORIO CHEIO")
	elif nivel < FAIXA_MIN and nivel > 0.1:
		mensagem = "VOLUME INSUFICIENTE! CONTINUE ENCHENDO"


func _esvaziar_por_transbordo() -> void:
	mensagem = "TRANSBORDOU! DRENANDO EXCESSO..."


func _atualizar_visual() -> void:
	var h: float = roundf(clampf(nivel, 0.0, 1.0) * ALTURA_MAXIMA)
	agua_node.size.y = h
	agua_node.position.y = 47.0 - h


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "DISPENSADOR DE AGUA", 160, 32, AMARELO)

	if acabou:
		Fonte.centralizado(textos, "RESERVATORIO CHEIO", 160, 138, VERDE, 2)
		return

	if transbordou:
		Fonte.centralizado(textos, "TRANSBORDOU! AGUARDE...", 160, 138, VERMELHO)
	elif mensagem != "" and not Input.is_action_pressed("usar"):
		Fonte.centralizado(textos, mensagem, 160, 138, AMARELO)
	else:
		Fonte.centralizado(textos, "SEGURE E: ENCHER  |  SOLTE NA MARCA", 160, 138, BRANCO)


func _terminar(texto: String) -> void:
	acabou = true
	jato.visible = false
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
