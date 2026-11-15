extends Control

signal terminou

const Fonte = preload("res://scripts/fonte.gd")

const TEXTO := Color("#ebede9")
const CERTO := Color("#a8ca58")
const ERRO := Color("#cf573c")
const DESTAQUE := Color("#e8c170")

const RODADAS := 3
const MAX_ERROS := 3
const TEMPO_RODADA := 12.0
const TEMPO_SYNC := 2.0
const PERDA_SYNC := 1.0
const TOL_AMP := 0.08
const TOL_FREQ := 0.15
const VEL_AMP := 0.5
const VEL_FREQ := 1.0
const AMP_MIN := 0.2
const AMP_MAX := 1.0
const FREQ_MIN := 1.0
const FREQ_MAX := 4.0

const LARG := 280
const CENTRO_Y := 52
const ESCALA := 38.0

var demo := false

var amp := 0.6
var freq := 2.0
var alvo_amp := 1.0
var alvo_freq := 3.0
var rodada := 0
var erros := 0
var tempo := TEMPO_RODADA
var sync := 0.0
var msg := ""
var msg_cor := TEXTO
var msg_t := 0.0
var fim := false

@onready var grafico: Control = $Grafico
@onready var cheia: ColorRect = $Cheia
@onready var textos: Control = $Textos


func _ready() -> void:
	_criar_teclas()
	grafico.draw.connect(_desenhar_grafico)
	textos.draw.connect(_desenhar_textos)
	_nova_onda()


func _process(delta: float) -> void:
	if not fim:
		if msg_t > 0.0:
			msg_t -= delta
		else:
			_jogar(delta)
	cheia.size.x = int(200.0 * sync / TEMPO_SYNC)
	cheia.color = CERTO if _sincronizado() else DESTAQUE
	grafico.queue_redraw()
	textos.queue_redraw()


func _jogar(delta: float) -> void:
	if demo:
		amp = move_toward(amp, alvo_amp, VEL_AMP * delta)
		freq = move_toward(freq, alvo_freq, VEL_FREQ * delta)
	else:
		var v := Input.get_vector("esquerda", "direita", "cima", "baixo")
		freq += v.x * VEL_FREQ * delta
		amp -= v.y * VEL_AMP * delta
	amp = clampf(amp, AMP_MIN, AMP_MAX)
	freq = clampf(freq, FREQ_MIN, FREQ_MAX)

	tempo -= delta
	if _sincronizado():
		sync += delta
	else:
		sync = maxf(0.0, sync - PERDA_SYNC * delta)

	if sync >= TEMPO_SYNC:
		rodada += 1
		if rodada >= RODADAS:
			_finalizar(false)
		else:
			_mensagem("WAVE LOCKED", CERTO)
			_nova_onda()
	elif tempo <= 0.0:
		erros += 1
		if erros >= MAX_ERROS:
			_finalizar(true)
		else:
			_mensagem("TIME OUT", ERRO)
			_nova_onda()


func _sincronizado() -> bool:
	return absf(amp - alvo_amp) <= TOL_AMP and absf(freq - alvo_freq) <= TOL_FREQ


func _nova_onda() -> void:
	sync = 0.0
	tempo = TEMPO_RODADA
	alvo_amp = snappedf(randf_range(0.3, AMP_MAX), 0.1)
	alvo_freq = snappedf(randf_range(FREQ_MIN, FREQ_MAX), 0.1)
	while _sincronizado():
		alvo_amp = snappedf(randf_range(0.3, AMP_MAX), 0.1)
		alvo_freq = snappedf(randf_range(FREQ_MIN, FREQ_MAX), 0.1)


func _mensagem(texto: String, cor: Color) -> void:
	msg = texto
	msg_cor = cor
	msg_t = 0.8


func _finalizar(perdeu: bool) -> void:
	fim = true
	if perdeu:
		msg = "SIGNAL LOST"
		msg_cor = ERRO
	else:
		msg = "VITALS SYNCED"
		msg_cor = CERTO
	var taxa_erro := erros / float(erros + RODADAS)
	await get_tree().create_timer(0.5).timeout
	terminou.emit()


func _pico(x: float, centro: float, largura: float) -> float:
	return exp(-pow(x - centro, 2.0) / (2.0 * largura * largura))


func _ecg(x: float, a: float, f: float) -> float:
	var p := fposmod(x * f, 1.0)
	var v := 0.12 * _pico(p, 0.20, 0.05)
	v -= 0.15 * _pico(p, 0.37, 0.02)
	v += 1.00 * _pico(p, 0.42, 0.025)
	v -= 0.25 * _pico(p, 0.47, 0.025)
	v += 0.20 * _pico(p, 0.70, 0.07)
	return v * a


func _alturas(a: float, f: float) -> PackedInt32Array:
	var ys := PackedInt32Array()
	for x in range(LARG):
		ys.append(CENTRO_Y - int(round(_ecg(float(x) / LARG, a, f) * ESCALA)))
	return ys


func _tracar(a: float, f: float, cor: Color, esp: int) -> void:
	var ys := _alturas(a, f)
	for x in range(LARG):
		var y0 := ys[x]
		var y1 := ys[maxi(x - 1, 0)]
		var topo := mini(y0, y1) - esp
		var base := maxi(y0, y1) + esp
		grafico.draw_rect(Rect2(x, topo, 1, base - topo + 1), cor)


func _desenhar_grafico() -> void:
	grafico.draw_rect(Rect2(0, CENTRO_Y, LARG, 1), Color(TEXTO, 0.15))   # linha de base
	_tracar(alvo_amp, alvo_freq, DESTAQUE.darkened(0.4), 1)   # alvo: faixa de 3 px, mais escura
	_tracar(amp, freq, CERTO if _sincronizado() else TEXTO, 0)   # jogador: 1 px, por cima


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "SYNC THE VITALS", 160, 8, TEXTO)
	Fonte.centralizado(textos, "UP DOWN: AMPLITUDE   LEFT RIGHT: RATE", 160, 126, TEXTO)
	Fonte.desenhar(textos, "WAVE " + str(mini(rodada + 1, RODADAS)) + "/" + str(RODADAS), Vector2(24, 156), TEXTO)
	Fonte.centralizado(textos, "TIME " + str(maxi(0, ceili(tempo))), 160, 156, TEXTO)
	var e := "ERRORS " + str(erros) + "/" + str(MAX_ERROS)
	Fonte.desenhar(textos, e, Vector2(296 - 4 * e.length(), 156), ERRO if erros > 0 else TEXTO)
	if msg_t > 0.0 or fim:
		Fonte.centralizado(textos, msg, 160, 70, msg_cor)


func _criar_teclas() -> void:
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
