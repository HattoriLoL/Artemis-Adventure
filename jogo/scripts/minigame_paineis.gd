extends Control
## Minigame "limpar os painéis solares" (CLEAN THE SOLAR PANELS), na superfície lunar em frente à Sala de Energia:
## o jogador move a escova com WASD / setas por cima dos 3 painéis e a poeira some ao passar a escova (não precisa
## apertar nada). A escova não sai da área dos painéis. Quando todas as manchas somem, o minigame fecha.
## Não tem falha, mas o tempo conta a partir do primeiro movimento: até TEMPO_IDEAL rende tudo; depois disso a poeira
## custa geração e taxa_erro sobe até TEMPO_ZERO (rende nada). O relógio fica no canto do painel.
## Arte (paleta Apollo) em res://assets/minigames/paineis/; poeira, nuvens de pó, brilho, moldura e textos animados
## aqui. Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e a
## variável `demo`.

signal terminou
signal cancelou
signal falhou                                    # nunca emitido aqui: com ele e comecou(), o mapa trata fechar
                                                 # depois de começar como desistência (gasta a ação, não rende)

const Fonte = preload("res://scripts/fonte.gd")
const TEX_CAMPO := preload("res://assets/minigames/paineis/campo.png")     # 192x121
const TEX_ESCOVA := preload("res://assets/minigames/paineis/escova.png")   # 18x24
const TEX_VEU := preload("res://assets/minigames/paineis/veu.png")         # 192x121, poeira fina só nas placas

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO_SUJO := Color("#c7cfcc")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const CIANO := Color("#73bed3")
const CIANO_CLARO := Color("#a4dddb")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                  # canto do campo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# posições dentro do campo
# placas por dentro da moldura (topo-esq, topo-dir, base-dir, base-esq): a da esquerda e a da direita são meio tortas
const PLACAS := [[Vector2(14, 9), Vector2(64, 9), Vector2(65, 98), Vector2(8, 98)],
	[Vector2(69, 9), Vector2(122, 9), Vector2(122, 98), Vector2(67, 98)],
	[Vector2(127, 9), Vector2(177, 9), Vector2(183, 98), Vector2(129, 98)]]
const AREA := Rect2(12, 12, 168, 84)             # por onde o meio das cerdas pode andar (só em cima dos painéis)
const CERDAS := Vector2(14, 6)                   # tamanho da parte da escova que limpa
const PEGA := Vector2(9, 20)                     # ponto do sprite da escova que fica no meio das cerdas

const VELOCIDADE := 80.0                         # pixels por segundo
const QTD_MANCHAS := 10
const TEMPO := 0.5                               # segundos com a escova em cima para uma mancha sumir
const RAIO_MIN := 3.5
const RAIO_MAX := 5.2
const DIST_MIN := 11.0                           # distância mínima entre manchas sorteadas
const TEMPO_BRILHO := 0.6                        # reflexo que passa no painel quando ele fica limpo
const TEMPO_FIM := 1.3
const TEMPO_IDEAL := 15.0                        # até aqui rende tudo (um jogador atento leva 10-13 s)
const TEMPO_ZERO := 45.0                         # aqui já não rende nada

var demo := false                                # o jogo coloca true no modo demo: o minigame se resolve sozinho
var pos_escova := Vector2(96, 54)
var manchas: Array = []                          # {pos, placa, limpo, fim, pixels: [[offset, cor, limiar]]}
var por_placa := [0, 0, 0]                       # manchas que cada painel tinha no começo
var t_brilho := [-1.0, -1.0, -1.0]
var po: Array = []                               # nuvens de pó: [pos, vel, vida, vida_total], dentro do campo
var t_po := 0.0
var limpando := false
var andando := false
var acabou := false
var t := 0.0
var t_fim := -1.0
var tempo := 0.0                                 # segundos limpando (conta a partir do primeiro movimento)
var comecou_a_andar := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	for i in QTD_MANCHAS:
		var placa := i % PLACAS.size()           # reparte as manchas entre os 3 painéis
		manchas.append(_criar_mancha(_sortear_pos(placa), placa))
		por_placa[placa] += 1


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
	for i in t_brilho.size():
		if t_brilho[i] >= 0.0:
			t_brilho[i] += delta
	_animar_po(delta)
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			terminou.emit()
		queue_redraw()
		return
	var dir := _direcao_demo() if demo else Input.get_vector("esquerda", "direita", "cima", "baixo")
	andando = dir != Vector2.ZERO
	comecou_a_andar = comecou_a_andar or andando
	if comecou_a_andar:
		tempo += delta
	pos_escova = (pos_escova + dir * VELOCIDADE * delta).clamp(AREA.position, AREA.end)
	_limpar(delta)
	queue_redraw()


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça. Sem isso, dava para fechar um preparo ruim e
## jogar de novo até sair perfeito, e a perda de ganho por erro não valia nada.
func comecou() -> bool:
	return comecou_a_andar


## Até TEMPO_IDEAL rende tudo; depois o ganho cai em linha reta até zero em TEMPO_ZERO (taxa 0,2 a 1,0 no mapa).
func taxa_erro() -> float:
	if tempo <= TEMPO_IDEAL:
		return 0.0
	return 0.2 + 0.8 * clampf((tempo - TEMPO_IDEAL) / (TEMPO_ZERO - TEMPO_IDEAL), 0.0, 1.0)


## Mancha nova: um borrão irregular de pixels de poeira. Cada pixel tem um limiar: ao limpar, as bordas somem
## primeiro e o miolo por último.
func _criar_mancha(pos: Vector2, placa: int) -> Dictionary:
	var r := randf_range(RAIO_MIN, RAIO_MAX)
	var pixels := []
	var lim := ceili(r) + 1
	for dy in range(-lim, lim + 1):
		for dx in range(-lim, lim + 1):
			var d := Vector2(dx, dy * 1.25).length() + randf_range(-0.9, 0.9)
			if d > r:
				continue
			var k := d / r
			var cor: Color
			if k < 0.35:
				cor = BRANCO_SUJO if randf() < 0.6 else METAL_CLARO
			elif k < 0.75:
				cor = METAL_CLARO if randf() < 0.75 else METAL
			else:
				cor = METAL if randf() < 0.7 else CINZA
			pixels.append([Vector2(dx, dy), cor, 0.25 + 0.75 * (1.0 - k) * randf_range(0.6, 1.0)])
	for k in randi_range(2, 5):                   # uns grãos soltos em volta
		var a := randf() * TAU
		pixels.append([(Vector2(cos(a), sin(a)) * (r + randf_range(1.0, 2.5))).round(), METAL, randf_range(0.1, 0.4)])
	# a mancha sai quando o último pixel some (o maior limiar), e não em limpo = 1: senão ela ficava invisível mas
	# contando, e o minigame não terminava depois de o jogador "limpar tudo"
	var fim := 0.0
	for px in pixels:
		fim = maxf(fim, px[2])
	return {"pos": pos, "placa": placa, "limpo": 0.0, "fim": minf(fim, 1.0), "pixels": pixels}


## x da borda esquerda e da direita da placa na linha y (dentro do campo).
func _bordas(placa: int, y: float) -> Vector2:
	var q: Array = PLACAS[placa]
	var k: float = (y - q[0].y) / (q[3].y - q[0].y)
	return Vector2(lerpf(q[0].x, q[3].x, k), lerpf(q[1].x, q[2].x, k))


func _sortear_pos(placa: int) -> Vector2:
	var melhor := Vector2.ZERO
	for tentativa in 30:                          # tenta não encostar numa mancha que já existe
		var y := randi_range(int(PLACAS[placa][0].y) + 7, int(PLACAS[placa][3].y) - 7)
		var b := _bordas(placa, y)
		var pos := Vector2(randi_range(ceili(b.x) + 7, floori(b.y) - 7), y)
		melhor = pos
		var livre := true
		for m in manchas:
			if m["pos"].distance_to(pos) < DIST_MIN:
				livre = false
				break
		if livre:
			break
	return melhor


func _limpar(delta: float) -> void:
	var area_cerdas := Rect2(pos_escova - CERDAS / 2.0, CERDAS)
	var meio_raio := Vector2(RAIO_MAX, RAIO_MAX)
	limpando = false
	for m in manchas.duplicate():
		if not area_cerdas.intersects(Rect2(m["pos"] - meio_raio, meio_raio * 2.0)):
			continue
		limpando = true
		m["limpo"] += delta / TEMPO
		if m["limpo"] >= m["fim"]:
			manchas.erase(m)
			_soltar_po(m["pos"], 6)
			if _restam(m["placa"]) == 0:
				t_brilho[m["placa"]] = 0.0
			if manchas.is_empty():
				acabou = true
				t_fim = TEMPO_FIM
	if limpando:
		t_po -= delta
		if t_po <= 0.0:
			t_po = 0.04
			_soltar_po(pos_escova + Vector2(randf_range(-6, 6), 2), 1)


func _restam(placa: int) -> int:
	return manchas.filter(func(m): return m["placa"] == placa).size()


## Demo: vai até a mancha mais perto e fica em cima até ela sumir.
func _direcao_demo() -> Vector2:
	if manchas.is_empty():
		return Vector2.ZERO
	var alvo: Vector2 = manchas[0]["pos"]
	for m in manchas:
		if m["pos"].distance_to(pos_escova) < alvo.distance_to(pos_escova):
			alvo = m["pos"]
	var falta := alvo - pos_escova
	return Vector2.ZERO if falta.length() < 1.5 else falta.normalized()


## Pó levantado pela escova: sobe e cai devagar (gravidade da Lua) e vai sumindo.
func _soltar_po(pos: Vector2, n: int) -> void:
	for k in n:
		var vida := randf_range(0.5, 1.0)
		po.append([pos + Vector2(randf_range(-2, 2), randf_range(-1, 1)),
			Vector2(randf_range(-22, 22), randf_range(-28, -8)), vida, vida])


func _animar_po(delta: float) -> void:
	for p in po:
		p[1].y += 18.0 * delta
		p[1] *= 1.0 - 1.2 * delta
		p[0] += p[1] * delta
		p[2] -= delta
	po = po.filter(func(p): return p[2] > 0.0)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "CLEAN THE SOLAR PANELS", PAINEL.position.x + PAINEL.size.x / 2.0,
		PAINEL.position.y + 5, AMARELO)
	Fonte.desenhar(self, "%d/%d" % [QTD_MANCHAS - manchas.size(), QTD_MANCHAS], PAINEL.position + Vector2(12, 5),
		VERDE_LIMA)
	var relogio := "%ds" % floori(tempo)
	var cor_relogio := VERDE_LIMA if tempo <= TEMPO_IDEAL else (AMARELO if fmod(t, 0.5) < 0.3 else VERMELHO_CLARO)
	Fonte.desenhar(self, relogio, Vector2(BOTAO_X.position.x - 6 - Fonte.largura(relogio), PAINEL.position.y + 5),
		cor_relogio)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	draw_texture(TEX_CAMPO, JANELA)
	_estrelas()
	for i in PLACAS.size():
		_placa(i)
	for m in manchas:
		_mancha(m)
	for p in po:
		var k: float = p[2] / p[3]
		_px(JANELA + p[0], Color(BRANCO_SUJO if k > 0.6 else METAL_CLARO, clampf(k * 1.4, 0.0, 0.9)))
	_escova()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if acabou:
		Fonte.centralizado(self, "PANELS ARE CLEAN!", 160, y_txt, VERDE_LIMA)
	elif tempo > TEMPO_IDEAL:
		Fonte.centralizado(self, "HURRY - DUSTY PANELS LOSE POWER", 160, y_txt, AMARELO)
	else:
		Fonte.centralizado(self, "MOVE THE BRUSH OVER THE DUST", 160, y_txt, BRANCO_SUJO)


func _px(p: Vector2, cor: Color) -> void:
	draw_rect(Rect2(p.floor(), Vector2.ONE), cor)


## Umas estrelas piscando no céu, acima dos painéis.
func _estrelas() -> void:
	for e in [Vector2(5, 2), Vector2(41, 4), Vector2(97, 1), Vector2(150, 3), Vector2(187, 6)]:
		if fmod(t * 0.7 + e.x * 0.13, 1.0) < 0.75:
			_px(JANELA + e, BRANCO if fmod(t + e.y, 1.6) < 0.2 else BRANCO_SUJO)


## Um painel: véu de poeira que some conforme as manchas dele somem, o LED de cima (vermelho piscando enquanto
## sujo, verde limpo) e o reflexo que atravessa o painel quando ele fica limpo (e de novo, os três, no fim).
func _placa(i: int) -> void:
	var q: Array = PLACAS[i]
	var x0 := minf(q[0].x, q[3].x)
	var r := Rect2(x0, q[0].y, maxf(q[1].x, q[2].x) - x0 + 1, q[3].y - q[0].y + 1)   # caixa em volta da placa
	var sujeira := float(_restam(i)) / maxf(1.0, por_placa[i])
	if sujeira > 0.0:
		draw_texture_rect_region(TEX_VEU, Rect2(JANELA + r.position, r.size), r, Color(1, 1, 1, sujeira))
	var led := JANELA + Vector2(roundf((q[0].x + q[1].x) / 2.0), q[0].y - 3)
	draw_rect(Rect2(led - Vector2(1, 1), Vector2(3, 3)), PRETO)
	var cor_led := VERDE_LIMA if sujeira == 0.0 else (VERMELHO if fmod(t + i * 0.3, 1.0) < 0.5 else CINZA_ESC)
	_px(led, cor_led)
	var tb: float = t_brilho[i]
	if acabou and t_fim < TEMPO_FIM - 0.5:
		tb = fmod(TEMPO_FIM - 0.5 - t_fim + i * 0.12, TEMPO_BRILHO * 1.4)
	if tb < 0.0 or tb > TEMPO_BRILHO:
		return
	# faixa diagonal clara indo da esquerda para a direita, só dentro da placa
	var xb := lerpf(r.position.x - r.size.y * 0.5 - 6.0, r.end.x + 6.0, tb / TEMPO_BRILHO)
	for y in range(int(r.position.y), int(r.end.y)):
		var b := _bordas(i, y)
		for k in 5:
			var x := roundi(xb + (r.end.y - y) * 0.5) + k
			if x < roundi(b.x) or x > roundi(b.y):
				continue
			var cor := BRANCO if k == 2 else (CIANO_CLARO if k in [1, 3] else CIANO)
			draw_rect(Rect2(JANELA + Vector2(x, y), Vector2.ONE), Color(cor, 0.85 if k == 2 else 0.5))


func _mancha(m: Dictionary) -> void:
	var c: Vector2 = JANELA + m["pos"]
	var limpo: float = m["limpo"]
	for p in m["pixels"]:
		if limpo < p[2]:
			_px(c + p[0], p[1])


## A escova: sombra nas placas, balanço ao andar e esfregando de um lado para o outro enquanto limpa.
func _escova() -> void:
	var p := JANELA + pos_escova.round()
	var dx := 0.0
	var dy := 0.0
	if limpando:
		dx = roundf(sin(t * 38.0) * 1.5)
	elif andando:
		dy = -1.0 if fmod(t, 0.24) < 0.12 else 0.0
	draw_rect(Rect2(p + Vector2(-7, 4), Vector2(15, 1)), Color(PRETO, 0.45))
	draw_texture(TEX_ESCOVA, p - PEGA + Vector2(dx, dy))


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
