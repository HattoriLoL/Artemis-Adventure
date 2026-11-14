extends Control
## Minigame "balancear energia": ajustar 3 canais de carga nas faixas certas por 2s.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const CINZA := Color("#577277")

const NOMES: Array[String] = ["SUP", "BASE", "ESC"]
const ALTURA_CANAL: float = 66.0
const FAIXAS: Array = [[0.40, 0.65], [0.50, 0.75], [0.35, 0.60]]
const TEMPO_OK: float = 2.0

var niveis: Array[float] = [0.15, 0.85, 0.20]
var selecionado: int = 0
var tempo_estavel: float = 0.0
var demo: bool = false
var t_demo: float = 0.0
var acabou: bool = false
var mensagem: String = ""

@onready var textos: Control = $Textos
@onready var selecao: ColorRect = $Selecao
@onready var canais: Array[ColorRect] = [$Canal1, $Canal2, $Canal3]


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	_atualizar_visual()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			cancelou.emit()
			set_process(false)


func _process(delta: float) -> void:
	if acabou:
		return

	if demo:
		_jogar_sozinho(delta)
	else:
		_controles(delta)

	var todos_ok: bool = true
	for i: int in 3:
		var faixa: Array = FAIXAS[i] as Array
		var min_val: float = float(faixa[0])
		var max_val: float = float(faixa[1])
		if niveis[i] < min_val or niveis[i] > max_val:
			todos_ok = false
			break

	if todos_ok:
		tempo_estavel += delta
		if tempo_estavel >= TEMPO_OK:
			_terminar("REDE ESTABILIZADA")
	else:
		tempo_estavel = 0.0

	_atualizar_visual()
	textos.queue_redraw()


func _controles(delta: float) -> void:
	if Input.is_action_just_pressed("esquerda"):
		selecionado = maxi(0, selecionado - 1)
	elif Input.is_action_just_pressed("direita"):
		selecionado = mini(canais.size() - 1, selecionado + 1)

	var ajuste: float = Input.get_axis("baixo", "cima")
	if ajuste != 0.0:
		niveis[selecionado] = clampf(niveis[selecionado] + ajuste * 0.45 * delta, 0.0, 1.0)


func _jogar_sozinho(delta: float) -> void:
	t_demo += delta
	if t_demo >= 0.3:
		t_demo = 0.0
		for i: int in 3:
			var faixa: Array = FAIXAS[i] as Array
			var centro: float = (float(faixa[0]) + float(faixa[1])) / 2.0
			if absf(niveis[i] - centro) > 0.05:
				selecionado = i
				break

	var faixa_sel: Array = FAIXAS[selecionado] as Array
	var alvo: float = (float(faixa_sel[0]) + float(faixa_sel[1])) / 2.0
	niveis[selecionado] = move_toward(niveis[selecionado], alvo, 0.45 * delta)


func _atualizar_visual() -> void:
	selecao.position.x = canais[selecionado].position.x - 4.0
	for i: int in 3:
		var canal: ColorRect = canais[i]
		var nivel_node: ColorRect = canal.get_node("Nivel") as ColorRect
		var h: float = roundf(niveis[i] * ALTURA_CANAL)
		nivel_node.size.y = h
		nivel_node.position.y = ALTURA_CANAL - h
		var faixa: Array = FAIXAS[i] as Array
		var na_faixa: bool = niveis[i] >= float(faixa[0]) and niveis[i] <= float(faixa[1])
		nivel_node.color = VERDE if na_faixa else AMARELO


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "DISTRIBUICAO ELETRICA", 160.0, 32.0, AMARELO)

	for i: int in 3:
		var canal: ColorRect = canais[i]
		var cx: float = canal.position.x + canal.size.x / 2.0
		var faixa: Array = FAIXAS[i] as Array
		var na_faixa: bool = niveis[i] >= float(faixa[0]) and niveis[i] <= float(faixa[1])
		var cor_texto: Color = VERDE if na_faixa else (BRANCO if i == selecionado else CINZA)
		Fonte.centralizado(textos, NOMES[i], cx, 122.0, cor_texto)

	if acabou:
		Fonte.centralizado(textos, mensagem, 160.0, 138.0, VERDE, 2)
		return

	Fonte.centralizado(textos, "ESQ/DIR ESCOLHE  |  CIMA/BAIXO REGULA", 160.0, 138.0, BRANCO)


func _terminar(texto: String) -> void:
	acabou = true
	mensagem = texto
	textos.queue_redraw()
	await get_tree().create_timer(1.0).timeout
	terminou.emit()


func _criar_teclas() -> void:
	var teclas: Dictionary = {
		"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP], "baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]
	}
	for acao: String in teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			var eventos: Array = teclas[acao] as Array
			for k: Variant in eventos:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = int(k) as Key
				InputMap.action_add_event(acao, ev)
