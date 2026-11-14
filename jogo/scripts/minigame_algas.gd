extends Control
## Minigame "cuidar das algas": manter os 2 tubos na faixa de fotossíntese por 2 segundos.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERDE_ALGA := Color("#468232")
const CINZA := Color("#577277")

const ALTURA_TUBO := 66.0
const FAIXAS := [[0.45, 0.75], [0.35, 0.65]]
const TEMPO_OK := 2.0

var niveis: Array[float] = [0.20, 0.85]
var selecionado := 0
var tempo_estavel := 0.0
var demo := false
var t_demo := 0.0
var acabou := false
var mensagem := ""

@onready var textos: Control = $Textos
@onready var selecao: ColorRect = $Selecao
@onready var tubos: Array[ColorRect] = [$TuboA, $TuboB]


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	_atualizar_visual()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancelou.emit()
			set_process(false)


func _process(delta: float) -> void:
	if acabou:
		return

	if demo:
		_jogar_sozinho(delta)
	else:
		_controles(delta)

	var todos_ok := true
	for i in 2:
		if niveis[i] < FAIXAS[i][0] or niveis[i] > FAIXAS[i][1]:
			todos_ok = false
			break

	if todos_ok:
		tempo_estavel += delta
		if tempo_estavel >= TEMPO_OK:
			_terminar("BIORREATORES EM EQUILIBRIO")
	else:
		tempo_estavel = 0.0

	_atualizar_visual()
	textos.queue_redraw()


func _controles(delta: float) -> void:
	if Input.is_action_just_pressed("esquerda"):
		selecionado = 0
	elif Input.is_action_just_pressed("direita"):
		selecionado = 1

	var ajuste: float = Input.get_axis("baixo", "cima")
	if ajuste != 0.0:
		niveis[selecionado] = clampf(niveis[selecionado] + ajuste * 0.50 * delta, 0.0, 1.0)


func _jogar_sozinho(delta: float) -> void:
	t_demo += delta
	if t_demo >= 0.35:
		t_demo = 0.0
		for i in 2:
			var centro: float = (FAIXAS[i][0] + FAIXAS[i][1]) / 2.0
			if absf(niveis[i] - centro) > 0.05:
				selecionado = i
				break

	var alvo: float = (FAIXAS[selecionado][0] + FAIXAS[selecionado][1]) / 2.0
	niveis[selecionado] = move_toward(niveis[selecionado], alvo, 0.50 * delta)


func _atualizar_visual() -> void:
	selecao.position.x = tubos[selecionado].position.x - 4
	for i in 2:
		var alga_node: ColorRect = tubos[i].get_node("Algas")
		var h: float = roundf(niveis[i] * ALTURA_TUBO)
		alga_node.size.y = h
		alga_node.position.y = ALTURA_TUBO - h
		var na_faixa: bool = niveis[i] >= FAIXAS[i][0] and niveis[i] <= FAIXAS[i][1]
		alga_node.color = VERDE if na_faixa else VERDE_ALGA


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "BIORREATORES DE ALGAS", 160, 32, AMARELO)

	var nomes: Array[String] = ["TUBO A", "TUBO B"]
	for i in 2:
		var cx: float = tubos[i].position.x + tubos[i].size.x / 2.0
		var na_faixa: bool = niveis[i] >= FAIXAS[i][0] and niveis[i] <= FAIXAS[i][1]
		Fonte.centralizado(textos, nomes[i], cx, 122, VERDE if na_faixa else (BRANCO if i == selecionado else CINZA))

	if acabou:
		Fonte.centralizado(textos, mensagem, 160, 138, VERDE, 2)
		return

	Fonte.centralizado(textos, "ESQ/DIR ESCOLHE  |  CIMA/BAIXO REGULA", 160, 138, BRANCO)


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
