extends Control
## Minigame "descontaminação" (REMOVE THE MOON DUST), no chuveiro do Habitat: o astronauta volta da superfície com o
## traje coberto de poeira lunar (regolito, que é cortante e gruda: no Apollo irritou olhos e pulmões). Na cabine, os
## 4 jatos de ar (teto, parede esquerda, parede direita, grade do chão) acendem um por vez; o jogador aperta a
## direção do jato aceso (W, A, D, S) e o ar sopra a poeira daquele lado. Errar a direção ou demorar conta um erro
## (taxa_erro diminui o que a tarefa rende); MAX_ERROS erros perdem a tarefa (sinal falhou). Não tira radiação: só
## poeira.
## A ideia do minigame (jatos de ar pressurizado em várias direções) veio do PR #22 (chinesdecroks).
## Arte (paleta Apollo, PixelAi; gerada por arte/minijogo_chuveiro.py) em res://assets/minigames/chuveiro/:
## cabine.png (192x121, bicos com centro em BICOS), astronauta_limpo.png e astronauta_sujo.png (30x56, mesma pose; a
## poeira são os pixels que diferem) e bico.png / bico_aceso.png (9x9). Se um arquivo faltar, o minigame desenha uma
## versão provisória no lugar dele. Jatos de ar, poeira voando, moldura e textos são animados aqui.
## Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const DIR_ARTE := "res://assets/minigames/chuveiro/"

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
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const AZUL := Color("#4f8fba")
const CIANO := Color("#73bed3")
const CIANO_BRILHO := Color("#a4dddb")
const POEIRA := [Color("#394a50"), Color("#577277"), Color("#819796"), Color("#a8b5b2")]   # regolito: cinza

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                  # canto da cabine (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# dentro da cabine: onde fica cada bico (centro) e o astronauta (centro dos pés)
const BICOS := {"cima": Vector2(96, 19), "esquerda": Vector2(33, 57), "direita": Vector2(158, 57),
	"baixo": Vector2(96, 105)}
const PES := Vector2(96, 98)                     # o astronauta (30x56) fica com o canto em (81, 42)
const TAM_PROVISORIO := Vector2(30, 52)          # astronauta desenhado enquanto não há arte
const TECLAS := {"cima": "W", "esquerda": "A", "direita": "D", "baixo": "S"}

const PASSOS := 8                                # jatos na sequência (2 de cada lado)
const TEMPO_PASSO := 1.8                         # segundos para apertar a direção do jato aceso (era 2.2: calmo demais)
const TEMPO_PRONTO := 0.8                        # READY antes do primeiro jato: dá tempo de ler a cabine
const TEMPO_SOPRO := 0.45                        # o jato sopra por este tempo depois do acerto
const TEMPO_FIM := 1.2
const MAX_ERROS := 3

var demo := false
var sequencia: Array[String] = []
var passo := 0                                   # quantos jatos já acertou
var acertos := 0
var erros := 0
var perdeu := false
var acabou := false
var t := 0.0
var t_passo := 0.0                               # quanto falta para o jato aceso apagar (erro por demora)
var t_pronto := TEMPO_PRONTO                     # > 0: ainda no READY (nenhum jato aceso, o tempo não corre)
var t_sopro := 0.0
var lado_sopro := ""
var t_erro := 0.0
var t_fim := -1.0
var t_demo := 0.0
var mensagem := ""
var cor_mensagem := AMARELO
var poeira: Array = []                           # [pixel na cabine, cor, lado mais perto] ainda grudados no traje
var voando: Array = []                           # [pos, vel, cor] poeira soprada para longe
var ar: Array = []                               # [pos, vel, vida] riscos de ar saindo do bico

var tex_cabine: Texture2D
var tex_limpo: Texture2D
var tex_sujo: Texture2D
var tex_bico: Texture2D
var tex_bico_aceso: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	tex_cabine = _textura("cabine")
	tex_limpo = _textura("astronauta_limpo")
	tex_sujo = _textura("astronauta_sujo")
	tex_bico = _textura("bico")
	tex_bico_aceso = _textura("bico_aceso")
	_montar_sequencia()
	_montar_poeira()
	t_passo = TEMPO_PASSO


func _textura(nome: String) -> Texture2D:
	var c := DIR_ARTE + nome + ".png"
	return load(c) if ResourceLoader.exists(c) else null


## 2 jatos de cada lado, embaralhados, sem o mesmo lado duas vezes seguidas.
func _montar_sequencia() -> void:
	var lados: Array = TECLAS.keys() + TECLAS.keys()
	for tentativa in 50:
		lados.shuffle()
		var ok := true
		for i in range(1, lados.size()):
			if lados[i] == lados[i - 1]:
				ok = false
				break
		if ok:
			break
	sequencia.assign(lados)


## A poeira grudada no traje: com a arte, os pixels em que o astronauta sujo difere do limpo; sem ela, manchas
## sorteadas dentro do astronauta provisório. Cada pixel é do lado (bico) mais perto dele.
func _montar_poeira() -> void:
	var canto := _canto_astronauta()
	if tex_limpo and tex_sujo:
		var limpo := tex_limpo.get_image()
		var sujo := tex_sujo.get_image()
		for y in sujo.get_height():
			for x in sujo.get_width():
				var cs := sujo.get_pixel(x, y)
				if cs.a > 0.5 and (x >= limpo.get_width() or y >= limpo.get_height() or not cs.is_equal_approx(limpo.get_pixel(x, y))):
					var p := canto + Vector2(x, y)
					poeira.append([p, cs, _lado_de(p)])
	else:
		for i in 140:
			var p := canto + Vector2(randi_range(2, int(TAM_PROVISORIO.x) - 3), randi_range(8, int(TAM_PROVISORIO.y) - 3))
			poeira.append([p, POEIRA[randi_range(0, POEIRA.size() - 1)], _lado_de(p)])


func _canto_astronauta() -> Vector2:
	var tam := tex_sujo.get_size() if tex_sujo else TAM_PROVISORIO
	return (PES - Vector2(tam.x / 2.0, tam.y)).floor()


func _lado_de(p: Vector2) -> String:
	var melhor := ""
	var d := INF
	for lado in BICOS:
		var dd: float = p.distance_squared_to(BICOS[lado])
		if dd < d:
			d = dd
			melhor = lado
	return melhor


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
	t_sopro = maxf(0.0, t_sopro - delta)
	t_erro = maxf(0.0, t_erro - delta)
	if t_pronto > 0.0 and not acabou:
		t_pronto -= delta
	elif not acabou:
		var apertou := _direcao_apertada()
		if demo:
			t_demo += delta
			apertou = sequencia[passo] if t_demo > 0.5 else ""
		if apertou != "":
			t_demo = 0.0
			if apertou == sequencia[passo]:
				_acertar(apertou)
			else:
				_errar("WRONG JET")
		else:
			t_passo -= delta
			if t_passo <= 0.0:
				_errar("TOO SLOW")
	_animar(delta)
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
	queue_redraw()


func _direcao_apertada() -> String:
	for lado in TECLAS:
		if Input.is_action_just_pressed(lado):
			return lado
	return ""


## Acertou o jato aceso: ele sopra, a poeira daquele lado sai voando (metade do que sobrou dela, e tudo no último
## jato do lado) e o próximo jato acende.
func _acertar(lado: String) -> void:
	acertos += 1
	passo += 1
	lado_sopro = lado
	t_sopro = TEMPO_SOPRO
	var restantes_do_lado := sequencia.slice(passo).count(lado)
	var do_lado := poeira.filter(func(p): return p[2] == lado)
	var tirar := do_lado.size() if restantes_do_lado == 0 else ceili(do_lado.size() / 2.0)
	do_lado.shuffle()
	for p in do_lado.slice(0, tirar):
		poeira.erase(p)
		var fora: Vector2 = (p[0] - BICOS[lado]).normalized()
		voando.append([p[0], fora * randf_range(40, 90) + Vector2(randf_range(-15, 15), randf_range(-15, 15)), p[1]])
	if passo >= PASSOS:
		acabou = true
		t_fim = TEMPO_FIM
		poeira.clear()
		_avisar("SUIT CLEAN!", VERDE_LIMA)
	else:
		t_passo = TEMPO_PASSO
		mensagem = ""


func _errar(txt: String) -> void:
	erros += 1
	t_erro = 0.4
	t_passo = TEMPO_PASSO
	if erros >= MAX_ERROS:
		perdeu = true
		acabou = true
		t_fim = TEMPO_FIM + 0.6
		_avisar("TOO MANY ERRORS - TASK FAILED", VERMELHO_CLARO)
	else:
		_avisar("%s (%d/%d)" % [txt, erros, MAX_ERROS], VERMELHO_CLARO)


func _avisar(txt: String, cor: Color) -> void:
	mensagem = txt
	cor_mensagem = cor


## Fração dos lances errados (direção errada ou demora).
func taxa_erro() -> float:
	return erros / maxf(1.0, float(erros + acertos))


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça.
func comecou() -> bool:
	return erros > 0 or acertos > 0


func _animar(delta: float) -> void:
	if t_sopro > 0.0 and randf() < 60.0 * delta:     # riscos de ar saindo do bico em direção ao astronauta
		var de: Vector2 = BICOS[lado_sopro]
		var para := PES - Vector2(0, 26)
		var dir := (para - de).normalized()
		var lado := Vector2(-dir.y, dir.x) * randf_range(-6, 6)
		ar.append([de + lado, dir * randf_range(110, 160), randf_range(0.25, 0.45)])
	for a in ar:
		a[0] += a[1] * delta
		a[2] -= delta
	ar = ar.filter(func(a): return a[2] > 0.0)
	for v in voando:
		v[0] += v[1] * delta
		v[1] *= 0.96
		v[1].y += 30.0 * delta
	voando = voando.filter(func(v): return Rect2(Vector2.ZERO, TAM_JANELA).has_point(v[0]))


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "REMOVE THE MOON DUST", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "%d/%d" % [passo, PASSOS], PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	if tex_cabine:
		draw_texture(tex_cabine, JANELA)
	else:
		_cabine_provisoria()
	_astronauta()
	for lado in BICOS:
		_bico(lado)
	for a in ar:
		_px(a[0], CIANO_BRILHO if a[2] > 0.2 else CIANO)
		_px(a[0] - (a[1] as Vector2).normalized() * 2.0, CIANO)
	for v in voando:
		_px(v[0], v[2])
	if t_erro > 0.0:
		draw_rect(Rect2(JANELA, TAM_JANELA), Color(VERMELHO_CLARO, 0.25 * t_erro / 0.4))
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if mensagem != "":
		Fonte.centralizado(self, mensagem, 160, y_txt, cor_mensagem)
	elif t_pronto > 0.0:
		Fonte.centralizado(self, "READY...", 160, y_txt, AMARELO)
	else:
		Fonte.centralizado_com_teclas(self, "PRESS THE LIT JET KEY: [W] [A] [S] [D]", 160, y_txt, BRANCO_SUJO, VERMELHO_CLARO)


func _px(p: Vector2, cor: Color) -> void:
	if Rect2(Vector2.ZERO, TAM_JANELA).has_point(p):
		draw_rect(Rect2(JANELA + p.floor(), Vector2.ONE), cor)


## O astronauta limpo, com a poeira que ainda sobrou por cima (cada pixel some quando o jato do lado dele sopra).
func _astronauta() -> void:
	var canto := _canto_astronauta()
	if tex_limpo:
		draw_texture(tex_limpo, JANELA + canto)
	else:
		_astronauta_provisorio(canto)
	for p in poeira:
		_px(p[0], p[1])


## Bico de ar: o aceso pisca (com a tecla dele do lado); os outros ficam apagados.
func _bico(lado: String) -> void:
	var c: Vector2 = BICOS[lado]
	var aceso := not acabou and t_pronto <= 0.0 and passo < sequencia.size() and sequencia[passo] == lado
	var piscando := aceso and (fmod(t, 0.4) < 0.28 or t_passo < 0.8)
	var soprando := t_sopro > 0.0 and lado_sopro == lado
	if tex_bico and tex_bico_aceso:
		var tex := tex_bico_aceso if (piscando or soprando) else tex_bico
		draw_texture(tex, JANELA + c - (tex.get_size() / 2.0).floor())
	else:
		draw_rect(Rect2(JANELA + c - Vector2(4, 4), Vector2(9, 9)), PRETO)
		draw_rect(Rect2(JANELA + c - Vector2(3, 3), Vector2(7, 7)), METAL)
		draw_rect(Rect2(JANELA + c - Vector2(2, 2), Vector2(5, 5)), CIANO if (piscando or soprando) else CINZA_ESC)
		if piscando or soprando:
			draw_rect(Rect2(JANELA + c - Vector2(1, 1), Vector2(3, 3)), CIANO_BRILHO)
	if aceso:                 # a tecla do jato aceso, do lado de dentro da cabine (a do chão, embaixo, longe das botas)
		var dentro := Vector2(0, 9) if lado == "baixo" else (PES - Vector2(0, 26) - c).normalized() * 11.0
		var cor := AMARELO if t_passo > 0.8 or fmod(t, 0.2) < 0.1 else VERMELHO_CLARO
		var cx := JANELA.x + c.x + dentro.x + 0.5
		var y := JANELA.y + c.y + dentro.y - 2
		draw_rect(Rect2(Vector2(round(cx - 1.5) - 2, y - 2), Vector2(8, 10)), Color(PRETO, 0.8))   # plaquinha: lê em fundo claro
		Fonte.centralizado(self, TECLAS[lado], cx, y, cor)


func _cabine_provisoria() -> void:
	draw_rect(Rect2(JANELA, TAM_JANELA), CINZA_ESC)
	draw_rect(Rect2(JANELA + Vector2(18, 16), Vector2(156, 92)), CINZA)
	draw_rect(Rect2(JANELA + Vector2(18, 108), Vector2(156, 13)), FUNDO)
	for x in range(22, 172, 6):
		draw_rect(Rect2(JANELA + Vector2(x, 111), Vector2(3, 1)), CINZA_ESC)
		draw_rect(Rect2(JANELA + Vector2(x, 115), Vector2(3, 1)), CINZA_ESC)
	draw_rect(Rect2(JANELA + Vector2(18, 16), Vector2(156, 1)), METAL_CLARO)
	draw_rect(Rect2(JANELA + Vector2(40, 22), Vector2(2, 80)), AZUL)
	draw_rect(Rect2(JANELA + Vector2(150, 22), Vector2(2, 80)), LARANJA)


func _astronauta_provisorio(canto: Vector2) -> void:
	var w := TAM_PROVISORIO.x
	var h := TAM_PROVISORIO.y
	var o := JANELA + canto
	draw_rect(Rect2(o + Vector2(w / 2.0 - 8, 0), Vector2(16, 14)), BRANCO)                # capacete
	draw_rect(Rect2(o + Vector2(w / 2.0 - 5, 4), Vector2(10, 6)), AZUL)                   # visor
	draw_rect(Rect2(o + Vector2(w / 2.0 - 4, 5), Vector2(3, 2)), CIANO_BRILHO)
	draw_rect(Rect2(o + Vector2(4, 14), Vector2(w - 8, 22)), BRANCO)                      # tronco
	draw_rect(Rect2(o + Vector2(0, 16), Vector2(4, 18)), BRANCO_SUJO)                     # braços
	draw_rect(Rect2(o + Vector2(w - 4, 16), Vector2(4, 18)), BRANCO_SUJO)
	draw_rect(Rect2(o + Vector2(w / 2.0 - 4, 20), Vector2(8, 6)), METAL)                  # painel do peito
	draw_rect(Rect2(o + Vector2(6, 36), Vector2(7, h - 36)), BRANCO_SUJO)                # pernas
	draw_rect(Rect2(o + Vector2(w - 13, 36), Vector2(7, h - 36)), BRANCO_SUJO)


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
