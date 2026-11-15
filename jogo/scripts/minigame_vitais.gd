extends Control
## Minigame "sinais vitais" (CHECK THE CREW VITALS), nos beliches do Habitat, no dia seguinte à erupção solar: o
## monitor mostra o eletrocardiograma de um tripulante. A onda-alvo (amarela) é a do exame; o jogador ajusta a
## amplitude (W/S) e o ritmo (A/D) da sua onda até as duas casarem por TEMPO_SYNC segundos. São RODADAS ondas, cada uma
## com TEMPO_RODADA segundos; o tempo esgotado conta um erro e MAX_ERROS erros perdem o exame (sinal falhou).
## A ideia e o eletrocardiograma (a forma da onda com P, QRS e T, as rodadas e o casamento de amplitude e ritmo)
## vieram do PR #38 (DKuhn29).
## Arte (paleta Apollo) em res://assets/minigames/vitais/fundo.png (192x121, com a tela do ECG lisa em TELA). Sem
## ela, o minigame desenha uma versão provisória. A grade, as ondas, os números e os textos são desenhados aqui.
## Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const DIR_ARTE := "res://assets/minigames/vitais/"

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const TELA_COR := Color("#10141f")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const VERDE := Color("#468232")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                   # canto do fundo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
const TELA := Rect2(10, 10, 172, 78)              # a tela do ECG dentro do fundo
const BASE_Y := 62.0                               # linha de base das ondas (dentro do fundo)
const ESCALA := 34.0
const ROTULO_Y := 92.0                             # AMP e RATE embaixo da tela
const BOTAO_AMP := Vector2(73, 98)                 # botões giratórios do painel (raio 6); a marca gira com o valor
const BOTAO_RITMO := Vector2(119, 98)

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
const BPM_BASE := 20.0                             # o ritmo na tela em batimentos por minuto: 20 + 25 x ritmo
const BPM_POR_FREQ := 25.0                         # (ritmo 1..4 -> 45..120 bpm)
const TEMPO_MSG := 0.8
const TEMPO_FIM := 1.2

var demo := false
var amp := 0.6
var freq := 2.0
var alvo_amp := 1.0
var alvo_freq := 3.0
var rodada := 0                                    # ondas já casadas
var erros := 0
var tempo := TEMPO_RODADA
var sync := 0.0
var mexeu := false
var acabou := false
var perdeu := false
var msg := ""
var msg_cor := BRANCO
var t_msg := 0.0
var t := 0.0
var t_fim := -1.0

var tex_fundo: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	var c := DIR_ARTE + "fundo.png"
	tex_fundo = load(c) if ResourceLoader.exists(c) else null
	_nova_onda()


func _input(ev: InputEvent) -> void:
	if acabou or demo:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if BOTAO_X.grow(1).has_point(get_local_mouse_position()):
			cancelou.emit()
	elif ev.is_action_pressed("ui_cancel"):
		cancelou.emit()


func _process(delta: float) -> void:
	t += delta
	if not acabou:
		if t_msg > 0.0:
			t_msg -= delta
		else:
			_jogar(delta)
	else:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
	queue_redraw()


func _jogar(delta: float) -> void:
	if demo:
		amp = move_toward(amp, alvo_amp, VEL_AMP * delta)
		freq = move_toward(freq, alvo_freq, VEL_FREQ * delta)
	else:
		var v := Input.get_vector("esquerda", "direita", "cima", "baixo")
		if v != Vector2.ZERO:
			mexeu = true
		freq += v.x * VEL_FREQ * delta
		amp -= v.y * VEL_AMP * delta
	amp = clampf(amp, AMP_MIN, AMP_MAX)
	freq = clampf(freq, FREQ_MIN, FREQ_MAX)
	tempo -= delta
	if sincronizado():
		sync += delta
	else:
		sync = maxf(0.0, sync - PERDA_SYNC * delta)
	if sync >= TEMPO_SYNC:
		rodada += 1
		if rodada >= RODADAS:
			acabou = true
			t_fim = TEMPO_FIM
			_mensagem("VITALS SYNCED!", VERDE_LIMA)
		else:
			_mensagem("WAVE LOCKED", VERDE_LIMA)
			_nova_onda()
	elif tempo <= 0.0:
		erros += 1
		if erros >= MAX_ERROS:
			acabou = true
			perdeu = true
			t_fim = TEMPO_FIM + 0.6
			_mensagem("SIGNAL LOST - EXAM FAILED", VERMELHO_CLARO)
		else:
			_mensagem("TIME OUT (%d/%d)" % [erros, MAX_ERROS], VERMELHO_CLARO)
			_nova_onda()


func sincronizado() -> bool:
	return absf(amp - alvo_amp) <= TOL_AMP and absf(freq - alvo_freq) <= TOL_FREQ


func _nova_onda() -> void:
	sync = 0.0
	tempo = TEMPO_RODADA
	alvo_amp = snappedf(randf_range(0.3, AMP_MAX), 0.1)
	alvo_freq = snappedf(randf_range(FREQ_MIN, FREQ_MAX), 0.1)
	while sincronizado():
		alvo_amp = snappedf(randf_range(0.3, AMP_MAX), 0.1)
		alvo_freq = snappedf(randf_range(FREQ_MIN, FREQ_MAX), 0.1)


func _mensagem(texto: String, cor: Color) -> void:
	msg = texto
	msg_cor = cor
	t_msg = TEMPO_MSG


## Fração das ondas perdidas por tempo entre todas as ondas jogadas.
func taxa_erro() -> float:
	return erros / maxf(1.0, float(erros + rodada))


## Já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como falha).
func comecou() -> bool:
	return mexeu or erros > 0 or rodada > 0


# ---------------------------------------------------------------- o eletrocardiograma (do PR #38)
func _pico(x: float, centro: float, largura: float) -> float:
	return exp(-pow(x - centro, 2.0) / (2.0 * largura * largura))


## A forma de um batimento: onda P, complexo QRS e onda T; `f` batimentos na largura da tela.
func _ecg(x: float, a: float, f: float) -> float:
	var p := fposmod(x * f, 1.0)
	var v := 0.12 * _pico(p, 0.20, 0.05)
	v -= 0.15 * _pico(p, 0.37, 0.02)
	v += 1.00 * _pico(p, 0.42, 0.025)
	v -= 0.25 * _pico(p, 0.47, 0.025)
	v += 0.20 * _pico(p, 0.70, 0.07)
	return v * a


func _tracar(a: float, f: float, cor: Color, esp: int) -> void:
	var larg := int(TELA.size.x)
	var antes := 0
	for x in larg:
		var y := int(round(BASE_Y - _ecg(float(x) / larg, a, f) * ESCALA))
		if x == 0:
			antes = y
		var topo := mini(y, antes) - esp
		var base := maxi(y, antes) + esp
		draw_rect(Rect2(JANELA + Vector2(TELA.position.x + x, topo), Vector2(1, base - topo + 1)), cor)
		antes = y


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "CHECK THE CREW VITALS", PAINEL.position.x + PAINEL.size.x / 2.0,
		PAINEL.position.y + 5, AMARELO)
	Fonte.desenhar(self, "%d/%d" % [rodada, RODADAS], PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	if tex_fundo:
		draw_texture(tex_fundo, JANELA)
	else:
		_fundo_provisorio()
	_tela()
	_rotulos()
	_barra_sync()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if t_msg > 0.0 or acabou:
		Fonte.centralizado(self, msg, 160, y_txt, msg_cor)
	else:
		Fonte.centralizado(self, "W/S: AMPLITUDE   A/D: RATE", 160, y_txt, BRANCO_SUJO)


## A tela do ECG: grade de monitor, linha de base, a onda-alvo (faixa amarela) e a do jogador por cima, os batimentos
## por minuto e o tempo que resta.
func _tela() -> void:
	var r := Rect2(JANELA + TELA.position, TELA.size)
	if not tex_fundo:
		draw_rect(r, TELA_COR)
	for x in range(0, int(TELA.size.x), 12):
		draw_rect(Rect2(r.position + Vector2(x, 0), Vector2(1, TELA.size.y)), Color(VERDE, 0.18))
	for y in range(0, int(TELA.size.y), 12):
		draw_rect(Rect2(r.position + Vector2(0, y), Vector2(TELA.size.x, 1)), Color(VERDE, 0.18))
	draw_rect(Rect2(JANELA + Vector2(TELA.position.x, BASE_Y), Vector2(TELA.size.x, 1)), Color(BRANCO, 0.12))
	_tracar(alvo_amp, alvo_freq, AMARELO.darkened(0.4), 1)
	var cor := VERDE_LIMA if sincronizado() else BRANCO
	if acabou and perdeu:
		cor = VERMELHO_CLARO
	_tracar(amp, freq, cor, 0)
	Fonte.desenhar(self, "HR %d" % roundi(BPM_BASE + freq * BPM_POR_FREQ), r.position + Vector2(4, 4), cor)
	Fonte.desenhar(self, "TARGET %d" % roundi(BPM_BASE + alvo_freq * BPM_POR_FREQ), r.position + Vector2(4, 12),
		AMARELO.darkened(0.2))
	var tt := "%dS" % maxi(0, ceili(tempo))
	Fonte.desenhar(self, tt, r.position + Vector2(TELA.size.x - 4 - Fonte.largura(tt), 4),
		VERMELHO_CLARO if tempo < 4.0 and fmod(t, 0.5) < 0.3 else BRANCO_SUJO)
	var e := "ERRORS %d/%d" % [erros, MAX_ERROS]
	Fonte.desenhar(self, e, r.position + Vector2(TELA.size.x - 4 - Fonte.largura(e), 12),
		VERMELHO_CLARO if erros > 0 else BRANCO_SUJO)


## Os rótulos dos dois botões giratórios do painel, com o valor do jogador, e a marca de cada botão girando junto.
func _rotulos() -> void:
	_marca(BOTAO_AMP, inverse_lerp(AMP_MIN, AMP_MAX, amp))
	_marca(BOTAO_RITMO, inverse_lerp(FREQ_MIN, FREQ_MAX, freq))
	Fonte.desenhar(self, "AMP %.1f" % amp, JANELA + Vector2(12, ROTULO_Y), BRANCO_SUJO)
	var tx := "RATE %.1f" % freq
	Fonte.desenhar(self, tx, JANELA + Vector2(180 - Fonte.largura(tx), ROTULO_Y), BRANCO_SUJO)


## A marca de um botão giratório: de -135 graus (mínimo) a +135 graus (máximo), com 0 apontando para cima.
func _marca(c: Vector2, f: float) -> void:
	var a := deg_to_rad(lerpf(-135.0, 135.0, clampf(f, 0.0, 1.0)))
	var d := Vector2(sin(a), -cos(a))
	var centro := JANELA + c + Vector2(0.5, 0.5)
	if tex_fundo:                                   # cobre a marca fixa da arte (para cima) com o miolo do botão
		draw_circle(centro, 3.5, CINZA_ESC)
	for k in range(1, 5):
		draw_rect(Rect2((centro + d * k).floor(), Vector2.ONE), AMARELO if k > 2 else BRANCO_SUJO)


## Quanto falta para travar a onda (casada por TEMPO_SYNC segundos).
func _barra_sync() -> void:
	var r := Rect2(JANELA + Vector2(8, TAM_JANELA.y - 7), Vector2(TAM_JANELA.x - 16, 4))
	draw_rect(r.grow(1), PRETO)
	draw_rect(r, CINZA_ESC)
	var f := 1.0 if (acabou and not perdeu) else clampf(sync / TEMPO_SYNC, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * f), r.size.y)), VERDE_LIMA if sincronizado() else AMARELO)


func _fundo_provisorio() -> void:
	draw_rect(Rect2(JANELA, TAM_JANELA), CINZA)
	draw_rect(Rect2(JANELA + TELA.position - Vector2(3, 3), TELA.size + Vector2(6, 6)), CINZA_ESC)
	draw_rect(Rect2(JANELA + Vector2(8, 89), Vector2(176, 18)), CINZA_ESC)
	draw_circle(JANELA + Vector2(70, 98), 4.0, METAL)
	draw_circle(JANELA + Vector2(122, 98), 4.0, METAL)


func _moldura() -> void:
	var p := PAINEL
	draw_rect(p, PRETO)
	draw_rect(p.grow(-1), CINZA)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(p.size.x - 2, 1)), METAL_CLARO)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(1, p.size.y - 2)), METAL)
	draw_rect(Rect2(p.position + Vector2(2, p.size.y - 2), Vector2(p.size.x - 3, 1)), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(p.size.x - 2, 2), Vector2(1, p.size.y - 3)), CINZA_ESC)
	for c in [Vector2(3, 3), Vector2(p.size.x - 6, 3), Vector2(3, p.size.y - 6), Vector2(p.size.x - 6, p.size.y - 6)]:
		draw_rect(Rect2(p.position + c, Vector2(3, 3)), METAL)
		draw_rect(Rect2(p.position + c + Vector2.ONE, Vector2.ONE), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(8, 3), Vector2(p.size.x - 16, 10)), FUNDO)


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
