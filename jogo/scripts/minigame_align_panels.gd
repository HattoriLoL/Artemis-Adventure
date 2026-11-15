extends Control
## Minigame "mirar os painéis solares" (AIM THE SOLAR PANELS), no computador da sala de Energia: pela câmera
## externa, o astronauta vê os 3 painéis solares da base no polo sul da Lua, onde o Sol fica baixo, perto do
## horizonte. Um painel de cada vez: A/D gira o painel no eixo vertical e a linha de mira mostra para onde ele aponta;
## de frente para o Sol (dentro de TOLERANCIA graus) por TEMPO_TRAVAR segundos, o painel trava e brilha. Com os 3
## travados, a tarefa termina. Não tem falha, mas passar direto pelo Sol (sair da mira ainda girando) ou forçar o
## painel no batente é erro: taxa_erro diminui o que a tarefa rende (o primeiro erro sai de graça). O +POWER dela
## já é multiplicado pela luz do local de pouso em recursos.json.
## A ideia e a mecânica (girar o painel com A/D até alinhar e segurar) vieram do PR #14 (chinesdecroks) e do card
## tarefas/card_align_panels.md (3 painéis, um de cada vez, seguindo o Sol).
## Arte (paleta Apollo, PixelAi) em res://assets/minigames/paineis_mira/: fundo.png (192x121, a vista da câmera) e
## painel.png / painel_brilho.png (tiras com QUADROS quadros, de -ANGULO_MAX a +ANGULO_MAX graus). Se um arquivo
## faltar, o minigame desenha uma versão provisória no lugar dele. O Sol, a mira e os textos são desenhados aqui.
## Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e `demo`.

signal terminou
signal cancelou
signal falhou                                    # nunca emitido aqui: com ele e comecou(), o mapa trata fechar
                                                 # depois de começar como desistência (gasta a ação, não rende)

const Fonte = preload("res://scripts/fonte.gd")
const DIR_ARTE := "res://assets/minigames/paineis_mira/"

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

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                   # canto do fundo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# dentro do fundo: o pé do poste de cada painel e o quadro da tira
const LUGARES := [Vector2(40, 100), Vector2(96, 100), Vector2(152, 100)]
const TAM_QUADRO := Vector2(32, 32)
const PE_NO_QUADRO := Vector2(16, 31)             # onde fica o pé do poste dentro do quadro
const QUADROS := 7
const ANGULO_MAX := 60.0                           # o quadro 0 é -60° e o último é +60°
const CEU := Rect2(30, 20, 130, 38)                # onde o Sol pode nascer: céu livre, longe do REC e da antena
const PROFUNDIDADE := 90.0                         # "distância" até o Sol: com 90, todo alvo fica dentro de ±57°

const VELOCIDADE := 50.0                           # graus por segundo segurando A/D
const TOLERANCIA := 6.0
const TEMPO_TRAVAR := 1.0
const FOLGA_INICIAL := 25.0                        # nenhum painel nasce a menos disso do Sol
const TEMPO_FIM := 1.2

var demo := false
var sol := Vector2.ZERO
var angulos: Array[float] = []
var travados: Array[bool] = []
var atual := 0                                     # o painel que o jogador está girando
var t_mirando := 0.0
var mexeu := false                                 # já girou algum painel (comecou)
var erros := 0                                     # passou direto pelo Sol ou forçou o batente
var t_erro := 0.0                                  # aviso na tela
var msg_erro := ""
var no_batente := false                            # já contou o batente (só conta de novo depois de sair dele)
var acabou := false
var t := 0.0
var t_fim := -1.0
var estrelas: Array = []

var tex_fundo: Texture2D
var tex_painel: Texture2D
var tex_brilho: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	tex_fundo = _textura("fundo")
	tex_painel = _textura("painel")
	tex_brilho = _textura("painel_brilho")
	sol = Vector2(randf_range(CEU.position.x, CEU.end.x), randf_range(CEU.position.y, CEU.end.y))
	for i in LUGARES.size():
		var a := randf_range(-ANGULO_MAX, ANGULO_MAX)
		for tentativa in 30:
			if absf(a - alvo(i)) >= FOLGA_INICIAL:
				break
			a = randf_range(-ANGULO_MAX, ANGULO_MAX)
		angulos.append(a)
		travados.append(false)
	for i in 40:
		estrelas.append(Vector2(randf_range(2, 190), randf_range(2, 60)))


func _textura(nome: String) -> Texture2D:
	var c := DIR_ARTE + nome + ".png"
	return load(c) if ResourceLoader.exists(c) else null


## O ângulo em que o painel i fica de frente para o Sol (girando no eixo vertical).
func alvo(i: int) -> float:
	var dx: float = sol.x - (LUGARES[i] as Vector2).x
	return clampf(rad_to_deg(atan2(dx, PROFUNDIDADE)), -ANGULO_MAX, ANGULO_MAX)


func mirando() -> bool:
	return not acabou and absf(angulos[atual] - alvo(atual)) <= TOLERANCIA


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
		var giro := Input.get_axis("esquerda", "direita")
		if demo:
			var falta := alvo(atual) - angulos[atual]
			giro = signf(falta) if absf(falta) > 1.0 else 0.0
		mexeu = mexeu or giro != 0.0
		var estava := mirando()
		angulos[atual] = clampf(angulos[atual] + giro * VELOCIDADE * delta, -ANGULO_MAX, ANGULO_MAX)
		if estava and not mirando() and giro != 0.0 and not demo:
			_errar("OVERSHOT THE SUN!")
		var batente := absf(angulos[atual]) >= ANGULO_MAX and giro != 0.0
		if batente and not no_batente and not demo:
			_errar("PANEL AT ITS LIMIT!")
		no_batente = batente
		if mirando():
			t_mirando += delta
			if t_mirando >= TEMPO_TRAVAR:
				_travar()
		else:
			t_mirando = 0.0
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			terminou.emit()
	queue_redraw()


func _errar(txt: String) -> void:
	erros += 1
	t_erro = 0.9
	msg_erro = txt


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça. Sem isso, dava para fechar um preparo ruim e
## jogar de novo até sair perfeito, e a perda de ganho por erro não valia nada.
func comecou() -> bool:
	return mexeu


## Fração de erros: o primeiro sai de graça (1 erro rende tudo), 2 ~ 83% do ganho, 3 ~ 71%.
func taxa_erro() -> float:
	return erros / (erros + 4.0)


func _travar() -> void:
	travados[atual] = true
	angulos[atual] = alvo(atual)
	t_mirando = 0.0
	if atual >= LUGARES.size() - 1:
		acabou = true
		t_fim = TEMPO_FIM
	else:
		atual += 1


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "AIM THE SOLAR PANELS", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "%d/%d" % [travados.count(true), LUGARES.size()], PAINEL.position + Vector2(12, 5),
		VERDE_LIMA)
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
	_sol()
	if not acabou:
		_mira(atual)
	for i in LUGARES.size():
		_painel(i)
	_barra_mira()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if acabou:
		Fonte.centralizado(self, "SOLAR ARRAY ALIGNED!", 160, y_txt, VERDE_LIMA)
	elif t_erro > 0.0:
		Fonte.centralizado(self, "%s (%d)" % [msg_erro, erros], 160, y_txt,
			VERMELHO_CLARO if fmod(t, 0.3) < 0.18 else AMARELO)
	elif mirando():
		Fonte.centralizado(self, "FACING THE SUN - HOLD IT...", 160, y_txt, VERDE_LIMA)
	else:
		Fonte.centralizado(self, "A/D: TURN PANEL %d TO FACE THE SUN" % (atual + 1), 160, y_txt, BRANCO_SUJO)


## O Sol baixo no horizonte: disco amarelo com um halo que pulsa de leve.
func _sol() -> void:
	var c := JANELA + sol
	var pulso := 0.5 + 0.5 * sin(t * 3.0)
	draw_circle(c, 9.0 + pulso, Color(AMARELO, 0.12))
	draw_circle(c, 6.5, Color(AMARELO, 0.3))
	draw_circle(c, 4.5, AMARELO)
	draw_circle(c, 2.5, BRANCO)


## Linha de mira do painel que está girando: sai do painel na direção para onde ele aponta (verde de frente pro Sol).
func _mira(i: int) -> void:
	var pe: Vector2 = LUGARES[i]
	var origem := pe + Vector2(0, -21)                  # o meio do painel (ele ocupa y 2..18 do quadro)
	var dx := tan(deg_to_rad(angulos[i])) * PROFUNDIDADE
	var fim := Vector2(origem.x + dx, sol.y)
	var cor := VERDE_LIMA if mirando() else Color(CIANO, 0.8)
	var passos := int(origem.distance_to(fim) / 3.0)
	for k in passos:
		if (k + int(t * 12.0)) % 3 == 0:
			continue
		var p := origem.lerp(fim, float(k) / maxf(1.0, passos))
		if Rect2(Vector2.ZERO, TAM_JANELA).has_point(p):
			draw_rect(Rect2(JANELA + p.floor(), Vector2.ONE), cor)


func _quadro(ang: float) -> int:
	return clampi(roundi((ang + ANGULO_MAX) / (2.0 * ANGULO_MAX) * (QUADROS - 1)), 0, QUADROS - 1)


## Um painel: o quadro da tira pelo ângulo (o travado usa a tira com brilho); o da vez ganha uma setinha.
func _painel(i: int) -> void:
	var pe: Vector2 = LUGARES[i]
	var canto := JANELA + pe - PE_NO_QUADRO
	var tex := tex_brilho if (travados[i] and tex_brilho) else tex_painel
	if tex:
		var q := _quadro(angulos[i])
		var larg := tex.get_width() / float(QUADROS)
		draw_texture_rect_region(tex, Rect2(canto, Vector2(larg, tex.get_height())),
			Rect2(q * larg, 0, larg, tex.get_height()))
	else:
		_painel_provisorio(i, canto)
	if travados[i]:
		draw_rect(Rect2(JANELA + pe + Vector2(-2, 2), Vector2(4, 2)), VERDE_LIMA)       # luz verde no pé
	elif i == atual and not acabou and fmod(t, 0.6) < 0.4:
		draw_colored_polygon(PackedVector2Array([JANELA + pe + Vector2(-3, 4), JANELA + pe + Vector2(3, 4),
			JANELA + pe + Vector2(0, 1)]), AMARELO)


func _painel_provisorio(i: int, canto: Vector2) -> void:
	var c := canto + Vector2(TAM_QUADRO.x / 2.0, TAM_QUADRO.y * 0.4)
	var larg := maxf(2.0, 24.0 * cos(deg_to_rad(angulos[i])))
	draw_rect(Rect2(canto + Vector2(TAM_QUADRO.x / 2.0 - 1, TAM_QUADRO.y * 0.4), Vector2(2, TAM_QUADRO.y * 0.6)), METAL)
	var r := Rect2(c - Vector2(larg / 2.0, 7), Vector2(larg, 14))
	draw_rect(r.grow(1), PRETO)
	draw_rect(r, VERDE_LIMA.lerp(AZUL, 0.5) if travados[i] else AZUL)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), CIANO)


## Quanto falta para travar o painel da vez (base do fundo).
func _barra_mira() -> void:
	var r := Rect2(JANELA + Vector2(8, TAM_JANELA.y - 7), Vector2(TAM_JANELA.x - 16, 4))
	draw_rect(r.grow(1), PRETO)
	draw_rect(r, CINZA_ESC)
	var f := 1.0 if acabou else clampf(t_mirando / TEMPO_TRAVAR, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * f), r.size.y)), VERDE_LIMA)


func _fundo_provisorio() -> void:
	draw_rect(Rect2(JANELA, TAM_JANELA), PRETO)
	for e in estrelas:
		draw_rect(Rect2(JANELA + (e as Vector2), Vector2.ONE), Color(BRANCO, 0.6))
	draw_rect(Rect2(JANELA + Vector2(0, 66), Vector2(192, 55)), CINZA_ESC)               # horizonte e chão
	draw_rect(Rect2(JANELA + Vector2(0, 66), Vector2(192, 1)), METAL)
	draw_rect(Rect2(JANELA + Vector2(0, 86), Vector2(192, 35)), CINZA)


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
