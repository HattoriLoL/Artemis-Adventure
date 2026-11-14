extends Control
## Minigame "ajustar oxigênio / suporte à vida": calibrar O2 e CO2 nas faixas por 2.5s.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO: Color = Color("#ebede9")
const AMARELO: Color = Color("#e8c170")
const VERDE: Color = Color("#a8ca58")
const AZUL_O2: Color = Color("#73bed3")
const LARANJA_CO2: Color = Color("#d77643")
const CINZA: Color = Color("#577277")

const ALTURA_COLUNA: float = 66.0
const LARGURA_BARRA: float = 120.0
const FAIXAS: Array = [[0.55, 0.85], [0.15, 0.45]]
const TEMPO_NECESSARIO: float = 2.5

var niveis: Array[float] = [0.25, 0.70] # O2 começa baixo, CO2 começa alto
var selecionado: int = 0
var tempo_estavel: float = 0.0
var demo: bool = false
var t_demo: float = 0.0
var acabou: bool = false
var mensagem: String = ""

@onready var textos: Control = $Textos
@onready var selecao: ColorRect = $Selecao
@onready var colunas: Array[ColorRect] = [$ColunaO2, $ColunaCO2]
@onready var barra_estavel: ColorRect = $BarraEstavel


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	_atualizar_visual()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
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
	for i: int in 2:
		var faixa: Array = FAIXAS[i] as Array
		var min_val: float = float(faixa[0])
		var max_val: float = float(faixa[1])
		if niveis[i] < min_val or niveis[i] > max_val:
			todos_ok = false
			break

	if todos_ok:
		tempo_estavel += delta
		if tempo_estavel >= TEMPO_NECESSARIO:
			_terminar("MISTURA DE AR ESTABILIZADA")
	else:
		tempo_estavel = maxf(0.0, tempo_estavel - delta * 0.5)

	var progresso: float = clampf(tempo_estavel / TEMPO_NECESSARIO, 0.0, 1.0)
	barra_estavel.size.x = progresso * LARGURA_BARRA

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
		for i: int in 2:
			var faixa_i: Array = FAIXAS[i] as Array
			var centro: float = (float(faixa_i[0]) + float(faixa_i[1])) / 2.0
			if absf(niveis[i] - centro) > 0.05:
				selecionado = i
				break

	var faixa_sel: Array = FAIXAS[selecionado] as Array
	var alvo: float = (float(faixa_sel[0]) + float(faixa_sel[1])) / 2.0
	niveis[selecionado] = move_toward(niveis[selecionado], alvo, 0.50 * delta)


func _atualizar_visual() -> void:
	selecao.position.x = colunas[selecionado].position.x - 4.0
	for i: int in 2:
		var nivel_node: ColorRect = colunas[i].get_node("Nivel") as ColorRect
		var h: float = roundf(niveis[i] * ALTURA_COLUNA)
		nivel_node.size.y = h
		nivel_node.position.y = ALTURA_COLUNA - h
		var faixa_i: Array = FAIXAS[i] as Array
		var na_faixa: bool = niveis[i] >= float(faixa_i[0]) and niveis[i] <= float(faixa_i[1])
		nivel_node.color = VERDE if na_faixa else (AZUL_O2 if i == 0 else LARANJA_CO2)


func _desenhar_textos() -> void:
	textos.draw_rect(Rect2(99, 129, LARGURA_BARRA + 2, 6), Color(0.1, 0.13, 0.18, 0.9))

	Fonte.centralizado(textos, "CALIBRADOR DE OXIGENIO", 160.0, 32.0, AMARELO)

	var nomes: Array[String] = ["O2 (AR)", "CO2 (GAS)"]
	for i: int in 2:
		var cx: float = colunas[i].position.x + colunas[i].size.x / 2.0
		var faixa_i: Array = FAIXAS[i] as Array
		var na_faixa: bool = niveis[i] >= float(faixa_i[0]) and niveis[i] <= float(faixa_i[1])
		var cor_texto: Color = VERDE if na_faixa else (BRANCO if i == selecionado else CINZA)
		Fonte.centralizado(textos, nomes[i], cx, 122.0, cor_texto)

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
		"esquerda": [KEY_A, KEY_LEFT],
		"direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER],
	}
	for acao: String in teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			var lista: Array = teclas[acao] as Array
			for k: Variant in lista:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = k as Key
				InputMap.action_add_event(acao, ev)
