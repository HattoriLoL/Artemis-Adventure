extends Control
## Minigame "reabastecer a água" (REFILL THE WATER), no dispensador do Habitat: segurar E abre a torneira e enche o
## galão; soltar com o nível na faixa verde conclui. Soltar antes avisa que falta água (dá para continuar); passar do
## limite transborda e o galão drena até a metade (soltar acima da faixa também drena). Cada vez que passa da faixa é
## um erro (taxa_erro diminui o que a tarefa rende); MAX_ERROS erros perdem a tarefa (sinal falhou).
## Arte (paleta Apollo) em res://assets/minigames/agua/; água, jato, respingos, bolhas, faixa, moldura e texto
## animados aqui. Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro() e `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const TEX_ESTACAO := preload("res://assets/minigames/agua/estacao.png")       # 192x121
const TEX_GALAO := preload("res://assets/minigames/agua/galao.png")           # 37x50
const TEX_BRILHO := preload("res://assets/minigames/agua/galao_brilho.png")   # reflexo do vidro, por cima da água

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const VERDE_ESC := Color("#468232")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const AGUA_FUNDA := Color("#3c5e8b")
const AGUA := Color("#4f8fba")
const AGUA_CLARA := Color("#73bed3")
const AGUA_BRILHO := Color("#a4dddb")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                  # canto da estação (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# posições dentro da estação
const X_JATO := 95                               # coluna do meio do jato (bico da torneira)
const Y_BICO := 44                               # ponta da torneira
const GALAO := Vector2(77, 51)                   # canto do galão, apoiado na grade
const VISOR := Rect2(84, 65, 23, 27)             # vidro do galão (GALAO + 7,14)
const Y_GRADE := 100                             # topo da grade (onde a água transbordada empoça)

const FAIXA_MIN := 0.78
const FAIXA_MAX := 0.95
const ENCHE := 0.40                              # nível por segundo, com a torneira aberta
const DRENA := 0.60                              # nível por segundo, drenando depois de transbordar
const NIVEL_DRENADO := 0.50
const VEL_JATO := 180.0                          # px/s da frente e do fim do jato
const TEMPO_FIM := 1.2
const MAX_ERROS := 3                             # com tantos transbordos a tarefa é perdida

var demo := false
var nivel := 0.0
var e_liberado := false                          # o E que abriu o minigame ainda pode estar apertado
var acabou := false
var transbordou := false
var erros := 0                                   # transbordos
var perdeu := false
var mensagem := ""
var cor_mensagem := AMARELO
var t := 0.0
var t_fim := -1.0
var t_derrame := 0.0                             # água escorrendo pelos lados do galão (logo depois de transbordar)
var poca := 0.0                                  # largura da poça na grade (0 a 1)
var jatos: Array = []                            # trechos de água caindo: [topo, base, aberto]
var gotas: Array = []                            # respingos: [pos, vel]
var bolhas: Array = []                           # bolhas subindo: [pos, vel_y]
var pingos: Array = []                           # pingos caindo pela grade: [pos, vel_y]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()


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
	var enchendo := false
	if not acabou:
		if not e_liberado and not Input.is_action_pressed("usar"):
			e_liberado = true
		if demo:
			if nivel < (FAIXA_MIN + FAIXA_MAX) / 2.0:
				enchendo = true
			elif _jato_parado():
				_verificar_resultado()       # no demo, solta e espera a água assentar antes de conferir
		else:
			enchendo = Input.is_action_pressed("usar") and e_liberado and not transbordou
			if Input.is_action_just_released("usar") and e_liberado and not transbordou:
				_verificar_resultado()
	if enchendo and _caindo_na_agua():
		nivel += ENCHE * delta
		if nivel >= 1.0:
			nivel = 1.0
			t_derrame = 0.9
			_errar("OVERFLOW! DRAINING...")
	if transbordou:
		nivel = maxf(NIVEL_DRENADO, nivel - DRENA * delta)
		if nivel <= NIVEL_DRENADO:
			transbordou = false
			mensagem = ""
	_animar_jato(enchendo and not transbordou, delta)
	_animar_particulas(delta)
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
	queue_redraw()


## Fração das tentativas que passaram da faixa (a tentativa certa é a que conclui).
func taxa_erro() -> float:
	return erros / float(erros + 1)


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça.
func comecou() -> bool:
	return erros > 0 or nivel > 0.0


## Passou da faixa (transbordou ou soltou acima dela): conta um erro e o galão drena até a metade.
func _errar(txt: String) -> void:
	transbordou = true
	erros += 1
	if erros >= MAX_ERROS and not acabou:
		perdeu = true
		acabou = true
		t_fim = TEMPO_FIM + 0.6
		_avisar("TOO MANY SPILLS - TASK FAILED", VERMELHO_CLARO)
	else:
		_avisar("%s (%d/%d)" % [txt, erros, MAX_ERROS], VERMELHO_CLARO)


func _verificar_resultado() -> void:
	if nivel >= FAIXA_MIN and nivel <= FAIXA_MAX:
		acabou = true
		t_fim = TEMPO_FIM
		_avisar("WATER TANK FULL!", VERDE_LIMA)
	elif nivel > FAIXA_MAX:
		_errar("TOO MUCH WATER! DRAINING...")      # soltou acima da faixa sem transbordar
	elif nivel < FAIXA_MIN and nivel > 0.1:
		_avisar("NOT ENOUGH WATER - KEEP FILLING", AMARELO)


func _avisar(txt: String, cor: Color) -> void:
	mensagem = txt
	cor_mensagem = cor


# ---------------------------------------------------------------- água
func _altura_agua() -> int:
	return roundi(clampf(nivel, 0.0, 1.0) * VISOR.size.y)


## y da superfície da água (ou do fundo do visor, com o galão vazio), na estação.
func _superficie() -> float:
	return VISOR.end.y - _altura_agua()


## O jato é feito de trechos: o aberto fica preso no bico e cresce para baixo; ao fechar, o fim também cai.
func _animar_jato(aberto: bool, delta: float) -> void:
	var sup := _superficie()
	if aberto and (jatos.is_empty() or not jatos[-1][2]):
		jatos.append([float(Y_BICO), float(Y_BICO), true])
	elif not aberto and not jatos.is_empty() and jatos[-1][2]:
		jatos[-1][2] = false
	for j in jatos:
		j[1] = minf(j[1] + VEL_JATO * delta, sup)
		if not j[2]:
			j[0] = minf(j[0] + VEL_JATO * delta, sup)
	jatos = jatos.filter(func(j): return j[0] < sup - 0.5)


func _jato_parado() -> bool:
	return jatos.is_empty()


func _caindo_na_agua() -> bool:
	return not jatos.is_empty() and jatos[-1][2] and jatos[-1][1] >= _superficie() - 0.5


func _animar_particulas(delta: float) -> void:
	var sup := _superficie()
	if _caindo_na_agua() and not transbordou:
		if randf() < 30.0 * delta:            # respingos saltando onde o jato bate
			gotas.append([Vector2(X_JATO + randf_range(-1, 1), sup - 1), Vector2(randf_range(-26, 26),
				randf_range(-46, -18))])
		if randf() < 14.0 * delta and _altura_agua() > 4:   # bolhas arrastadas para o fundo, subindo
			bolhas.append([Vector2(X_JATO + randf_range(-4, 4), sup + randf_range(4, minf(14, _altura_agua()))),
				randf_range(-22, -12)])
	for g in gotas:
		g[1].y += 170.0 * delta
		g[0] += g[1] * delta
	gotas = gotas.filter(func(g): return g[0].y <= sup and VISOR.grow(1).has_point(g[0]))
	for b in bolhas:
		b[0].y += b[1] * delta
		b[0].x += sin(t * 9.0 + b[0].y) * 6.0 * delta
	bolhas = bolhas.filter(func(b): return b[0].y > sup + 1)
	t_derrame = maxf(0.0, t_derrame - delta)
	if t_derrame > 0.0:
		poca = minf(1.0, poca + 2.5 * delta)
	else:
		poca = maxf(0.0, poca - 0.5 * delta)
	if poca > 0.2 and randf() < poca * 12.0 * delta:        # a poça pinga pela grade
		pingos.append([Vector2(GALAO.x + randf_range(-2, 39), Y_GRADE + 1), randf_range(10, 30)])
	for p in pingos:
		p[1] += 160.0 * delta
		p[0].y += p[1] * delta
	pingos = pingos.filter(func(p): return p[0].y < TAM_JANELA.y)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "REFILL THE WATER", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	draw_texture(TEX_ESTACAO, JANELA)
	_desenhar_jato(Y_BICO, GALAO.y)                # entre a torneira e a boca do galão
	draw_texture(TEX_GALAO, JANELA + GALAO)
	_agua()
	_desenhar_jato(VISOR.position.y, _superficie())   # dentro do galão, visto pelo vidro
	for g in gotas:
		_px(g[0], AGUA_BRILHO)
	draw_texture(TEX_BRILHO, JANELA + GALAO)
	_derrame()
	_faixa()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if mensagem != "" and (acabou or transbordou or not Input.is_action_pressed("usar")):
		Fonte.centralizado(self, mensagem, 160, y_txt, cor_mensagem)
	else:
		Fonte.centralizado_com_teclas(self, "HOLD [E] TO FILL - RELEASE ON THE GREEN MARK", 160, y_txt, BRANCO_SUJO, VERMELHO_CLARO)


func _px(p: Vector2, cor: Color) -> void:
	draw_rect(Rect2(JANELA + p.floor(), Vector2.ONE), cor)


## Trechos do jato entre y0 e y1: 3 px de largura, miolo claro com filetes correndo para baixo.
func _desenhar_jato(y0: float, y1: float) -> void:
	for j in jatos:
		var a := maxf(j[0], y0)
		var b := minf(j[1], y1)
		if b <= a:
			continue
		var topo := floori(a)
		var alto := ceili(b) - topo
		draw_rect(Rect2(JANELA + Vector2(X_JATO - 1, topo), Vector2(3, alto)), AGUA)
		draw_rect(Rect2(JANELA + Vector2(X_JATO, topo), Vector2(1, alto)), AGUA_CLARA)
		for y in range(topo, topo + alto):
			if posmod(y - int(t * 90.0), 6) == 0:
				_px(Vector2(X_JATO, y), AGUA_BRILHO)
			elif posmod(y - int(t * 90.0) + 3, 7) == 0:
				_px(Vector2(X_JATO - 1, y), AGUA_CLARA)


## Água no visor: superfície ondulando (mais quando o jato bate), espuma clara em cima e fundo mais escuro.
func _agua() -> void:
	var alto := _altura_agua()
	if alto <= 0:
		return
	var agitada := 1.0 if _caindo_na_agua() else 0.6
	var fundo := int(VISOR.end.y)
	for i in int(VISOR.size.x):
		var x := VISOR.position.x + i
		var onda := roundi(sin(t * 7.0 + i * 0.8) * agitada)
		var topo := clampi(fundo - alto + onda, int(VISOR.position.y), fundo - 1)
		var funda := mini(topo + 12, fundo)
		draw_rect(Rect2(JANELA + Vector2(x, topo), Vector2(1, funda - topo)), AGUA)
		if funda < fundo:
			draw_rect(Rect2(JANELA + Vector2(x, funda), Vector2(1, fundo - funda)), AGUA_FUNDA)
		_px(Vector2(x, topo), AGUA_BRILHO)
		if topo + 1 < fundo:
			_px(Vector2(x, topo + 1), AGUA_CLARA)
		if i == 3 and topo + 3 < fundo:        # reflexo vertical na água
			draw_rect(Rect2(JANELA + Vector2(x, topo + 3), Vector2(1, fundo - topo - 3)), AGUA_CLARA)
	for b in bolhas:
		_px(b[0], AGUA_BRILHO)


## Faixa verde: linhas pontilhadas no vidro nos dois limites e um colchete do lado de fora do galão.
func _faixa() -> void:
	var y_alto := VISOR.end.y - roundi(FAIXA_MAX * VISOR.size.y)
	var y_baixo := VISOR.end.y - roundi(FAIXA_MIN * VISOR.size.y)
	var dentro := nivel >= FAIXA_MIN and nivel <= FAIXA_MAX
	var cor := VERDE_LIMA if dentro else VERDE_ESC
	if acabou and fmod(t, 0.3) < 0.15:
		cor = BRANCO
	for i in range(0, int(VISOR.size.x), 2):
		_px(Vector2(VISOR.position.x + i, y_alto), cor)
		_px(Vector2(VISOR.position.x + i, y_baixo), cor)
	var xc := GALAO.x + TEX_GALAO.get_width() + 2
	draw_rect(Rect2(JANELA + Vector2(xc, y_alto), Vector2(1, y_baixo - y_alto + 1)), cor)
	draw_rect(Rect2(JANELA + Vector2(xc - 1, y_alto), Vector2(2, 1)), cor)
	draw_rect(Rect2(JANELA + Vector2(xc - 1, y_baixo), Vector2(2, 1)), cor)
	if dentro:                                    # setinha apontando para o nível
		var y := _superficie()
		_px(Vector2(xc + 2, y), cor)
		_px(Vector2(xc + 3, y - 1), cor)
		_px(Vector2(xc + 3, y + 1), cor)


## Transbordo: a água passa por cima do galão, escorre pelos dois lados, empoça na grade e pinga pelos furos.
func _derrame() -> void:
	var w := TEX_GALAO.get_width()
	var corre := int(t * 80.0)
	if t_derrame > 0.0:
		var y_topo := int(GALAO.y) + 3
		draw_rect(Rect2(JANELA + Vector2(GALAO.x + 2, y_topo), Vector2(w - 4, 1)), AGUA)
		for i in range(2, w - 2):
			if posmod(absi(i - int(w / 2.0)) - corre, 4) == 0:      # a película corre do meio para as bordas
				_px(Vector2(GALAO.x + i, y_topo), AGUA_BRILHO)
		for lado in [[GALAO.x - 2, GALAO.x + 1], [GALAO.x + w - 2, GALAO.x + w]]:
			var x: float = lado[0]
			_px(Vector2(lado[1], y_topo + 1), AGUA)
			draw_rect(Rect2(JANELA + Vector2(x, y_topo + 2), Vector2(2, Y_GRADE - y_topo - 2)), AGUA)
			for y in range(y_topo + 2, Y_GRADE):
				if posmod(y - corre, 5) == 0:
					_px(Vector2(x + 1, y), AGUA_BRILHO)
				elif posmod(y - corre, 5) == 2:
					_px(Vector2(x, y), AGUA_CLARA)
	if poca > 0.0:
		var meia := roundi((w / 2.0 + 8.0) * poca)
		var cx := GALAO.x + w / 2.0
		draw_rect(Rect2(JANELA + Vector2(cx - meia, Y_GRADE), Vector2(meia * 2, 2)), AGUA)
		draw_rect(Rect2(JANELA + Vector2(cx - meia + 1, Y_GRADE), Vector2(maxi(0, meia * 2 - 2), 1)), AGUA_CLARA)
		for i in range(-meia + 2, meia - 2, 5):
			_px(Vector2(cx + i + posmod(int(corre / 3.0), 3), Y_GRADE), AGUA_BRILHO)
	for p in pingos:
		_px(p[0], AGUA_CLARA)


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
