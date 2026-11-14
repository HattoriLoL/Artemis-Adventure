extends Control
## Minigame "preparar refeição": modular o aquecedor com E para manter na faixa por 2.5s.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO: Color = Color("#ebede9")
const AMARELO: Color = Color("#e8c170")
const VERDE: Color = Color("#a8ca58")
const VERMELHO: Color = Color("#cf573c")
const CINZA: Color = Color("#577277")

const ALTURA_TERMOMETRO: float = 70.0
const LARGURA_PREPARO: float = 160.0
const FAIXA_MIN: float = 0.40
const FAIXA_MAX: float = 0.75
const TEMPO_NECESSARIO: float = 2.5

var temp: float = 0.15                         # 0.0 (frio) a 1.0 (muito quente)
var tempo_cozinhando: float = 0.0
var demo: bool = false
var e_liberado: bool = false
var acabou: bool = false
var mensagem: String = ""

@onready var textos: Control = $Textos
@onready var comida: ColorRect = $Prato/Comida
@onready var mercurio: ColorRect = $"Termometro/Mercúrio"
@onready var barra_preparo: ColorRect = $BarraPreparo


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

	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true

	var aquecendo: bool = false
	if demo:
		# Modo demo modula em torno de 0.58 (meio da faixa)
		if temp < 0.58:
			aquecendo = true
	else:
		aquecendo = Input.is_action_pressed("usar") and e_liberado

	if aquecendo:
		temp = minf(1.0, temp + 0.65 * delta)
	else:
		temp = maxf(0.0, temp - 0.35 * delta)

	var na_faixa: bool = temp >= FAIXA_MIN and temp <= FAIXA_MAX
	if na_faixa:
		tempo_cozinhando += delta

	var progresso: float = clampf(tempo_cozinhando / TEMPO_NECESSARIO, 0.0, 1.0)
	barra_preparo.size.x = progresso * LARGURA_PREPARO

	# Comida vai dourando conforme cozinha
	comida.color = Color("#819796").lerp(Color("#e8c170"), progresso)

	_atualizar_visual()

	if tempo_cozinhando >= TEMPO_NECESSARIO:
		_terminar("REFEICAO NUTRITIVA PRONTA")

	textos.queue_redraw()


func _atualizar_visual() -> void:
	var h: float = roundf(temp * ALTURA_TERMOMETRO)
	mercurio.size.y = h
	mercurio.position.y = ALTURA_TERMOMETRO - h


func _desenhar_textos() -> void:
	# Fundo da barra de preparo
	textos.draw_rect(Rect2(79, 129, LARGURA_PREPARO + 2, 6), Color(0.1, 0.13, 0.18, 0.9))

	Fonte.centralizado(textos, "REIDRATADOR TERMICO", 160, 32, AMARELO)

	var na_faixa: bool = temp >= FAIXA_MIN and temp <= FAIXA_MAX
	var cor_temp: Color = VERDE if na_faixa else (VERMELHO if temp > FAIXA_MAX else CINZA)
	var txt_temp: String = "TEMPERATURA IDEAL" if na_faixa else ("MUITO QUENTE!" if temp > FAIXA_MAX else "MUITO FRIO")

	Fonte.centralizado(textos, txt_temp, 160, 118, cor_temp)

	if acabou:
		Fonte.centralizado(textos, mensagem, 160, 138, VERDE, 2)
		return

	Fonte.centralizado(textos, "SEGURE E: AQUECER  |  SOLTE: RESFRIAR", 160, 138, BRANCO)


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
			var lista_teclas: Array = teclas[acao] as Array
			for k: Key in lista_teclas:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(acao, ev)
