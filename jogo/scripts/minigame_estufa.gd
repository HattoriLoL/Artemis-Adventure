extends Control
## Minigame da estufa (WATER THE PLANTS), no estilo "segure a faixa em cima do alvo".
## Do lado do canteiro há um trilho vertical. Segurar E (ou o clique) faz o JATO subir; soltar faz ele cair.
## A GOTA (a umidade certa) sobe e desce sozinha. Com a gota dentro do jato, o crescimento enche e as 3 alfaces
## crescem; fora, ele esvazia. Cheio: plantas regadas, a tarefa conclui. Vazio: as plantas murcham e a rodada
## recomeça; depois de TENTATIVAS falhas a tarefa é perdida (sinal falhou). O tempo com a gota fora do jato é a
## taxa de erro (taxa_erro): diminui o que a tarefa rende.
## Arte do PixelAi (paleta Apollo) em res://assets/minigames/regar/; moldura, trilho e texto desenhados aqui.
## Contrato com o mapa: sinais `terminou` (concluiu), `falhou` (murchou TENTATIVAS vezes) e `cancelou` (X ou Esc),
## taxa_erro() e `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const TEX_CANTEIRO := preload("res://assets/minigames/regar/canteiro.png")
const TEX_ALFACE := preload("res://assets/minigames/regar/alface.png")   # 8 estágios + 2 de balanço, 31x29
const TEX_MURCHA := preload("res://assets/minigames/regar/alface_murcha.png")

const PRETO := Color("#090a14")
const NOITE := Color("#10141f")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const VERDE_ESC := Color("#25562e")
const VERDE := Color("#468232")
const VERDE_LIMA := Color("#a8ca58")
const AGUA := Color("#4f8fba")
const AGUA_CLARA := Color("#73bed3")
const AGUA_BRILHO := Color("#a4dddb")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")

# --- tela
const PAINEL := Rect2(36, 13, 228, 154)
const JANELA := Vector2(64, 29)                 # canto do canteiro (192x121) na tela
const BOTAO_X := Rect2(245, 17, 8, 8)
const VASOS := [46, 96, 146]                    # centro de cada vaso, no canteiro
const BICOS := [49, 95, 143]                    # gotejador de cada vaso
const Y_BICO := 49
const Y_TERRA := 91
const QUADRO := Vector2(31, 29)
const TRILHO := Rect2(42, 29, 10, 121)          # onde o jato e a gota andam
const BARRA := Rect2(55, 29, 4, 121)            # medidor de crescimento

# --- jogo (mexa aqui para deixar mais fácil ou mais difícil)
const ALT_JATO := 34.0                          # altura do jato, em pixels (maior = mais fácil)
const SUBIDA := 340.0                           # aceleração para cima segurando, px/s²
const GRAVIDADE := 300.0                        # aceleração para baixo soltando, px/s²
const VEL_MAX := 130.0                          # velocidade máxima do jato, px/s
const QUIQUE := 0.6                             # quanto o jato quica no fundo (0 = não quica)
const QUIQUE_MIN := 20.0                        # abaixo dessa velocidade ele só para (senão treme no fundo)
const T_IMPACTO := 0.2                          # duração do respingo e do achatamento ao bater no fundo
const VEL_GOTA := 44.0                          # velocidade da gota, px/s
const TROCA_GOTA := Vector2(0.6, 1.4)           # a gota escolhe um novo destino a cada 0,6 a 1,4 s
const ENCHE := 0.105                            # crescimento por segundo com a gota no jato
const ESVAZIA := 0.075                          # crescimento perdido por segundo com a gota fora
const COMECO := 0.3                             # crescimento no começo de cada rodada
const TENTATIVAS := 3
const MARGEM_ERRO := 4.0                        # a gota só conta como erro mais longe que isso do jato (px)

var demo := false
var e_liberado := false                         # o E que abriu o minigame ainda pode estar apertado
var t := 0.0
var segurando := false
var jato_y := 0.0                               # topo do jato, contado do topo do trilho
var jato_v := 0.0
var gota_y := 0.0                               # centro da gota, contado do topo do trilho
var gota_destino := 0.0
var t_gota := 0.0
var crescimento := COMECO                       # 0 a 1
var tentativa := 1
var estado := "jogando"                         # "jogando", "murchou" ou "pronto"
var t_estado := 0.0
var aviso := ""
var cor_aviso := BRANCO
var t_aviso := 0.0
var t_impacto := 0.0                            # > 0 logo depois de o jato bater no fundo
var forca_impacto := 0.0                        # 0 a 1: quão forte foi a batida (velocidade / VEL_MAX)
var t_jogando := 0.0                            # tempo jogando, somando as rodadas
var t_fora := 0.0                               # desse tempo, quanto a gota passou fora do jato


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	_nova_rodada()


func _input(ev: InputEvent) -> void:
	if estado != "jogando" or demo:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if BOTAO_X.grow(1).has_point(get_local_mouse_position()):
			cancelou.emit()
	elif ev.is_action_pressed("ui_cancel"):
		cancelou.emit()


func _process(delta: float) -> void:
	t += delta
	t_aviso = maxf(0.0, t_aviso - delta)
	t_impacto = maxf(0.0, t_impacto - delta)
	if estado == "jogando":
		segurando = _quer_subir()
		_mover_jato(delta)
		_mover_gota(delta)
		_crescer(delta)
	else:
		segurando = false
		t_estado -= delta
		if t_estado <= 0.0:
			_fim_da_pausa()
	queue_redraw()


func _nova_rodada() -> void:
	jato_y = TRILHO.size.y - ALT_JATO
	jato_v = 0.0
	gota_y = TRILHO.size.y * 0.6
	gota_destino = gota_y
	t_gota = 0.0
	crescimento = COMECO
	estado = "jogando"


func _quer_subir() -> bool:
	if demo:  # como um jogador: segura se o jato (com o embalo dele) está abaixo da gota
		return jato_y + ALT_JATO / 2.0 + jato_v * 0.25 > gota_y
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	if e_liberado and Input.is_action_pressed("usar"):
		return true
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		and not BOTAO_X.grow(1).has_point(get_local_mouse_position())


func _mover_jato(delta: float) -> void:
	jato_v += (-SUBIDA if segurando else GRAVIDADE) * delta
	jato_v = clampf(jato_v, -VEL_MAX, VEL_MAX)
	jato_y += jato_v * delta
	var fundo := TRILHO.size.y - ALT_JATO
	if jato_y > fundo:
		jato_y = fundo
		if jato_v > QUIQUE_MIN:                     # bateu no fundo: quica, achata e respinga
			forca_impacto = clampf(jato_v / VEL_MAX, 0.0, 1.0)
			t_impacto = T_IMPACTO
			jato_v = -jato_v * QUIQUE
		else:
			jato_v = 0.0                            # devagar demais: só para, sem ficar tremendo
	if jato_y < 0.0:                                # no topo para seco, sem quicar
		jato_y = 0.0
		jato_v = 0.0


func _mover_gota(delta: float) -> void:
	t_gota -= delta
	if t_gota <= 0.0:
		t_gota = randf_range(TROCA_GOTA.x, TROCA_GOTA.y)
		gota_destino = randf_range(6.0, TRILHO.size.y - 6.0)
	gota_y = move_toward(gota_y, gota_destino, VEL_GOTA * delta)


func _gota_no_jato() -> bool:
	return gota_y >= jato_y and gota_y <= jato_y + ALT_JATO


## Fração do tempo de jogo com a gota longe do jato (mais que MARGEM_ERRO): passar raspando não conta.
func taxa_erro() -> float:
	return t_fora / maxf(0.001, t_jogando)


func _crescer(delta: float) -> void:
	t_jogando += delta
	if maxf(jato_y - gota_y, gota_y - (jato_y + ALT_JATO)) > MARGEM_ERRO:
		t_fora += delta
	crescimento += (ENCHE if _gota_no_jato() else -ESVAZIA) * delta
	if crescimento >= 1.0:
		crescimento = 1.0
		estado = "pronto"
		t_estado = 1.6
		_avisar("PLANTS WATERED!", VERDE_LIMA, 2.0)
	elif crescimento <= 0.0:
		crescimento = 0.0
		estado = "murchou"
		t_estado = 1.6
		if tentativa < TENTATIVAS:
			_avisar("THE PLANTS WILTED! TRY AGAIN", VERMELHO_CLARO, 1.6)
		else:
			_avisar("THE PLANTS WILTED - TASK FAILED", VERMELHO_CLARO, 1.6)


func _fim_da_pausa() -> void:
	if estado == "pronto":
		set_process(false)
		terminou.emit()
	elif tentativa < TENTATIVAS:
		tentativa += 1
		_nova_rodada()
	else:
		set_process(false)
		falhou.emit()


func _avisar(txt: String, cor: Color, dur: float) -> void:
	aviso = txt
	cor_aviso = cor
	t_aviso = dur


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "WATER THE PLANTS", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "TRY %d/%d" % [tentativa, TENTATIVAS], PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	_botao_x()
	draw_rect(Rect2(JANELA - Vector2.ONE, Vector2(194, 123)), PRETO)
	draw_texture(TEX_CANTEIRO, JANELA)
	for i in VASOS.size():
		_vaso(i)
	_trilho()
	var y_txt := JANELA.y + 126
	if t_aviso > 0.0:
		Fonte.centralizado(self, aviso, 160, y_txt, cor_aviso)
	else:
		Fonte.centralizado(self, "HOLD E OR CLICK: KEEP THE DROP IN THE WATER", 160, y_txt, BRANCO_SUJO)


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


func _botao_x() -> void:
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)


func _vaso(i: int) -> void:
	var cx: float = JANELA.x + VASOS[i]
	var terra: float = JANELA.y + Y_TERRA
	if estado == "murchou":
		draw_texture(TEX_MURCHA, Vector2(cx - TEX_MURCHA.get_width() / 2, terra - TEX_MURCHA.get_height() + 1))
	else:
		var q := int(crescimento * 7.0)                 # estágio 0 a 7 conforme o crescimento
		if estado == "pronto":
			q = [8, 7, 9, 7][int(t / 0.3) % 4]          # balanço da planta pronta
		draw_texture_rect_region(TEX_ALFACE, Rect2(cx - 15, terra - QUADRO.y + 1, QUADRO.x, QUADRO.y),
			Rect2(Vector2(q * QUADRO.x, 0), QUADRO))
	# gotas caindo do gotejador enquanto o jogador segura
	if segurando:
		var bx: float = JANELA.x + BICOS[i]
		var queda: float = Y_TERRA - Y_BICO - 4
		for k in 3:
			var gy: float = JANELA.y + Y_BICO + 2 + fmod(t * 60.0 + k * 13.0, queda)
			draw_rect(Rect2(bx, gy, 1, 2), AGUA_CLARA)
			draw_rect(Rect2(bx, gy - 1, 1, 1), AGUA_BRILHO)


func _trilho() -> void:
	var r := TRILHO
	draw_rect(r.grow(1), PRETO)
	draw_rect(r, NOITE)
	# jato (o que o jogador controla): azul quando a gota está dentro
	var dentro := _gota_no_jato() and estado == "jogando"
	var k := t_impacto / T_IMPACTO                  # 1 na batida, 0 quando o efeito acaba
	var achata := roundf(2.0 * forca_impacto * k)   # o jato encolhe até 2 px por um instante, com a base fixa
	var jato := Rect2(r.position.x + 1, r.position.y + roundf(jato_y) + achata, r.size.x - 2, ALT_JATO - achata)
	draw_rect(jato, AGUA if dentro else CINZA_ESC)
	draw_rect(Rect2(jato.position, Vector2(jato.size.x, 1)), AGUA_BRILHO if dentro else CINZA)
	draw_rect(Rect2(jato.position.x, jato.end.y - 1, jato.size.x, 1), AGUA_BRILHO if dentro else CINZA)
	# respingo: gotinhas saindo para os dois lados da base do trilho, num arco curto
	if t_impacto > 0.0 and forca_impacto > 0.25:
		var p := 1.0 - k
		var base := Vector2(r.position.x + r.size.x / 2.0, r.end.y - 2)
		for lado in [-1, 1]:
			for n in 2:
				var dx: float = lado * (3.0 + p * (4.0 + n * 3.0))
				var dy := -sin(p * PI) * (3.0 + n * 2.0) * forca_impacto
				var pos := (base + Vector2(dx, dy)).round()
				draw_rect(Rect2(pos, Vector2.ONE), AGUA_BRILHO if n == 0 else AGUA_CLARA)
	# gota (o alvo)
	var g := Vector2(r.position.x + r.size.x / 2.0, r.position.y + roundf(gota_y))
	draw_rect(Rect2(g.x - 1, g.y - 3, 2, 1), AGUA_BRILHO)
	draw_rect(Rect2(g.x - 2, g.y - 2, 4, 2), AGUA_CLARA)
	draw_rect(Rect2(g.x - 3, g.y, 6, 2), AGUA_CLARA)
	draw_rect(Rect2(g.x - 2, g.y + 2, 4, 1), AGUA)
	draw_rect(Rect2(g.x - 2, g.y - 1, 1, 1), BRANCO)
	# medidor de crescimento
	var b := BARRA
	draw_rect(b.grow(1), PRETO)
	draw_rect(b, NOITE)
	var h := roundf(b.size.y * crescimento)
	var cor := VERDE_LIMA if crescimento > 0.35 else (AMARELO if crescimento > 0.15 else VERMELHO_CLARO)
	if h > 0:
		draw_rect(Rect2(b.position.x, b.end.y - h, b.size.x, h), cor)


func _criar_teclas() -> void:
	# para a cena rodar sozinha com F6: no jogo, quem cria as teclas é o mapa
	if InputMap.has_action("usar"):
		return
	InputMap.add_action("usar")
	for k in [KEY_E, KEY_X, KEY_J, KEY_ENTER]:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event("usar", ev)
