extends Control
## Minigame "consertar a irrigação" (FIX THE IRRIGATION), na Estufa: uma grade de 5x3 canos entre o tanque de água
## (esquerda) e as 3 camas de plantio (direita). O jogador move o cursor (setas ou WASD) e gira o cano (E) de 90 em
## 90 graus até a água sair do tanque e chegar às 3 camas. Vale qualquer caminho. Há um limite de giros: o mínimo que
## o tabuleiro sorteado precisa mais FOLGA; passou disso, a linha falha (sinal falhou). Os giros a mais contam como
## erro (taxa_erro diminui o que a tarefa rende).
## A ideia e o quebra-cabeça (o sorteio do caminho, o giro dos canos e a água correndo) vieram do PR #37 (DKuhn29).
## Arte (paleta Apollo) em res://assets/minigames/irrigacao/: fundo.png (192x121, com o tanque, os 15 encaixes e o
## lugar das camas), canos.png (5 peças de 22x22 na orientação básica; linha de cima seca, de baixo com água) e
## cama_seca.png / cama_molhada.png. Se um arquivo faltar, o minigame desenha uma versão provisória no lugar dele.
## Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const DIR_ARTE := "res://assets/minigames/irrigacao/"

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const VERDE := Color("#75a743")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const AZUL := Color("#4f8fba")
const CIANO := Color("#73bed3")
const MARROM := Color("#7a4841")
const TERRA := Color("#ad7757")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                   # canto do fundo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# dentro do fundo: a grade de canos, o tanque e as camas
const COLUNAS := 5
const LINHAS := 3
const CELULA := 22
const GRADE := Vector2(44, 25)                     # canto do encaixe (0, 0)
const LINHA_ENTRADA := 1                           # a água entra pela esquerda nesta linha (y 58)
const TANQUE := Rect2(6, 20, 32, 76)
const CAMA_X := 173.0                              # centro das camas (uma por linha)
const TAM_CAMA := Vector2(30, 20)

const FOLGA := 8                                   # giros a mais permitidos além do mínimo do tabuleiro
const MINIMO_GIROS := 9                            # o tabuleiro sorteado nunca precisa de menos que isso
const TEMPO_FIM := 1.2
const PASSO_DEMO := 0.15

# máscara de saídas de cada cano (bits) e para onde cada bit aponta
const N := 1
const L := 2
const S := 4
const O := 8
const DIRECOES := {1: Vector2i(0, -1), 2: Vector2i(1, 0), 4: Vector2i(0, 1), 8: Vector2i(-1, 0)}
# formas básicas na canos.png (índice = coluna da peça) e a máscara delas na orientação básica
const FORMAS := [1, 5, 3, 7, 15]                   # ponta (N), reto (N+S), curva (N+L), T (N+L+S), cruz

var demo := false
var solucao: Array[int] = []
var masc: Array[int] = []
var molhado: Array[bool] = []
var cursor := Vector2i(0, LINHA_ENTRADA)
var giros := 0
var minimo := 0                                    # giros que o tabuleiro sorteado precisa (pela solução)
var acabou := false
var perdeu := false
var e_liberado := false                            # o E que abriu a tarefa não pode já girar
var t := 0.0
var t_fim := -1.0
var t_demo := 0.0
var t_giro: Array[float] = []                      # brilho rápido no cano que acabou de girar

var tex_fundo: Texture2D
var tex_canos: Texture2D
var tex_seca: Texture2D
var tex_molhada: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	tex_fundo = _textura("fundo")
	tex_canos = _textura("canos")
	tex_seca = _textura("cama_seca")
	tex_molhada = _textura("cama_molhada")
	for i in COLUNAS * LINHAS:
		molhado.append(false)
		t_giro.append(0.0)
	_sortear_tabuleiro()
	minimo = _distancia_total()


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
	for i in t_giro.size():
		t_giro[i] = maxf(0.0, t_giro[i] - delta)
	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true
	if not acabou:
		if demo:
			_passo_demo(delta)
		elif e_liberado:
			_ler_teclado()
	else:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
	queue_redraw()


func _ler_teclado() -> void:
	if Input.is_action_just_pressed("esquerda"):
		cursor.x = maxi(cursor.x - 1, 0)
	if Input.is_action_just_pressed("direita"):
		cursor.x = mini(cursor.x + 1, COLUNAS - 1)
	if Input.is_action_just_pressed("cima"):
		cursor.y = maxi(cursor.y - 1, 0)
	if Input.is_action_just_pressed("baixo"):
		cursor.y = mini(cursor.y + 1, LINHAS - 1)
	if Input.is_action_just_pressed("usar"):
		_girar(cursor)


func _passo_demo(delta: float) -> void:
	t_demo += delta
	if t_demo < PASSO_DEMO:
		return
	t_demo = 0.0
	for r in LINHAS:
		for c in COLUNAS:
			if masc[r * COLUNAS + c] != solucao[r * COLUNAS + c]:
				cursor = Vector2i(c, r)
				_girar(cursor)
				return


## Gira o cano 90 graus no sentido horário. Cano vazio ou cruz não muda e não conta giro.
func _girar(pos: Vector2i) -> void:
	var i := pos.y * COLUNAS + pos.x
	if masc[i] == 0 or masc[i] == 15:
		return
	masc[i] = _rodar(masc[i])
	giros += 1
	t_giro[i] = 0.15
	_calcular_agua()
	if camas_molhadas() == LINHAS:
		acabou = true
		t_fim = TEMPO_FIM
	elif giros >= limite_giros():
		acabou = true
		perdeu = true
		t_fim = TEMPO_FIM + 0.6


func limite_giros() -> int:
	return minimo + FOLGA


## Os giros além do mínimo do tabuleiro, sobre todos os giros (0 = resolveu sem nenhum giro a mais).
func taxa_erro() -> float:
	return maxf(0.0, float(giros - minimo)) / maxf(1.0, float(giros))


## Já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como falha).
func comecou() -> bool:
	return giros > 0


# ---------------------------------------------------------------- o quebra-cabeça (do PR #37)
func _rodar(m: int) -> int:
	return ((m << 1) & 15) | (m >> 3)


func _oposto(d: int) -> int:
	return _rodar(_rodar(d))


func _distancia(i: int) -> int:
	var m := masc[i]
	var k := 0
	while m != solucao[i] and k < 4:
		m = _rodar(m)
		k += 1
	return k


func _distancia_total() -> int:
	var total := 0
	for i in masc.size():
		if masc[i] != 0 and masc[i] != 15:
			total += _distancia(i)
	return total


func _sortear_tabuleiro() -> void:
	for tentativa in 50:
		_gerar_solucao()
		masc.clear()
		for m in solucao:
			masc.append(m)
		for i in masc.size():
			for k in randi() % 4:
				masc[i] = _rodar(masc[i])
		_calcular_agua()
		if camas_molhadas() < LINHAS and _distancia_total() >= MINIMO_GIROS:
			return
	while camas_molhadas() == LINHAS:
		for i in masc.size():
			if masc[i] != 0 and masc[i] != 15:
				masc[i] = _rodar(masc[i])
				break
		_calcular_agua()


func _gerar_solucao() -> void:
	solucao.clear()
	for i in COLUNAS * LINHAS:
		solucao.append(0)
	solucao[LINHA_ENTRADA * COLUNAS] |= O
	for r in LINHAS:
		var linha := LINHA_ENTRADA
		for c in COLUNAS:
			var alvo := r if c == COLUNAS - 1 else randi() % LINHAS
			while linha != alvo:
				var prox := linha + signi(alvo - linha)
				_ligar(Vector2i(c, linha), Vector2i(c, prox))
				linha = prox
			if c < COLUNAS - 1:
				_ligar(Vector2i(c, linha), Vector2i(c + 1, linha))
		solucao[r * COLUNAS + COLUNAS - 1] |= L


func _ligar(a: Vector2i, b: Vector2i) -> void:
	var d := b - a
	var bit := N
	if d == Vector2i(1, 0):
		bit = L
	elif d == Vector2i(0, 1):
		bit = S
	elif d == Vector2i(-1, 0):
		bit = O
	solucao[a.y * COLUNAS + a.x] |= bit
	solucao[b.y * COLUNAS + b.x] |= _oposto(bit)


func _calcular_agua() -> void:
	for i in molhado.size():
		molhado[i] = false
	var inicio := LINHA_ENTRADA * COLUNAS
	if masc[inicio] & O == 0:
		return
	molhado[inicio] = true
	var fila: Array[int] = [inicio]
	while not fila.is_empty():
		var i: int = fila.pop_back()
		var c := i % COLUNAS
		var r := floori(i / float(COLUNAS))
		for d in DIRECOES:
			if masc[i] & d == 0:
				continue
			var v: Vector2i = Vector2i(c, r) + DIRECOES[d]
			if v.x < 0 or v.x >= COLUNAS or v.y < 0 or v.y >= LINHAS:
				continue
			var j := v.y * COLUNAS + v.x
			if molhado[j] or masc[j] & _oposto(d) == 0:
				continue
			molhado[j] = true
			fila.append(j)


func cama_molhada(r: int) -> bool:
	var i := r * COLUNAS + COLUNAS - 1
	return molhado[i] and masc[i] & L != 0


func camas_molhadas() -> int:
	var n := 0
	for r in LINHAS:
		if cama_molhada(r):
			n += 1
	return n


## A forma básica (coluna da canos.png) e quantos giros de 90 graus no sentido horário levam a ela até a máscara.
func _forma(m: int) -> Vector2i:
	for f in FORMAS.size():
		var b: int = FORMAS[f]
		for k in 4:
			if b == m:
				return Vector2i(f, k)
			b = _rodar(b)
	return Vector2i(-1, 0)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "FIX THE IRRIGATION", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "%d/%d" % [camas_molhadas(), LINHAS], PAINEL.position + Vector2(12, 5), VERDE_LIMA)
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
	for r in LINHAS:
		for c in COLUNAS:
			_cano(c, r)
	for r in LINHAS:
		_cama(r)
	if not acabou:                                       # cursor
		var cur := Rect2(JANELA + GRADE + Vector2(cursor) * CELULA, Vector2(CELULA, CELULA))
		var cor := AMARELO if fmod(t, 0.6) < 0.4 else BRANCO
		draw_rect(cur.grow(-1), cor, false, 1.0)
	_barra_giros()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if acabou and perdeu:
		Fonte.centralizado(self, "OUT OF TURNS - THE LINE FAILED", 160, y_txt, VERMELHO_CLARO)
	elif acabou:
		Fonte.centralizado(self, "IRRIGATION FIXED!", 160, y_txt, VERDE_LIMA)
	else:
		Fonte.centralizado(self, "ARROWS: MOVE   E: TURN THE PIPE", 160, y_txt, BRANCO_SUJO)


## Um cano: a peça básica da canos.png girada até a máscara (giros de 90 graus não estragam o pixel art).
func _cano(c: int, r: int) -> void:
	var i := r * COLUNAS + c
	var m := masc[i]
	if m == 0:
		return
	var centro := JANELA + GRADE + Vector2(c * CELULA, r * CELULA) + Vector2(CELULA, CELULA) / 2.0
	var cor_brilho := Color(BRANCO, t_giro[i] / 0.15 * 0.5)
	if tex_canos:
		var f := _forma(m)
		var linha := 1 if molhado[i] else 0
		draw_set_transform(centro, f.y * PI / 2.0, Vector2.ONE)
		draw_texture_rect_region(tex_canos, Rect2(-CELULA / 2.0, -CELULA / 2.0, CELULA, CELULA),
			Rect2(f.x * CELULA, linha * CELULA, CELULA, CELULA))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var cor := CIANO if molhado[i] else METAL
		var meia := CELULA / 2.0
		draw_rect(Rect2(centro - Vector2(3, 3), Vector2(6, 6)), cor)
		if m & N:
			draw_rect(Rect2(centro + Vector2(-3, -meia), Vector2(6, meia)), cor)
		if m & L:
			draw_rect(Rect2(centro + Vector2(0, -3), Vector2(meia, 6)), cor)
		if m & S:
			draw_rect(Rect2(centro + Vector2(-3, 0), Vector2(6, meia)), cor)
		if m & O:
			draw_rect(Rect2(centro + Vector2(-meia, -3), Vector2(meia, 6)), cor)
	if t_giro[i] > 0.0:
		draw_rect(Rect2(centro - Vector2(CELULA, CELULA) / 2.0, Vector2(CELULA, CELULA)), cor_brilho)


func _cama(r: int) -> void:
	var centro := JANELA + Vector2(CAMA_X, GRADE.y + r * CELULA + CELULA / 2.0)
	var molhada := cama_molhada(r)
	var tex := tex_molhada if molhada else tex_seca
	if tex:
		draw_texture(tex, (centro - tex.get_size() / 2.0).floor())
	else:
		var rc := Rect2(centro - TAM_CAMA / 2.0, TAM_CAMA)
		draw_rect(rc, PRETO)
		draw_rect(rc.grow(-1), MARROM if molhada else TERRA)
		if molhada:
			for k in 4:
				draw_rect(Rect2(rc.position + Vector2(5 + k * 6, 6), Vector2(2, 4)), VERDE_LIMA)


## Giros que ainda sobram (a barra esvazia; fica vermelha perto do fim).
func _barra_giros() -> void:
	var r := Rect2(JANELA + Vector2(8, TAM_JANELA.y - 7), Vector2(TAM_JANELA.x - 16, 4))
	draw_rect(r.grow(1), PRETO)
	draw_rect(r, CINZA_ESC)
	var resta := clampi(limite_giros() - giros, 0, limite_giros())
	var f := float(resta) / float(limite_giros())
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * f), r.size.y)), VERDE_LIMA if resta > 3 else VERMELHO_CLARO)
	Fonte.desenhar(self, "TURNS %d" % resta, JANELA + Vector2(8, TAM_JANELA.y - 15), BRANCO_SUJO if resta > 3 else
		VERMELHO_CLARO)


func _fundo_provisorio() -> void:
	draw_rect(Rect2(JANELA, TAM_JANELA), CINZA)
	draw_rect(Rect2(JANELA + TANQUE.position, TANQUE.size), PRETO)                      # tanque
	draw_rect(Rect2(JANELA + TANQUE.position + Vector2.ONE, TANQUE.size - Vector2(2, 2)), AZUL)
	draw_rect(Rect2(JANELA + Vector2(38, 55), Vector2(6, 6)), METAL)                    # saída do tanque
	for r in LINHAS:
		for c in COLUNAS:
			draw_rect(Rect2(JANELA + GRADE + Vector2(c * CELULA + 1, r * CELULA + 1), Vector2(CELULA - 2, CELULA - 2)),
				CINZA_ESC)
		draw_rect(Rect2(JANELA + Vector2(154, GRADE.y + r * CELULA + 8), Vector2(4, 6)), METAL)  # entrada das camas


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
