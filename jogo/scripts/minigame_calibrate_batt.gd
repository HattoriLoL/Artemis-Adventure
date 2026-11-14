extends Control
## Minigame "calibrar as baterias": apertar E quando o ponteiro passar na faixa verde, 3 vezes.

signal terminou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const CINZA := Color("#394a50")

const BATERIAS := 3
const LARGURA_BARRA := 160.0             # igual à largura do nó Barra
const LARGURA_FAIXA := 24.0              # igual à largura do nó Faixa
const VELOCIDADES := [70.0, 95.0, 160.0] # velocidade do ponteiro em cada bateria (pixels por segundo)
const TEMPO_ERRO := 0.3                  # quanto tempo a barra fica vermelha depois de um erro

var demo := false                        # o jogo coloca true no modo demo: o minigame se resolve sozinho
var bateria := 0                         # bateria atual: 0, 1 ou 2
var ponteiro_x := 0.0
var sentido := 1.0                       # 1 = indo para a direita, -1 = voltando
var faixa_x := 0.0
var t_erro := 0.0
var e_liberado := false                  # só aceita o E depois que o jogador soltar o aperto que abriu o minigame
var acabou := false
var mensagem := ""

@onready var textos: Control = $Textos
@onready var barra: ColorRect = $Barra
@onready var faixa: ColorRect = $Barra/Faixa
@onready var ponteiro: ColorRect = $Barra/Ponteiro
@onready var luzes := [$Bateria1, $Bateria2, $Bateria3]


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	_nova_bateria()


func _process(delta: float) -> void:
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	if acabou:
		return
	_mover_ponteiro(delta)
	t_erro = maxf(0.0, t_erro - delta)
	var apertou := e_liberado and Input.is_action_just_pressed("usar")
	if demo:
		apertou = _ponteiro_na_faixa(6.0)    # no demo, "aperta" sozinho bem no meio da faixa
	if apertou:
		if _ponteiro_na_faixa(0.0):
			_calibrar()
		else:
			t_erro = TEMPO_ERRO
	_atualizar_visual()


func _mover_ponteiro(delta: float) -> void:
	# vai e volta: quando chega numa ponta da barra, inverte o sentido
	ponteiro_x += sentido * VELOCIDADES[bateria] * delta
	if ponteiro_x >= LARGURA_BARRA:
		ponteiro_x = LARGURA_BARRA
		sentido = -1.0
	elif ponteiro_x <= 0.0:
		ponteiro_x = 0.0
		sentido = 1.0


func _ponteiro_na_faixa(margem: float) -> bool:
	return ponteiro_x >= faixa_x + margem and ponteiro_x <= faixa_x + LARGURA_FAIXA - margem


func _nova_bateria() -> void:
	faixa_x = randf_range(0.0, LARGURA_BARRA - LARGURA_FAIXA)


func _calibrar() -> void:
	luzes[bateria].color = VERDE
	bateria += 1
	if bateria >= BATERIAS:
		_terminar("BATERIAS CALIBRADAS")
	else:
		_nova_bateria()


func _atualizar_visual() -> void:
	faixa.position.x = round(faixa_x)
	ponteiro.position.x = round(ponteiro_x) - 1
	barra.color = VERMELHO if t_erro > 0.0 else CINZA
	textos.queue_redraw()


func _desenhar_textos() -> void:
	if acabou:
		Fonte.centralizado(textos, mensagem, 160, 80, VERDE)
		return
	Fonte.centralizado(textos, "BATERIA %d/%d" % [bateria + 1, BATERIAS], 160, 36, AMARELO)
	Fonte.centralizado(textos, "APERTE E NA FAIXA VERDE", 160, 132, BRANCO)


func _terminar(texto: String) -> void:
	acabou = true
	mensagem = texto
	textos.queue_redraw()
	print("minigame terminou")
	await get_tree().create_timer(0.8).timeout
	terminou.emit()


func _criar_teclas() -> void:
	# para a cena rodar sozinha com F6: no jogo, quem cria as teclas é o mapa
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
