extends Control
## Minigame "cuidar das algas" (TEND THE ALGAE), nos biorreatores do Suporte à Vida: deixar os 2 tubos (TUBE A e
## TUBE B) dentro da faixa verde de fotossíntese ao mesmo tempo por 2 segundos. Esquerda / direita escolhem o tubo,
## cima / baixo aumentam ou diminuem o fluxo de nutrientes e luz dele. Passar do ponto (empurrar um tubo para fora
## da faixa) é erro: taxa_erro diminui o que a tarefa rende e MAX_ERROS erros a perdem (sinal falhou).
## Arte (paleta Apollo) em res://assets/minigames/algas/; líquido das algas, bolhas de fotossíntese, luz UV, faixas,
## seleção, luzes, barra de estabilidade, moldura e textos animados aqui. Contrato com o mapa: sinais `terminou`,
## `falhou` e `cancelou` (X ou Esc), taxa_erro() e a variável `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const TEX_REATOR := preload("res://assets/minigames/algas/reator.png")   # 192x121
const TEX_VIDRO := preload("res://assets/minigames/algas/vidro.png")     # reflexos do vidro, por cima do líquido

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
const MUSGO := Color("#19332d")
const VERDE_ESC := Color("#25562e")
const VERDE := Color("#468232")
const VERDE_CLARO := Color("#75a743")
const VERDE_LIMA := Color("#a8ca58")
const VERDE_PALIDO := Color("#d0da91")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const ROXO := Color("#a23e8c")
const ROSA := Color("#df84a5")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                  # canto do fundo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# posições dentro do fundo
const TUBOS := [Rect2(51, 18, 30, 66), Rect2(112, 18, 30, 66)]   # dentro do vidro
const LUZES_UV := [Rect2(37, 27, 8, 42), Rect2(147, 27, 8, 42)]   # faixas de LED roxo ao lado de cada tubo
const LEDS := [Vector2(40, 79), Vector2(152, 79)]                 # luz de estado nas caixinhas de controle
const VISOR := Rect2(26, 105, 140, 13)           # visor do rodapé: nomes dos tubos e barra de estabilidade

const NOMES := ["TUBE A", "TUBE B"]
const FAIXAS := [[0.45, 0.75], [0.35, 0.65]]     # faixa de fotossíntese de cada tubo (0 = vazio, 1 = cheio)
const INICIO := [0.20, 0.85]                     # cada tubo começa fora da faixa: o A baixo, o B alto
const VEL_AJUSTE := 0.50                         # quanto o jogador sobe ou desce por segundo
const TEMPO_OK := 2.0                            # segundos com os 2 tubos na faixa para terminar
const TEMPO_FIM := 1.3
const MAX_ERROS := 6                             # com tantos erros a tarefa é perdida
const TEMPO_ERRO := 0.6                          # quanto tempo o aviso de erro fica na tela

var demo := false                                # o jogo coloca true no modo demo: o minigame se resolve sozinho
var niveis: Array = []
var selecionado := 0                             # tubo escolhido: 0 = A, 1 = B
var tempo_estavel := 0.0
var t_demo := 0.0
var acabou := false
var t := 0.0
var t_fim := -1.0
var acertos := 0                                 # vezes que o jogador levou um item para dentro da faixa
var erros := 0                                   # vezes que o jogador passou do ponto (empurrou para fora)
var estava: Array = []                           # cada item estava na faixa no quadro anterior?
var t_erro := 0.0
var perdeu := false
var ajuste := 0.0                                # -1, 0 ou 1: o jogador está tirando ou pondo nutrientes
var bolhas: Array = []                           # [tubo, x, y, vel]: bolhas de oxigênio subindo, dentro do tubo
var particulas: Array = []                       # [tubo, x, y, fase]: grumos de alga boiando no líquido
var t_bolha := 0.0
var t_troca := 0.0                               # piscada da seleção ao trocar de tubo


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	niveis = INICIO.duplicate()
	for i in niveis.size():
		estava.append(_na_faixa(i))
	for i in TUBOS.size():
		var r: Rect2 = TUBOS[i]
		for k in 9:
			particulas.append([i, randf_range(2.0, r.size.x - 3.0), randf_range(0.0, 1.0), randf() * TAU])


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
	_contar_lances()
	if perdeu:
		queue_redraw()
		return
	if _todos_na_faixa():
		tempo_estavel += delta
		if tempo_estavel >= TEMPO_OK:
			acabou = true
			t_fim = TEMPO_FIM
	else:
		tempo_estavel = 0.0
	queue_redraw()


func _controles(delta: float) -> void:
	var antes := selecionado
	if Input.is_action_just_pressed("esquerda"):
		selecionado = 0
	elif Input.is_action_just_pressed("direita"):
		selecionado = 1
	if selecionado != antes:
		t_troca = 0.2
	ajuste = Input.get_axis("baixo", "cima")
	niveis[selecionado] = clampf(niveis[selecionado] + ajuste * VEL_AJUSTE * delta, 0.0, 1.0)


## Erro: o jogador empurrou o item da vez para fora da faixa (passou do ponto). Acerto: levou ele para dentro.
## Sair da faixa sozinho (sem o jogador mexer) não conta.
func _contar_lances() -> void:
	for i in niveis.size():
		var dentro := _na_faixa(i)
		if i == selecionado and ajuste != 0.0 and dentro != estava[i]:
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


func _na_faixa(i: int) -> bool:
	return niveis[i] >= FAIXAS[i][0] and niveis[i] <= FAIXAS[i][1]


func _todos_na_faixa() -> bool:
	for i in niveis.size():
		if not _na_faixa(i):
			return false
	return true


func _meio(i: int) -> float:
	return (FAIXAS[i][0] + FAIXAS[i][1]) / 2.0


func _jogar_sozinho(delta: float) -> void:
	# no demo, a cada 0,35 s pega o primeiro tubo longe do meio da faixa e leva ele para o meio
	t_demo += delta
	if t_demo >= 0.35:
		t_demo = 0.0
		for i in niveis.size():
			if absf(niveis[i] - _meio(i)) > 0.05:
				if i != selecionado:
					t_troca = 0.2
				selecionado = i
				break
	var alvo := _meio(selecionado)
	ajuste = 0.0 if absf(alvo - niveis[selecionado]) < 0.005 else signf(alvo - niveis[selecionado])
	niveis[selecionado] = move_toward(niveis[selecionado], alvo, VEL_AJUSTE * delta)


## y (dentro do tubo) da superfície do líquido.
func _superficie(i: int) -> float:
	var r: Rect2 = TUBOS[i]
	return r.size.y - roundf(niveis[i] * r.size.y)


## Bolhas de oxigênio da fotossíntese: muitas com o tubo na faixa, poucas fora dela.
func _animar_bolhas(delta: float) -> void:
	t_bolha -= delta
	if t_bolha <= 0.0:
		t_bolha = 0.1
		for i in TUBOS.size():
			var chance := 0.8 if _na_faixa(i) else 0.15
			if randf() < chance and niveis[i] > 0.06:
				var r: Rect2 = TUBOS[i]
				bolhas.append([i, randf_range(2.0, r.size.x - 3.0), r.size.y - 1.0, randf_range(12.0, 26.0)])
	for b in bolhas:
		b[2] -= b[3] * delta
		b[1] += sin(t * 6.0 + b[3]) * 4.0 * delta          # sobem balançando um pouco
	bolhas = bolhas.filter(func(b): return b[2] > _superficie(b[0]) + 1.0)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "TEND THE ALGAE", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	var certos := 0
	for i in NOMES.size():
		certos += 1 if _na_faixa(i) else 0
	Fonte.desenhar(self, "%d/2" % certos, PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	draw_texture(TEX_REATOR, JANELA)
	for i in TUBOS.size():
		_luz_uv(i)
		_tubo(i)
	draw_texture(TEX_VIDRO, JANELA)
	for i in TUBOS.size():
		_faixa(i)
		_led(i)
	_selecao()
	_visor()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if perdeu:
		Fonte.centralizado(self, "TOO MANY ERRORS - TASK FAILED", 160, y_txt, VERMELHO_CLARO)
	elif acabou:
		Fonte.centralizado(self, "BIOREACTORS BALANCED!", 160, y_txt, VERDE_LIMA)
	elif t_erro > 0.0:
		Fonte.centralizado(self, "OVERSHOT! (%d/%d)" % [erros, MAX_ERROS], 160, y_txt,
			VERMELHO_CLARO)
	else:
		Fonte.centralizado(self, "LEFT/RIGHT PICK A TUBE - UP/DOWN FEED IT", 160, y_txt, BRANCO_SUJO)


func _px(p: Vector2, cor: Color) -> void:
	draw_rect(Rect2(p.floor(), Vector2.ONE), cor)


## Brilho da faixa de LED roxo: mais forte quanto mais luz e nutrientes o tubo recebe, tremendo ao ajustar.
func _luz_uv(i: int) -> void:
	var r: Rect2 = LUZES_UV[i]
	var forca: float = 0.15 + 0.45 * niveis[i]
	if i == selecionado and ajuste != 0.0:
		forca += 0.1 * sin(t * 30.0)
	draw_rect(Rect2(JANELA + r.position, r.size), Color(ROXO, forca * 0.6))
	draw_rect(Rect2(JANELA + r.position + Vector2(3, 1), Vector2(2, r.size.y - 2)), Color(ROSA, forca))


## O líquido das algas: verde escuro com faixa mais clara do lado, superfície ondulando, grumos boiando e bolhas.
func _tubo(i: int) -> void:
	var r: Rect2 = TUBOS[i]
	var base := JANELA + r.position
	var topo := _superficie(i)
	var dentro := _na_faixa(i)
	var pulso := acabou and not perdeu and fmod(t + i * 0.2, 0.5) < 0.25
	var corpo := VERDE if dentro else VERDE_ESC
	var lado := VERDE_CLARO if dentro else VERDE
	if pulso:
		corpo = VERDE_CLARO
		lado = VERDE_LIMA
	for x in int(r.size.x):
		var onda := roundf(sin(t * 4.0 + x * 0.6 + i * 2.0) * 0.7)
		var y0 := clampf(topo + onda, 0.0, r.size.y)
		var alto := r.size.y - y0
		if alto <= 0.0:
			continue
		var cor := lado if x in [2, 3, 4] else corpo
		draw_rect(Rect2(base + Vector2(x, y0), Vector2(1, alto)), Color(cor, 0.92))
		draw_rect(Rect2(base + Vector2(x, y0), Vector2.ONE), VERDE_PALIDO if dentro else VERDE_CLARO)
	for p in particulas:                          # grumos de alga boiando devagar
		if p[0] != i:
			continue
		var py: float = topo + 2.0 + p[2] * (r.size.y - topo - 3.0) + sin(t * 1.3 + p[3]) * 1.5
		if py > topo + 1.0 and py < r.size.y:
			_px(base + Vector2(p[1] + sin(t * 0.8 + p[3]), py), MUSGO)
	for b in bolhas:
		if b[0] == i:
			_px(base + Vector2(b[1], b[2]), VERDE_PALIDO)


## Faixa verde: colchetes dos dois lados do tubo; acendem com o líquido dentro.
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
	for y in [y1, y2]:                            # tracinhos no vidro marcando as pontas da faixa
		for x in range(0, int(r.size.x), 2):
			_px(Vector2(JANELA.x + r.position.x + x, y), Color(cor, 0.7))


func _led(i: int) -> void:
	var p: Vector2 = JANELA + LEDS[i]
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(4, 4)), PRETO)
	var cor := VERDE_LIMA if _na_faixa(i) else (VERMELHO_CLARO if fmod(t + i * 0.2, 0.6) < 0.3 else VERMELHO)
	draw_rect(Rect2(p, Vector2(2, 2)), cor)


## Cantos amarelos em volta do tubo da vez, com uma setinha piscando em cima.
func _selecao() -> void:
	if acabou:
		return
	var r: Rect2 = TUBOS[selecionado]
	var caixa := Rect2(JANELA + r.position - Vector2(6, 4), r.size + Vector2(12, 8))
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


## Visor do rodapé: o nome de cada tubo embaixo dele (verde na faixa) e a barra de estabilidade.
func _visor() -> void:
	var v := Rect2(JANELA + VISOR.position, VISOR.size)
	draw_rect(v.grow(1), PRETO)
	draw_rect(v, NOITE)
	for i in NOMES.size():
		var cx: float = JANELA.x + TUBOS[i].get_center().x
		var cor: Color = VERDE_LIMA if _na_faixa(i) else (BRANCO if i == selecionado else METAL)
		Fonte.centralizado(self, NOMES[i], cx, v.position.y + 1, cor)
	var barra := Rect2(v.position + Vector2(4, 9), Vector2(v.size.x - 8, 2))
	draw_rect(barra.grow(1), CINZA_ESC)
	draw_rect(barra, FUNDO)
	var cheio := 1.0 if acabou and not perdeu else clampf(tempo_estavel / TEMPO_OK, 0.0, 1.0)
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
