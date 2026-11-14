extends Control
## Minigame do painel solar: o painel começa girado e o jogador gira até alinhá-lo na horizontal ou na vertical.

signal terminou

const Fonte = preload("res://scripts/fonte.gd")
const TEXTO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const CINZA := Color("#394a50")
const AZUL := Color("#4f8fba")

const VELOCIDADE_GIRO := 90.0    # graus por segundo
const TOLERANCIA := 4.0          # margem de erro, em graus (para cada lado)
const TEMPO_SEGURAR := 0.8       # quanto tempo precisa ficar alinhado
const FOLGA_INICIAL := 20.0      # o painel nunca nasce a menos de 20° de um alinhamento

var demo := false                # no modo demo, o minigame se resolve sozinho
var angulo := 0.0                # rotação atual do painel, entre -180 e 180
var t_alinhado := 0.0
var acabou := false
var mensagem := ""

var alvo := 0.0     # 0 = horizontal, 90 = vertical
var moldura: Control
@onready var textos: Control = $Textos
@onready var panel: Control = $Panel


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	panel.pivot_offset = panel.size / 2.0                 # gira pelo centro
	moldura = Control.new()
	moldura.size = panel.size
	moldura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(moldura)
	moldura.draw.connect(_desenhar_moldura)
	# sorteia um ângulo qualquer, mas longe de 0/90/180/-90
	alvo = 0.0 if randf() < 0.5 else 90.0
	while _erro() < FOLGA_INICIAL:
		angulo = randf_range(-180.0, 180.0)
	_atualizar_visual()


func _process(delta: float) -> void:
	if acabou:
		return

	var giro := Input.get_axis("esquerda", "direita")
	if demo:
		giro = signf(_diferenca()) if _erro() > 1.0 else 0.0
	angulo = wrapf(angulo + giro * VELOCIDADE_GIRO * delta, -180.0, 180.0)

	if _erro() <= TOLERANCIA:
		t_alinhado += delta
		if t_alinhado >= TEMPO_SEGURAR:
			_terminar("PAINEL ALINHADO")
	else:
		t_alinhado = 0.0

	_atualizar_visual()


func _diferenca() -> float:
	# quanto falta (com sinal) para o alvo mais próximo; 180° conta como igual a 0°
	return wrapf(alvo - angulo, -90.0, 90.0)


func _erro() -> float:
	return absf(_diferenca())


func _atualizar_visual() -> void:
	panel.rotation_degrees = angulo
	moldura.queue_redraw()
	textos.queue_redraw()

func _desenhar_moldura() -> void:
	var cor := AZUL if _erro() <= TOLERANCIA else CINZA
	var m := 4.0   # distância da borda do painel até a linha
	moldura.draw_rect(Rect2(m, m, panel.size.x - m * 2.0, panel.size.y - m * 2.0), cor, false, 2.0)

func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "Painel Solar", 160, 36, AMARELO)
	if acabou:
		Fonte.centralizado(textos, mensagem, 160, 132, VERDE)
		return
	Fonte.centralizado(textos, "A / D giram o painel até alinhá-lo", 160, 132, AMARELO)
	# barra de progresso enquanto o painel está alinhado
	textos.draw_rect(Rect2(110, 150, 100, 4), CINZA)
	textos.draw_rect(Rect2(110, 150, 100.0 * (t_alinhado / TEMPO_SEGURAR), 4), VERDE)


func _terminar(texto: String) -> void:
	acabou = true
	mensagem = texto
	_atualizar_visual()
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
