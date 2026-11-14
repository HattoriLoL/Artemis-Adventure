extends Control
## Minigame "reiniciar terminal": memorizar e repetir a sequência de 4 disjuntores.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const CINZA := Color("#577277")
const APAGADO := Color("#10141f")

enum Estado { MOSTRANDO, JOGADOR, ERRO, CONCLUIDO }

var sequencia: Array[int] = [1, 3, 0, 2] # índices de 0 a 3
var passo_demo: int = 0
var passo_jogador: int = 0
var selecionado: int = 0
var estado: Estado = Estado.MOSTRANDO
var timer: float = 0.0
var chave_acesa: int = -1
var demo: bool = false
var t_demo_click: float = 0.0
var e_liberado: bool = false
var mensagem: String = ""

@onready var textos: Control = $Textos
@onready var selecao: ColorRect = $Selecao
@onready var chaves: Array[ColorRect] = [$Chave1, $Chave2, $Chave3, $Chave4]
@onready var luzes: Array[ColorRect] = [$Chave1/Luz1, $Chave2/Luz2, $Chave3/Luz3, $Chave4/Luz4]


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	_gerar_sequencia()
	_iniciar_demonstracao()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE or key_event.is_action_pressed("ui_cancel"):
				cancelou.emit()
				set_process(false)


func _gerar_sequencia() -> void:
	# Sorteia uma permutação aleatória de [0, 1, 2, 3]
	var seq: Array[int] = [0, 1, 2, 3]
	seq.shuffle()
	sequencia = seq


func _iniciar_demonstracao() -> void:
	estado = Estado.MOSTRANDO
	passo_demo = 0
	passo_jogador = 0
	timer = 0.5
	chave_acesa = -1
	t_demo_click = 0.0
	_apagar_luzes()


func _apagar_luzes() -> void:
	for l: ColorRect in luzes:
		l.color = APAGADO


func _process(delta: float) -> void:
	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true

	match estado:
		Estado.MOSTRANDO:
			timer -= delta
			if timer <= 0.0:
				if chave_acesa != -1:
					# Apaga a luz que estava acesa e dá um intervalo curto
					chave_acesa = -1
					_apagar_luzes()
					timer = 0.2
				else:
					if passo_demo < sequencia.size():
						chave_acesa = sequencia[passo_demo]
						luzes[chave_acesa].color = AMARELO
						passo_demo += 1
						timer = 0.5
					else:
						# Terminou de mostrar: passa para o jogador
						estado = Estado.JOGADOR
						passo_jogador = 0
						_apagar_luzes()

		Estado.JOGADOR:
			if demo:
				_jogar_sozinho(delta)
			else:
				_controles_jogador()

		Estado.ERRO:
			timer -= delta
			if timer <= 0.0:
				_iniciar_demonstracao()

		Estado.CONCLUIDO:
			timer -= delta
			if timer <= 0.0:
				terminou.emit()
				set_process(false)

	selecao.position.x = chaves[selecionado].position.x - 4.0
	textos.queue_redraw()


func _controles_jogador() -> void:
	if Input.is_action_just_pressed("esquerda"):
		selecionado = maxi(0, selecionado - 1)
	elif Input.is_action_just_pressed("direita"):
		selecionado = mini(chaves.size() - 1, selecionado + 1)

	if Input.is_action_just_pressed("usar") and e_liberado:
		_acionar_chave(selecionado)


func _acionar_chave(idx: int) -> void:
	if idx == sequencia[passo_jogador]:
		# Acertou a chave atual
		luzes[idx].color = VERDE
		passo_jogador += 1
		if passo_jogador >= sequencia.size():
			estado = Estado.CONCLUIDO
			timer = 1.0
			mensagem = "SISTEMA REINICIADO"
	else:
		# Errou a ordem
		estado = Estado.ERRO
		timer = 0.9
		for l: ColorRect in luzes:
			l.color = VERMELHO


func _jogar_sozinho(delta: float) -> void:
	t_demo_click += delta
	if t_demo_click >= 0.4:
		t_demo_click = 0.0
		var alvo: int = sequencia[passo_jogador]
		selecionado = alvo
		_acionar_chave(alvo)


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "PAINEL DE DISJUNTORES", 160.0, 32.0, AMARELO)

	for i: int in 4:
		var cx: float = chaves[i].position.x + chaves[i].size.x / 2.0
		Fonte.centralizado(textos, "%d" % (i + 1), cx, 116.0, BRANCO if i == selecionado else CINZA)

	match estado:
		Estado.MOSTRANDO:
			Fonte.centralizado(textos, "OBSERVE A SEQUENCIA...", 160.0, 138.0, AMARELO)
		Estado.JOGADOR:
			Fonte.centralizado(textos, "PASSO %d/4: ACIONE NA ORDEM" % (passo_jogador + 1), 160.0, 138.0, BRANCO)
		Estado.ERRO:
			Fonte.centralizado(textos, "SEQUENCIA INCORRETA! REINICIANDO...", 160.0, 138.0, VERMELHO)
		Estado.CONCLUIDO:
			Fonte.centralizado(textos, mensagem, 160.0, 138.0, VERDE, 2)


func _criar_teclas() -> void:
	var teclas: Dictionary = {
		"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP], "baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]
	}
	for acao: String in teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			var keys: Array = teclas[acao]
			for k: Key in keys:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(acao, ev)
