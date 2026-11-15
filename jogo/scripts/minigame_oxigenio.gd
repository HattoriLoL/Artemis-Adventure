extends Control
## Minigame "equilibrar o ar" (BALANCE THE AIR), no console de gases do Suporte à Vida: deixar O2, N2 e CO2 dentro
## das faixas verdes ao mesmo tempo por 2 segundos. Esquerda / direita escolhem o tubo, cima / baixo giram o volante
## e sobem ou descem o gás. Os níveis mudam sozinhos devagar (O2 e N2 descem, CO2 sobe). Passar do ponto (empurrar
## um gás para fora da faixa) é erro: taxa_erro diminui o que a tarefa rende e MAX_ERROS erros a perdem (falhou).
## Arte (paleta Apollo) em res://assets/minigames/oxigenio/; gás, bolhas, faixas, seleção, volantes, luzes, barra de
## estabilidade, moldura e textos animados aqui. Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou`
## (X ou Esc), taxa_erro() e a variável `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const TEX_CONSOLE := preload("res://assets/minigames/oxigenio/console.png")   # 192x121
const TEX_VIDRO := preload("res://assets/minigames/oxigenio/vidro.png")       # reflexos do vidro, por cima do gás

const PRETO := Color("#090a14")
const NOITE := Color("#10141f")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO_SUJO := Color("#c7cfcc")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE_ESC := Color("#25562e")
const VERDE := Color("#468232")
const VERDE_CLARO := Color("#75a743")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
# cor de cada gás: [corpo, superfície, brilho]
const CORES_GAS := [[Color("#4f8fba"), Color("#73bed3"), Color("#a4dddb")],    # O2
	[Color("#7a367b"), Color("#a23e8c"), Color("#df84a5")],                    # N2
	[Color("#be772b"), Color("#de9e41"), Color("#e8c170")]]                    # CO2

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                  # canto do console (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# posições dentro do console
const TUBOS := [Rect2(44, 24, 11, 45), Rect2(90, 24, 12, 45), Rect2(136, 24, 12, 45)]   # dentro do vidro
const VOLANTES := [Vector2(46, 86), Vector2(96, 86), Vector2(143, 86)]                  # meio de cada volante
const RAIO_VOLANTE := 8.0
const LEDS := [Vector2(65, 62), Vector2(112, 62), Vector2(160, 62)]
const VISOR := Rect2(26, 103, 140, 13)           # visor do rodapé: nomes dos gases e barra de estabilidade

const NOMES := ["O2", "N2", "CO2"]
const FAIXAS := [[0.55, 0.75], [0.60, 0.80], [0.10, 0.30]]   # faixa certa de cada gás (0 = vazio, 1 = cheio)
const INICIO := [0.25, 0.30, 0.65]                            # nível inicial de cada gás, fora da faixa
const DERIVA := [-0.03, -0.02, 0.04]                          # quanto cada nível muda sozinho por segundo
const VEL_AJUSTE := 0.35                                      # quanto o jogador sobe ou desce por segundo
const TEMPO_OK := 2.0                                         # segundos com as 3 na faixa para terminar
const TEMPO_FIM := 1.3
const MAX_ERROS := 4                             # com tantos erros a tarefa é perdida (era 6: tolerante demais)
const TEMPO_ERRO := 0.6                          # quanto tempo o aviso de erro fica na tela

var demo := false                                # o jogo coloca true no modo demo: o minigame se resolve sozinho
var niveis: Array = []
var selecionada := 0                             # tubo escolhido: 0 = O2, 1 = N2, 2 = CO2
var tempo_ok := 0.0
var t_demo := 0.0
var acabou := false
var t := 0.0
var t_fim := -1.0
var acertos := 0                                 # vezes que o jogador levou um item para dentro da faixa
var erros := 0                                   # vezes que o jogador passou do ponto (empurrou para fora)
var estava: Array = []                           # cada item estava na faixa no quadro anterior?
var t_erro := 0.0
var perdeu := false
var ajuste := 0.0                                # -1, 0 ou 1: para onde o volante da vez está girando
var angulos := [0.0, 0.7, 1.4]                   # rotação de cada volante
var bolhas: Array = []                           # [tubo, x, y, vel]: bolhas subindo no gás, dentro do console
var t_bolha := 0.0
var t_troca := 0.0                               # piscada da seleção ao trocar de tubo


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	niveis = INICIO.duplicate()
	for i in niveis.size():
		estava.append(_na_faixa(i))


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
	t_troca = maxf(0.0, t_troca - delta)
	t_erro = maxf(0.0, t_erro - delta)
	_animar_bolhas(delta)
	if acabou:
		ajuste = 0.0
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
		queue_redraw()
		return
	if demo:
		_jogar_sozinho(delta)
	else:
		_controles(delta)
	angulos[selecionada] += ajuste * 6.0 * delta
	for i in niveis.size():
		niveis[i] = clampf(niveis[i] + DERIVA[i] * delta, 0.0, 1.0)
	_contar_lances()
	if perdeu:
		queue_redraw()
		return
	if _todas_na_faixa():
		tempo_ok += delta
	else:
		tempo_ok = 0.0
	if tempo_ok >= TEMPO_OK:
		acabou = true
		t_fim = TEMPO_FIM
	queue_redraw()


func _controles(delta: float) -> void:
	var antes := selecionada
	if Input.is_action_just_pressed("esquerda"):
		selecionada = maxi(0, selecionada - 1)
	if Input.is_action_just_pressed("direita"):
		selecionada = mini(NOMES.size() - 1, selecionada + 1)
	if selecionada != antes:
		t_troca = 0.2
	ajuste = Input.get_axis("baixo", "cima")     # cima = +1, baixo = -1
	niveis[selecionada] = clampf(niveis[selecionada] + ajuste * VEL_AJUSTE * delta, 0.0, 1.0)


## Erro: o jogador empurrou o item da vez para fora da faixa (passou do ponto). Acerto: levou ele para dentro.
## Sair da faixa sozinho (sem o jogador mexer) não conta.
func _contar_lances() -> void:
	for i in niveis.size():
		var dentro := _na_faixa(i)
		if i == selecionada and ajuste != 0.0 and dentro != estava[i]:
			if dentro:
				acertos += 1
			else:
				erros += 1
				t_erro = TEMPO_ERRO
				if erros >= MAX_ERROS:
					perdeu = true
					acabou = true
					t_fim = TEMPO_FIM
		estava[i] = dentro


## Fração dos lances que passaram do ponto.
func taxa_erro() -> float:
	return erros / maxf(1.0, float(erros + acertos))


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça.
func comecou() -> bool:
	return erros > 0 or acertos > 0


func _na_faixa(i: int) -> bool:
	return niveis[i] >= FAIXAS[i][0] and niveis[i] <= FAIXAS[i][1]


func _todas_na_faixa() -> bool:
	for i in niveis.size():
		if not _na_faixa(i):
			return false
	return true


func _jogar_sozinho(delta: float) -> void:
	# no demo, a cada 0,4 s escolhe o tubo mais longe do meio da faixa e leva ele para o meio
	t_demo -= delta
	if t_demo <= 0.0:
		t_demo = 0.4
		var maior_erro := -1.0
		var antes := selecionada
		for i in niveis.size():
			var erro := absf(niveis[i] - _meio(i))
			if erro > maior_erro:
				maior_erro = erro
				selecionada = i
		if selecionada != antes:
			t_troca = 0.2
	var alvo := _meio(selecionada)
	ajuste = 0.0 if absf(alvo - niveis[selecionada]) < 0.005 else signf(alvo - niveis[selecionada])
	niveis[selecionada] = move_toward(niveis[selecionada], alvo, VEL_AJUSTE * delta)


func _meio(i: int) -> float:
	return (FAIXAS[i][0] + FAIXAS[i][1]) / 2.0


## Bolhas sobem dentro do gás de cada tubo e estouram na superfície; com o volante girando saem mais.
func _animar_bolhas(delta: float) -> void:
	t_bolha -= delta
	if t_bolha <= 0.0:
		t_bolha = 0.12
		for i in TUBOS.size():
			var chance := 0.75 if i == selecionada and ajuste > 0.0 else 0.25
			if randf() < chance and niveis[i] > 0.08:
				var r: Rect2 = TUBOS[i]
				bolhas.append([i, randf_range(1.0, r.size.x - 2.0), r.size.y - 1.0, randf_range(10.0, 22.0)])
	for b in bolhas:
		b[2] -= b[3] * delta
	bolhas = bolhas.filter(func(b): return b[2] > _altura_gas(b[0]) + 1.0)


## y (dentro do tubo) da superfície do gás.
func _altura_gas(i: int) -> float:
	var r: Rect2 = TUBOS[i]
	return r.size.y - roundf(niveis[i] * r.size.y)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "BALANCE THE AIR", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	var certos := 0
	for i in NOMES.size():
		certos += 1 if _na_faixa(i) else 0
	Fonte.desenhar(self, "%d/3" % certos, PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	draw_texture(TEX_CONSOLE, JANELA)
	for i in TUBOS.size():
		_tubo(i)
	draw_texture(TEX_VIDRO, JANELA)
	for i in TUBOS.size():
		_faixa(i)
		_volante(i)
		_led(i)
	_selecao()
	_visor()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if perdeu:
		Fonte.centralizado(self, "TOO MANY ERRORS - TASK FAILED", 160, y_txt, VERMELHO_CLARO)
	elif acabou:
		Fonte.centralizado(self, "AIR BALANCED!", 160, y_txt, VERDE_LIMA)
	elif t_erro > 0.0:
		Fonte.centralizado(self, "OVERSHOT! (%d/%d)" % [erros, MAX_ERROS], 160, y_txt,
			VERMELHO_CLARO)
	else:
		Fonte.centralizado(self, "LEFT/RIGHT PICK A GAS - UP/DOWN TURN THE VALVE", 160, y_txt, BRANCO_SUJO)


func _px(p: Vector2, cor: Color) -> void:
	draw_rect(Rect2(p.floor(), Vector2.ONE), cor)


## O gás dentro do tubo: corpo com faixa clara de um lado, superfície ondulando e bolhas.
func _tubo(i: int) -> void:
	var r: Rect2 = TUBOS[i]
	var base := JANELA + r.position
	var cores: Array = CORES_GAS[i]
	var topo := _altura_gas(i)
	var pulso := acabou and not perdeu and fmod(t + i * 0.15, 0.5) < 0.25
	for x in int(r.size.x):
		var onda := roundf(sin(t * 5.0 + x * 0.9 + i) * 0.6)     # superfície mexendo um pouco
		var y0 := clampf(topo + onda, 0.0, r.size.y)
		var alto := r.size.y - y0
		if alto <= 0.0:
			continue
		var cor: Color = cores[0]
		if x == 1 or x == 2:
			cor = cores[1]                                         # faixa clara do lado esquerdo do vidro
		if pulso:
			cor = cores[1]
		draw_rect(Rect2(base + Vector2(x, y0), Vector2(1, alto)), Color(cor, 0.9))
		draw_rect(Rect2(base + Vector2(x, y0), Vector2.ONE), cores[2])
	for b in bolhas:
		if b[0] == i:
			_px(base + Vector2(b[1], b[2]), cores[2])


## Faixa verde: colchetes dos dois lados do tubo marcando onde o gás tem que ficar; acendem com o gás dentro.
func _faixa(i: int) -> void:
	var r: Rect2 = TUBOS[i]
	var y1 := JANELA.y + r.position.y + r.size.y - roundf(FAIXAS[i][1] * r.size.y)
	var y2 := JANELA.y + r.position.y + r.size.y - roundf(FAIXAS[i][0] * r.size.y)
	var dentro := _na_faixa(i)
	var cor := VERDE_LIMA if dentro else VERDE_CLARO
	var escura := VERDE if dentro else VERDE_ESC
	for lado in [JANELA.x + r.position.x - 3, JANELA.x + r.end.x + 1]:
		draw_rect(Rect2(lado - 1, y1 - 1, 4, y2 - y1 + 3), PRETO)
		draw_rect(Rect2(lado, y1, 2, y2 - y1 + 1), escura)
		draw_rect(Rect2(lado, y1, 2, 1), cor)
		draw_rect(Rect2(lado, y2, 2, 1), cor)
		if dentro:
			draw_rect(Rect2(lado, y1, 1, y2 - y1 + 1), cor)
	# tracinhos no vidro marcando as pontas da faixa
	for y in [y1, y2]:
		for x in range(0, int(r.size.x), 2):
			_px(Vector2(JANELA.x + r.position.x + x, y), Color(cor, 0.7))


## Volante: um raio claro marca a rotação; o da vez gira quando o jogador sobe ou desce o gás.
func _volante(i: int) -> void:
	var c: Vector2 = JANELA + VOLANTES[i]
	for k in 3:
		var a: float = angulos[i] + k * TAU / 3.0
		for d in range(2, int(RAIO_VOLANTE)):
			_px(c + Vector2(cos(a), sin(a)) * d, METAL_CLARO if k == 0 else METAL)
	var a0: float = angulos[i]
	_px(c + Vector2(cos(a0), sin(a0)) * RAIO_VOLANTE, BRANCO if i == selecionada else BRANCO_SUJO)


func _led(i: int) -> void:
	var p: Vector2 = JANELA + LEDS[i]
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(4, 4)), PRETO)
	var cor := VERDE_LIMA if _na_faixa(i) else (VERMELHO_CLARO if fmod(t + i * 0.2, 0.6) < 0.3 else VERMELHO)
	draw_rect(Rect2(p, Vector2(2, 2)), cor)


## Moldura amarela em volta do tubo e do volante da vez, com uma setinha piscando em cima.
func _selecao() -> void:
	if acabou:
		return
	var r: Rect2 = TUBOS[selecionada]
	var caixa := Rect2(JANELA + r.position - Vector2(6, 4), Vector2(r.size.x + 12, 74))
	var cor := BRANCO if t_troca > 0.0 else AMARELO
	var canto := 4.0
	for c in [caixa.position, Vector2(caixa.end.x - canto, caixa.position.y),
			Vector2(caixa.position.x, caixa.end.y - 1), Vector2(caixa.end.x - canto, caixa.end.y - 1)]:
		draw_rect(Rect2(c, Vector2(canto, 1)), cor)
	for c in [caixa.position, Vector2(caixa.end.x - 1, caixa.position.y),
			Vector2(caixa.position.x, caixa.end.y - canto), Vector2(caixa.end.x - 1, caixa.end.y - canto)]:
		draw_rect(Rect2(c, Vector2(1, canto)), cor)
	var cx := roundf(caixa.get_center().x)
	var y := caixa.position.y - 5 + (1 if fmod(t, 0.6) < 0.3 else 0)
	draw_rect(Rect2(cx - 2, y, 5, 1), cor)
	draw_rect(Rect2(cx - 1, y + 1, 3, 1), cor)
	_px(Vector2(cx, y + 2), cor)


## Visor do rodapé: o nome de cada gás embaixo do tubo (verde quando está na faixa) e a barra de estabilidade, que
## enche enquanto os três estão certos.
func _visor() -> void:
	var v := Rect2(JANELA + VISOR.position, VISOR.size)
	draw_rect(v.grow(1), PRETO)
	draw_rect(v, NOITE)
	for i in NOMES.size():
		var cx: float = JANELA.x + TUBOS[i].get_center().x
		var cor: Color = VERDE_LIMA if _na_faixa(i) else (BRANCO if i == selecionada else METAL)
		Fonte.centralizado(self, NOMES[i], cx, v.position.y + 1, cor)
	var barra := Rect2(v.position + Vector2(4, 9), Vector2(v.size.x - 8, 2))
	draw_rect(barra.grow(1), CINZA_ESC)
	draw_rect(barra, FUNDO)
	var cheio := 1.0 if acabou and not perdeu else clampf(tempo_ok / TEMPO_OK, 0.0, 1.0)
	if cheio > 0.0:
		var cor_barra := VERDE_LIMA if acabou and fmod(t, 0.3) < 0.15 else VERDE_CLARO
		draw_rect(Rect2(barra.position, Vector2(roundf(barra.size.x * cheio), barra.size.y)), cor_barra)


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
