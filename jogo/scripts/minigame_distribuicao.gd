extends Control
## Minigame "balancear a energia" (BALANCE THE POWER), no painel de distribuição da sala de Energia: 3 canais de
## carga (LIFE SUPPORT, BASE, SHIELDS), cada um com um medidor vertical e uma alavanca. O jogador escolhe o canal
## (A/D) e sobe ou desce a carga (W/S) até os três ficarem na faixa verde ao mesmo tempo por TEMPO_OK segundos
## seguidos. A energia da base é uma só: mexer num canal empurra os outros dois para o lado contrário
## (ACOPLAMENTO). Não tem falha (é uma das tarefas de energia que funcionam à noite), mas passar do ponto, tirando o
## canal escolhido da faixa verde, é erro: taxa_erro diminui o que a tarefa rende.
## A ideia e a mecânica (3 canais com faixas, A/D escolhe, W/S regula, estável por 2 s) vieram do PR #17
## (IltonBJSilva).
## Arte (paleta Apollo, PixelAi) em res://assets/minigames/distribuicao/: fundo.png (192x121) com os 3 trilhos e
## alavanca.png / alavanca_sel.png. Se um arquivo faltar, o minigame desenha uma versão provisória no lugar dele.
## A carga, a faixa verde, os nomes dos canais e a barra de estabilidade são desenhados aqui.
## Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e `demo`.

signal terminou
signal cancelou
signal falhou                                    # nunca emitido aqui: com ele e comecou(), o mapa trata fechar
                                                 # depois de começar como desistência (gasta a ação, não rende)

const Fonte = preload("res://scripts/fonte.gd")
const DIR_ARTE := "res://assets/minigames/distribuicao/"

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const LARANJA := Color("#de9e41")
const VERDE := Color("#75a743")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const CIANO := Color("#73bed3")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                   # canto do fundo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# dentro do fundo: o x do centro de cada trilho, o topo e a base da fenda e o y das plaquinhas dos nomes
const TRILHOS_X := [56.0, 96.0, 136.0]            # fendas do fundo.png em x 52..59, 92..99 e 132..139
const FENDA_LARG := 8.0
const FENDA_TOPO := 22.0
const FENDA_BASE := 88.0                           # a fenda vai de y 22 a 87 (66 px)
const PLACA_Y := 96.0                              # miolo das plaquinhas (30x7 com o canto em y 95)

const NOMES := ["SUPPORT", "BASE", "SHIELDS"]
const FAIXAS := [[0.40, 0.65], [0.50, 0.75], [0.35, 0.60]]   # faixa verde de cada canal (fração da fenda)
const INICIO := [0.15, 0.85, 0.20]
const VELOCIDADE := 0.45                           # quanto a carga anda por segundo segurando W/S
const TEMPO_OK := 2.0                              # segundos com os três canais na faixa
const ACOPLAMENTO := 0.3                           # o que um canal sobe, os outros dois descem juntos (30%, metade cada)
const TEMPO_FIM := 1.2

var demo := false
var niveis: Array[float] = []
var selecionado := 0
var tempo_estavel := 0.0
var acabou := false
var t := 0.0
var t_fim := -1.0
var t_demo := 0.0
var mexeu := false                                 # já mexeu na carga de algum canal (comecou)
var erros := 0                                     # vezes que o jogador tirou o canal escolhido da faixa
var t_erro := 0.0                                  # aviso OVERSHOT! na tela
var faiscas: Array = []                            # [pos, vel, vida] no canal fora da faixa mexido agora

var tex_fundo: Texture2D
var tex_alavanca: Texture2D
var tex_alavanca_sel: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	niveis.assign(INICIO)
	tex_fundo = _textura("fundo")
	tex_alavanca = _textura("alavanca")
	tex_alavanca_sel = _textura("alavanca_sel")


func _textura(nome: String) -> Texture2D:
	var c := DIR_ARTE + nome + ".png"
	return load(c) if ResourceLoader.exists(c) else null


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
	t_erro = maxf(0.0, t_erro - delta)
	if not acabou:
		if demo:
			_jogar_sozinho(delta)
		else:
			_controles(delta)
		if canais_ok() == NOMES.size():
			tempo_estavel += delta
			if tempo_estavel >= TEMPO_OK:
				acabou = true
				t_fim = TEMPO_FIM
		else:
			tempo_estavel = 0.0
	_animar(delta)
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			terminou.emit()
	queue_redraw()


func _controles(delta: float) -> void:
	if Input.is_action_just_pressed("esquerda"):
		selecionado = maxi(0, selecionado - 1)
	elif Input.is_action_just_pressed("direita"):
		selecionado = mini(NOMES.size() - 1, selecionado + 1)
	var ajuste := Input.get_axis("baixo", "cima")
	if ajuste != 0.0:
		mexeu = true
		var estava := na_faixa(selecionado)
		_mover(selecionado, ajuste * VELOCIDADE * delta)
		if estava and not na_faixa(selecionado):    # passou do ponto: erro
			erros += 1
			t_erro = 0.8


## Muda a carga de um canal; os outros dois mudam ao contrário (a energia total da base é uma só).
func _mover(i: int, d: float) -> void:
	var antes := niveis[i]
	niveis[i] = clampf(niveis[i] + d, 0.0, 1.0)
	var real := niveis[i] - antes
	for j in NOMES.size():
		if j != i:
			niveis[j] = clampf(niveis[j] - real * ACOPLAMENTO / 2.0, 0.0, 1.0)


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça. Sem isso, dava para fechar um preparo ruim e
## jogar de novo até sair perfeito, e a perda de ganho por erro não valia nada.
func comecou() -> bool:
	return mexeu


## Fração de erros (3 canais para acertar): 1 erro ~ 94% do ganho, 2 ~ 75%, 3 ~ 62%.
func taxa_erro() -> float:
	return erros / (erros + 3.0)


## Demo: vai para o primeiro canal longe do meio da faixa e leva a carga até lá.
func _jogar_sozinho(delta: float) -> void:
	t_demo += delta
	if t_demo >= 0.3:
		t_demo = 0.0
		for i in NOMES.size():
			if absf(niveis[i] - _meio(i)) > 0.05:
				selecionado = i
				break
	var alvo := move_toward(niveis[selecionado], _meio(selecionado), VELOCIDADE * delta)
	_mover(selecionado, alvo - niveis[selecionado])


func _meio(i: int) -> float:
	return (float(FAIXAS[i][0]) + float(FAIXAS[i][1])) / 2.0


func na_faixa(i: int) -> bool:
	return niveis[i] >= float(FAIXAS[i][0]) and niveis[i] <= float(FAIXAS[i][1])


func canais_ok() -> int:
	var n := 0
	for i in NOMES.size():
		if na_faixa(i):
			n += 1
	return n


func _y_nivel(v: float) -> float:
	return FENDA_BASE - v * (FENDA_BASE - FENDA_TOPO)


## Faíscas saindo do topo da carga dos canais fora da faixa (o painel "reclama" do desequilíbrio).
func _animar(delta: float) -> void:
	if not acabou:
		for i in NOMES.size():
			if not na_faixa(i) and randf() < 6.0 * delta:
				var p := Vector2(TRILHOS_X[i] + randf_range(-3, 3), _y_nivel(niveis[i]))
				faiscas.append([p, Vector2(randf_range(-20, 20), randf_range(-30, -10)), randf_range(0.2, 0.4)])
	for f in faiscas:
		f[0] += f[1] * delta
		f[1].y += 80.0 * delta
		f[2] -= delta
	faiscas = faiscas.filter(func(f): return f[2] > 0.0)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "BALANCE THE POWER", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "%d/%d" % [canais_ok(), NOMES.size()], PAINEL.position + Vector2(12, 5), VERDE_LIMA)
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
	for i in NOMES.size():
		_canal(i)
	for f in faiscas:
		draw_rect(Rect2(JANELA + (f[0] as Vector2).floor(), Vector2.ONE), AMARELO if f[2] > 0.25 else LARANJA)
	_barra_estavel()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if acabou:
		Fonte.centralizado(self, "GRID BALANCED!", 160, y_txt, VERDE_LIMA)
	elif t_erro > 0.0:
		Fonte.centralizado(self, "OVERSHOT! (%d)" % erros, 160, y_txt,
			VERMELHO_CLARO if fmod(t, 0.3) < 0.18 else LARANJA)
	elif canais_ok() == NOMES.size():
		Fonte.centralizado(self, "ALL CHANNELS GREEN - HOLD IT...", 160, y_txt, VERDE_LIMA)
	else:
		Fonte.centralizado_com_teclas(self, "[A/D]: PICK CHANNEL   [W/S]: SET LOAD", 160, y_txt, BRANCO_SUJO, Color("#cf573c"))


## Um canal: a faixa verde na fenda, a carga subindo da base, a alavanca na altura da carga e o nome na plaquinha.
func _canal(i: int) -> void:
	var cx: float = TRILHOS_X[i]
	var x0 := cx - FENDA_LARG / 2.0
	var ok := na_faixa(i)
	var sel := i == selecionado and not acabou
	if not tex_fundo:                                     # fenda provisória
		draw_rect(Rect2(JANELA + Vector2(x0 - 2, FENDA_TOPO - 2), Vector2(FENDA_LARG + 4, FENDA_BASE - FENDA_TOPO + 4)), PRETO)
		draw_rect(Rect2(JANELA + Vector2(x0, FENDA_TOPO), Vector2(FENDA_LARG, FENDA_BASE - FENDA_TOPO)), FUNDO)
	var y_max := _y_nivel(float(FAIXAS[i][1]))
	var y_min := _y_nivel(float(FAIXAS[i][0]))
	draw_rect(Rect2(JANELA + Vector2(x0, y_max), Vector2(FENDA_LARG, y_min - y_max)), Color(VERDE, 0.35))
	draw_rect(Rect2(JANELA + Vector2(x0 - 3, y_max), Vector2(2, y_min - y_max)), Color(VERDE_LIMA, 0.9 if ok else 0.5))
	draw_rect(Rect2(JANELA + Vector2(x0 + FENDA_LARG + 1, y_max), Vector2(2, y_min - y_max)),
		Color(VERDE_LIMA, 0.9 if ok else 0.5))
	var y := roundf(_y_nivel(niveis[i]))
	var cor := VERDE_LIMA if ok else (VERMELHO_CLARO if niveis[i] > float(FAIXAS[i][1]) else CIANO)
	draw_rect(Rect2(JANELA + Vector2(x0 + 2, y), Vector2(FENDA_LARG - 4, FENDA_BASE - y)), cor)
	var tex := tex_alavanca_sel if (sel and tex_alavanca_sel) else tex_alavanca
	if tex:
		draw_texture(tex, JANELA + Vector2(cx, y) - (tex.get_size() / 2.0).floor())
	else:
		var r := Rect2(JANELA + Vector2(cx - 9, y - 3), Vector2(18, 7))
		draw_rect(r, PRETO)
		draw_rect(r.grow(-1), METAL_CLARO if not sel else AMARELO)
		draw_rect(Rect2(r.position + Vector2(2, 3), Vector2(14, 1)), CINZA_ESC)
	if sel and fmod(t, 0.6) < 0.4:                        # setinhas de W/S ao lado do canal escolhido
		Fonte.desenhar(self, "W", JANELA + Vector2(cx + 9, y - 8), AMARELO)
		Fonte.desenhar(self, "S", JANELA + Vector2(cx + 9, y + 3), AMARELO)
	var cor_nome := VERDE_LIMA if ok else (AMARELO if sel else BRANCO_SUJO)
	Fonte.centralizado(self, NOMES[i], JANELA.x + cx + 0.5, JANELA.y + PLACA_Y, cor_nome)


## Quanto falta de estabilidade: enche enquanto os três estão na faixa e zera se algum sair.
func _barra_estavel() -> void:
	var r := Rect2(JANELA + Vector2(8, TAM_JANELA.y - 7), Vector2(TAM_JANELA.x - 16, 4))
	draw_rect(r.grow(1), PRETO)
	draw_rect(r, CINZA_ESC)
	var f := 1.0 if acabou else clampf(tempo_estavel / TEMPO_OK, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * f), r.size.y)), VERDE_LIMA)


func _fundo_provisorio() -> void:
	draw_rect(Rect2(JANELA, TAM_JANELA), CINZA)
	draw_rect(Rect2(JANELA + Vector2(6, 6), Vector2(180, 100)), CINZA_ESC)
	draw_rect(Rect2(JANELA + Vector2(6, 6), Vector2(180, 1)), METAL)
	for x in range(10, 184, 8):                                                   # faixa amarela e preta
		draw_rect(Rect2(JANELA + Vector2(x, 108), Vector2(4, 3)), AMARELO)
	for i in TRILHOS_X.size():                                                    # plaquinhas
		draw_rect(Rect2(JANELA + Vector2(TRILHOS_X[i] - 15, PLACA_Y - 1), Vector2(30, 7)), FUNDO)


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
