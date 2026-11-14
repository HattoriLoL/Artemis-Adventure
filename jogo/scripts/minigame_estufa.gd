extends Control
## Minigame da estufa: regar 3 bandejas na medida certa.

signal terminou

const Fonte = preload("res://scripts/fonte.gd")
const TEXTO := Color("#ebede9")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#75a743")
const CINZA := Color("#819796")
const VERMELHO := Color("#d65b5b")
const AZUL := Color("#38a2e5")

const BARRA_ALTURA := 80.0
const VELOCIDADE_ENCHER := 0.52

# Faixas de acerto (min, max) para cada bandeja (0.0 a 1.0)
const FAIXAS := [
	{"min": 0.35, "max": 0.60},
	{"min": 0.60, "max": 0.85},
	{"min": 0.40, "max": 0.65}
]

enum Estado {
	JOGANDO,
	ACERTO,
	MUITO_POUCO,
	TRANSBORDOU,
	CONCLUIDO
}

var demo := false   # no modo demo, o minigame se resolve sozinho

var bandeja_atual := 0
var nivel_agua := 0.0 # 0.0 a 1.0
var estado: Estado = Estado.JOGANDO
var t_espera := 0.0

@onready var painel: ColorRect = $Painel
@onready var bandejas: Array = [$Bandeja1, $Bandeja2, $Bandeja3]
@onready var brotos: Array = [$Bandeja1/Broto, $Bandeja2/Broto, $Bandeja3/Broto]
@onready var barra: ColorRect = $Barra
@onready var faixa: ColorRect = $Barra/Faixa
@onready var agua: ColorRect = $Barra/Agua
@onready var textos: Control = $Textos


func _ready() -> void:
	_criar_tecla_usar()
	textos.draw.connect(_desenhar_textos)
	_configurar_bandeja(0)


func _configurar_bandeja(idx: int) -> void:
	bandeja_atual = idx
	nivel_agua = 0.0
	estado = Estado.JOGANDO
	_atualizar_faixa()
	_atualizar_agua()


func _atualizar_faixa() -> void:
	if bandeja_atual >= FAIXAS.size():
		return
	var f: Dictionary = FAIXAS[bandeja_atual]
	var y_topo: float = BARRA_ALTURA - (f["max"] * BARRA_ALTURA)
	var h: float = (f["max"] - f["min"]) * BARRA_ALTURA
	faixa.position = Vector2(0, y_topo)
	faixa.size = Vector2(barra.size.x, h)


func _atualizar_agua() -> void:
	var h: float = clampf(nivel_agua, 0.0, 1.0) * BARRA_ALTURA
	agua.size = Vector2(barra.size.x, h)
	agua.position = Vector2(0, BARRA_ALTURA - h)


func _process(delta: float) -> void:
	if estado == Estado.CONCLUIDO:
		t_espera -= delta
		if t_espera <= 0.0:
			terminou.emit()
			set_process(false)
		textos.queue_redraw()
		return

	if estado in [Estado.MUITO_POUCO, Estado.TRANSBORDOU]:
		t_espera -= delta
		nivel_agua = maxf(0.0, nivel_agua - delta * 2.2)
		_atualizar_agua()
		if t_espera <= 0.0:
			nivel_agua = 0.0
			_atualizar_agua()
			estado = Estado.JOGANDO
		textos.queue_redraw()
		return

	if estado == Estado.ACERTO:
		t_espera -= delta
		if t_espera <= 0.0:
			if bandeja_atual + 1 < 3:
				_configurar_bandeja(bandeja_atual + 1)
			else:
				_finalizar()
		textos.queue_redraw()
		return

	# Estado JOGANDO
	var segurando := false
	if demo:
		var f: Dictionary = FAIXAS[bandeja_atual]
		var alvo: float = (f["min"] + f["max"]) / 2.0
		if nivel_agua < alvo:
			segurando = true
	else:
		segurando = Input.is_action_pressed("usar")

	if segurando:
		nivel_agua += delta * VELOCIDADE_ENCHER
		if nivel_agua >= 1.0:
			nivel_agua = 1.0
			_atualizar_agua()
			_falhar(Estado.TRANSBORDOU)
			textos.queue_redraw()
			return
		_atualizar_agua()
	else:
		if demo and nivel_agua > 0.0:
			_soltar()
		elif not demo and Input.is_action_just_released("usar"):
			_soltar()

	textos.queue_redraw()


func _soltar() -> void:
	if estado != Estado.JOGANDO:
		return
	if nivel_agua <= 0.02:
		return

	var f: Dictionary = FAIXAS[bandeja_atual]
	if nivel_agua < f["min"]:
		_falhar(Estado.MUITO_POUCO)
	elif nivel_agua <= f["max"]:
		_acertar()
	else:
		_falhar(Estado.TRANSBORDOU)


func _acertar() -> void:
	estado = Estado.ACERTO
	t_espera = 0.6
	brotos[bandeja_atual].visible = true


func _falhar(novo_estado: Estado) -> void:
	estado = novo_estado
	t_espera = 0.75


func _finalizar() -> void:
	estado = Estado.CONCLUIDO
	t_espera = 1.8
	faixa.visible = false
	agua.visible = false


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "ESTUFA: REGAR AS PLANTAS", 160, 31, AMARELO)

	if estado == Estado.CONCLUIDO:
		Fonte.centralizado(textos, "PLANTIO FEITO", 160, 70, VERDE, 2)
		Fonte.centralizado(textos, "AS PLANTAS CRESCERAO NOS PROXIMOS DIAS", 160, 95, TEXTO)
		return

	Fonte.centralizado(textos, "BANDEJA %d/3" % (bandeja_atual + 1), 138, 50, TEXTO)

	for i in 3:
		var bx: float = bandejas[i].position.x + bandejas[i].size.x / 2.0
		var cor_num: Color = VERDE if brotos[i].visible else (AMARELO if i == bandeja_atual else CINZA)
		Fonte.centralizado(textos, "%d" % (i + 1), bx, 110, cor_num)

	Fonte.centralizado(textos, "AGUA", barra.position.x + barra.size.x / 2.0, 36, AZUL)

	match estado:
		Estado.JOGANDO:
			Fonte.centralizado(textos, "SEGURE E: ENCHER", 138, 126, BRANCO if Input.is_action_pressed("usar") else CINZA)
			Fonte.centralizado(textos, "SOLTE NA FAIXA VERDE", 138, 136, VERDE)
		Estado.MUITO_POUCO:
			Fonte.centralizado(textos, "POUCA AGUA! TENTE DE NOVO", 138, 130, VERMELHO)
		Estado.TRANSBORDOU:
			Fonte.centralizado(textos, "TRANSBORDOU! TENTE DE NOVO", 138, 130, VERMELHO)
		Estado.ACERTO:
			Fonte.centralizado(textos, "CERTO! BROTOU!", 138, 130, VERDE)


func _criar_tecla_usar() -> void:
	# para a cena rodar sozinha com F6: no jogo, quem cria a tecla é o mapa
	if InputMap.has_action("usar"):
		return
	InputMap.add_action("usar")
	for k in [KEY_E, KEY_X, KEY_J, KEY_ENTER]:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event("usar", ev)
