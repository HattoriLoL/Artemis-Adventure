extends Control
## Minigame "calibrar as baterias" (CALIBRATE THE BATTERIES), no banco de baterias da Sala de Energia: um ponteiro vai e
## volta no mostrador; apertar E com ele na faixa verde calibra a bateria da vez (3 baterias, o ponteiro acelera a
## cada uma). Fora da faixa, o mostrador pisca vermelho, a bateria solta faíscas e o jogador tenta de novo.
## Erros (taxa_erro) diminuem o que a tarefa rende; MAX_ERROS erros perdem a tarefa (sinal falhou). Arte (paleta Apollo) em res://assets/minigames/baterias/; mostrador, cargas, faíscas, moldura e
## texto animados aqui. Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro() e
## a variável `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const TEX_RACK := preload("res://assets/minigames/baterias/rack.png")         # 192x121
const TEX_BATERIA := preload("res://assets/minigames/baterias/bateria.png")   # 23x50

const PRETO := Color("#090a14")
const NOITE := Color("#10141f")
const FUNDO := Color("#151d28")
const AZUL_NOITE := Color("#172038")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const LARANJA := Color("#de9e41")
const LARANJA_ESC := Color("#be772b")
const VERDE_ESC := Color("#25562e")
const VERDE := Color("#468232")
const VERDE_CLARO := Color("#75a743")
const VERDE_LIMA := Color("#a8ca58")
const VINHO := Color("#752438")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const CIANO := Color("#73bed3")
const CIANO_CLARO := Color("#a4dddb")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                  # canto do rack (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# posições dentro do rack
const CENTROS := [69, 96, 123]                   # meio de cada bateria na prateleira
const Y_BATERIA := 39
const VISOR := Rect2(8, 15, 5, 28)               # visor de carga, dentro da bateria
const LED := Vector2(12, 10)                     # luz de estado, dentro da bateria
const BARRA := Rect2(16, 107, 160, 8)            # mostrador da calibração, por cima do console

const BATERIAS := 3
const LARGURA_BARRA := 160.0                     # igual à largura da BARRA
const LARGURA_FAIXA := 24.0
const VELOCIDADES := [70.0, 95.0, 120.0]         # velocidade do ponteiro em cada bateria (pixels por segundo)
const TEMPO_ERRO := 0.3                          # quanto tempo o mostrador fica vermelho depois de um erro
const TEMPO_CARGA := 0.45                        # tempo da carga subindo no visor ao calibrar
const TEMPO_FIM := 1.2
const MAX_ERROS := 6                             # com tantos erros a tarefa é perdida

var demo := false                                # o jogo coloca true no modo demo: o minigame se resolve sozinho
var bateria := 0                                 # bateria atual: 0, 1 ou 2 (3 = acabou)
var ponteiro_x := 0.0
var sentido := 1.0                               # 1 = indo para a direita, -1 = voltando
var faixa_x := 0.0
var t_erro := 0.0
var e_liberado := false                          # só aceita o E depois que o jogador soltar o aperto que abriu
var acabou := false
var t := 0.0
var t_fim := -1.0
var cargas := [0.0, 0.0, 0.0]                    # quanto do visor de cada bateria está cheio (0 a 1)
var t_raio := [0.0, 0.0, 0.0]                    # arco elétrico entre os terminais logo depois de calibrar
var faiscas: Array = []                          # [pos, vel, vida], na tela
var rastro: Array = []                           # posições recentes do ponteiro (o rastro some atrás dele)
var erros := 0                                   # apertos fora da faixa
var perdeu := false                              # errou MAX_ERROS vezes


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	_nova_bateria()


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
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	t_erro = maxf(0.0, t_erro - delta)
	for i in BATERIAS:
		t_raio[i] = maxf(0.0, t_raio[i] - delta)
		if i < bateria and cargas[i] < 1.0:
			cargas[i] = minf(1.0, cargas[i] + delta / TEMPO_CARGA)
	_animar_faiscas(delta)
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
		queue_redraw()
		return
	_mover_ponteiro(delta)
	var apertou := e_liberado and Input.is_action_just_pressed("usar")
	if demo:
		apertou = _ponteiro_na_faixa(6.0)        # no demo, "aperta" sozinho bem no meio da faixa
	if apertou:
		if _ponteiro_na_faixa(0.0):
			_calibrar()
		else:
			_errar()
	queue_redraw()


func _mover_ponteiro(delta: float) -> void:
	# vai e volta: quando chega numa ponta da barra, inverte o sentido
	rastro.push_front(ponteiro_x)
	if rastro.size() > 3:
		rastro.pop_back()
	ponteiro_x += sentido * VELOCIDADES[bateria] * delta
	if ponteiro_x >= LARGURA_BARRA:
		ponteiro_x = LARGURA_BARRA
		sentido = -1.0
	elif ponteiro_x <= 0.0:
		ponteiro_x = 0.0
		sentido = 1.0


## Fração dos apertos que foram erros (os acertos são as baterias calibradas).
func taxa_erro() -> float:
	return erros / maxf(1.0, float(erros + bateria))


func _ponteiro_na_faixa(margem: float) -> bool:
	return ponteiro_x >= faixa_x + margem and ponteiro_x <= faixa_x + LARGURA_FAIXA - margem


func _nova_bateria() -> void:
	faixa_x = randf_range(0.0, LARGURA_BARRA - LARGURA_FAIXA)


func _calibrar() -> void:
	t_raio[bateria] = 0.35
	bateria += 1
	if bateria >= BATERIAS:
		acabou = true
		t_fim = TEMPO_FIM
	else:
		_nova_bateria()


func _errar() -> void:
	t_erro = TEMPO_ERRO
	erros += 1
	if erros >= MAX_ERROS:
		perdeu = true
		acabou = true
		t_fim = TEMPO_FIM
	var topo := _canto_bateria(bateria) + Vector2(11, 1)
	for k in 7:                                   # faíscas saindo dos terminais da bateria da vez
		faiscas.append([topo + Vector2(randf_range(-6, 6), 0), Vector2(randf_range(-45, 45), randf_range(-70, -25)),
			randf_range(0.25, 0.45)])


func _animar_faiscas(delta: float) -> void:
	for f in faiscas:
		f[1].y += 220.0 * delta
		f[0] += f[1] * delta
		f[2] -= delta
	faiscas = faiscas.filter(func(f): return f[2] > 0.0)


func _canto_bateria(i: int) -> Vector2:
	return JANELA + Vector2(CENTROS[i] - floori(TEX_BATERIA.get_width() / 2.0), Y_BATERIA)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "CALIBRATE THE BATTERIES", PAINEL.position.x + PAINEL.size.x / 2.0,
		PAINEL.position.y + 5, AMARELO)
	Fonte.desenhar(self, "%d/%d" % [mini(bateria, BATERIAS), BATERIAS], PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	draw_texture(TEX_RACK, JANELA)
	for i in BATERIAS:
		_bateria(i)
	_mostrador()
	for f in faiscas:
		draw_rect(Rect2(f[0].floor(), Vector2.ONE), AMARELO if f[2] > 0.15 else LARANJA_ESC)
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if perdeu:
		Fonte.centralizado(self, "TOO MANY ERRORS - TASK FAILED", 160, y_txt, VERMELHO_CLARO)
	elif acabou:
		Fonte.centralizado(self, "BATTERIES CALIBRATED!", 160, y_txt, VERDE_LIMA)
	elif t_erro > 0.0:
		Fonte.centralizado(self, "MISSED - TRY AGAIN (%d/%d)" % [erros, MAX_ERROS], 160, y_txt,
			VERMELHO_CLARO)
	else:
		Fonte.centralizado(self, "PRESS E WHEN THE NEEDLE IS ON THE GREEN BAND", 160, y_txt, BRANCO_SUJO)


func _px(p: Vector2, cor: Color) -> void:
	draw_rect(Rect2(p.floor(), Vector2.ONE), cor)


## Uma bateria: o sprite, a carga no visor (vermelha e fraca antes, tremendo na da vez, verde depois de calibrar),
## o LED, a setinha em cima da da vez e o arco elétrico entre os terminais ao calibrar.
func _bateria(i: int) -> void:
	var canto := _canto_bateria(i)
	var tremor := Vector2(1, 0) if i == bateria and t_erro > TEMPO_ERRO - 0.12 and int(t * 40.0) % 2 == 0 else Vector2.ZERO
	draw_texture(TEX_BATERIA, canto + tremor)
	var v := Rect2(canto + tremor + VISOR.position, VISOR.size)
	var calibrada := i < bateria
	var nivel: float
	var cor: Color
	var cor_topo: Color
	if calibrada:
		nivel = cargas[i]
		var pulso := acabou and not perdeu and fmod(t + i * 0.15, 0.6) < 0.3
		cor = VERDE_LIMA if pulso else VERDE_CLARO
		cor_topo = BRANCO if pulso else VERDE_LIMA
	elif i == bateria:
		nivel = 0.35 + 0.12 * sin(t * 13.0) + 0.06 * sin(t * 31.0)   # carga instável, ainda sem calibrar
		cor = LARANJA_ESC
		cor_topo = AMARELO
	else:
		nivel = 0.15
		cor = VINHO
		cor_topo = VERMELHO
	var alto := roundi(nivel * v.size.y)
	if alto > 0:
		draw_rect(Rect2(v.position.x, v.end.y - alto, v.size.x, alto), cor)
		draw_rect(Rect2(v.position.x, v.end.y - alto, v.size.x, 1), cor_topo)
		for y in range(int(v.end.y) - alto + 2, int(v.end.y), 4):     # marcas de nível no visor
			draw_rect(Rect2(v.position.x, y, 1, 1), cor_topo if calibrada else NOITE)
	var cor_led := VERDE_LIMA if calibrada else (AMARELO if i == bateria and fmod(t, 0.5) < 0.25 else VERMELHO_CLARO)
	if i == bateria and t_erro > 0.0:
		cor_led = VERMELHO_CLARO if fmod(t, 0.1) < 0.05 else BRANCO
	_px(canto + tremor + LED, cor_led)
	if i == bateria and not acabou:               # setinha piscando em cima da bateria da vez
		var y := canto.y - 6 + (1 if fmod(t, 0.6) < 0.3 else 0)
		var cx := canto.x + 11
		draw_rect(Rect2(cx - 2, y, 5, 1), AMARELO)
		draw_rect(Rect2(cx - 1, y + 1, 3, 1), AMARELO)
		_px(Vector2(cx, y + 2), AMARELO)
	if t_raio[i] > 0.0:                            # arco elétrico zigue-zague entre os dois terminais
		var a := canto + Vector2(4, 1)
		var x := 0
		while x <= 14:
			var dy := -2 - (randi() % 3)
			_px(a + Vector2(x, dy), CIANO_CLARO if x % 3 != 0 else BRANCO)
			x += 1


## Mostrador: caixa escura com marcas, a faixa verde (sorteada) e o ponteiro com rastro.
func _mostrador() -> void:
	var b := Rect2(JANELA + BARRA.position, BARRA.size)
	draw_rect(b.grow(3), PRETO)
	draw_rect(b.grow(2), CINZA_ESC)
	draw_rect(Rect2(b.position - Vector2(2, 2), Vector2(b.size.x + 4, 1)), METAL)
	draw_rect(b.grow(1), NOITE)
	draw_rect(b, VINHO if t_erro > 0.0 and fmod(t, 0.1) < 0.06 else AZUL_NOITE)
	for x in range(0, int(b.size.x) + 1, 10):     # marcas da escala
		draw_rect(Rect2(b.position + Vector2(x, b.size.y - (3 if x % 40 == 0 else 2)), Vector2(1, 3)), CINZA)
	if perdeu:
		draw_rect(b, VINHO if fmod(t, 0.3) < 0.15 else VERMELHO)
	elif not acabou:
		var f := Rect2(b.position + Vector2(roundf(faixa_x), 0), Vector2(LARGURA_FAIXA, b.size.y))
		var na_faixa := _ponteiro_na_faixa(0.0)
		draw_rect(f, VERDE if na_faixa else VERDE_ESC)
		draw_rect(Rect2(f.position, Vector2(1, f.size.y)), VERDE_LIMA)
		draw_rect(Rect2(f.end.x - 1, f.position.y, 1, f.size.y), VERDE_LIMA)
		draw_rect(Rect2(f.position, Vector2(f.size.x, 1)), VERDE_CLARO if na_faixa else VERDE)
	else:
		draw_rect(b, VERDE_ESC if fmod(t, 0.3) < 0.15 else VERDE)
	var cores_rastro := [CIANO, CINZA, CINZA_ESC]
	for k in range(rastro.size() - 1, -1, -1):    # rastro: as posições de antes, mais apagadas
		if absf(rastro[k] - ponteiro_x) >= 1.0:
			draw_rect(Rect2(b.position + Vector2(roundf(rastro[k]), 1), Vector2(1, b.size.y - 2)), cores_rastro[k])
	var px := b.position.x + roundf(ponteiro_x)
	var cor_ponteiro := VERMELHO_CLARO if t_erro > 0.0 else BRANCO
	draw_rect(Rect2(px, b.position.y - 3, 1, b.size.y + 6), cor_ponteiro)
	draw_rect(Rect2(px - 1, b.position.y - 4, 3, 1), cor_ponteiro)   # cabeça do ponteiro
	draw_rect(Rect2(px - 2, b.position.y - 5, 5, 1), cor_ponteiro)


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
