extends Control
## Minigame de Descontaminação (DECONTAMINATE SUIT) no chuveiro do Habitat.
## O astronauta entra na cabine cilíndrica coberto por poeira lunar (regolito) em 5 regiões:
## capacete/ombros, botas/pernas, braço esquerdo, braço direito e mochila dorsal PLSS.
## O jogador ativa os 5 bicos injetores de ar pressurizado (cima, baixo, esquerda, direita e duto dorsal)
## para expelir o regolito lunar pelo sistema de sucção e drenagem do piso.
## Teclas: W/CIMA (topo), S/BAIXO (piso), A/ESQUERDA (parede esq), D/DIREITA (parede dir), E/ESPAÇO (duto dorsal).
## O mouse também pode clicar diretamente nos bicos ou nas regiões para acionar os jatos.
## Contrato com o mapa: sinais `terminou`, `falhou`, `cancelou`, métodos `taxa_erro()`, `comecou()` e var `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")

const TEX_FUNDO := preload("res://assets/minigames/chuveiro/cabine_fundo.png")
const TEX_VIDRO := preload("res://assets/minigames/chuveiro/cabine_vidro.png")
const TEX_ASTRO := preload("res://assets/minigames/chuveiro/astronauta_cabine.png")
const TEX_POEIRA_CIMA := preload("res://assets/minigames/chuveiro/poeira_cima.png")
const TEX_POEIRA_BAIXO := preload("res://assets/minigames/chuveiro/poeira_baixo.png")
const TEX_POEIRA_ESQ := preload("res://assets/minigames/chuveiro/poeira_esquerda.png")
const TEX_POEIRA_DIR := preload("res://assets/minigames/chuveiro/poeira_direita.png")
const TEX_POEIRA_ATRAS := preload("res://assets/minigames/chuveiro/poeira_atras.png")
const TEX_JATO := preload("res://assets/minigames/chuveiro/jato_ar_folha.png")

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
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const CIANO := Color("#73bed3")
const CIANO_CLARO := Color("#a4dddb")
const REGOLITO := Color("#7a4841")
const REGOLITO_CLARO := Color("#c09473")

# --- Geometria da tela (320x180)
const PAINEL := Rect2(44, 7, 232, 166)
const JANELA := Vector2(64, 21)                  # Canto da cabine (192x121) na tela
const ASTRO_OFFSET := Vector2(72, 42)            # Posição do astronauta (48x64) dentro da janela
const BOTAO_X := Rect2(263, 11, 8, 8)
const BARRA_TOTAL := Rect2(52, 153, 216, 5)

# 5 Injetores / Zonas de descontaminação
# 0: Cima, 1: Baixo, 2: Esquerda, 3: Direita, 4: Atrás
const ZONAS := [
	{"nome": "HELMET", "tecla": "cima", "txt": "UP/W", "bico": Vector2(96, 12), "dir": Vector2(0, 1), "rot": PI / 2.0},
	{"nome": "BOOTS", "tecla": "baixo", "txt": "DOWN/S", "bico": Vector2(96, 102), "dir": Vector2(0, -1), "rot": -PI / 2.0},
	{"nome": "LEFT ARM", "tecla": "esquerda", "txt": "LEFT/A", "bico": Vector2(38, 58), "dir": Vector2(1, 0), "rot": 0.0},
	{"nome": "RIGHT ARM", "tecla": "direita", "txt": "RIGHT/D", "bico": Vector2(154, 58), "dir": Vector2(-1, 0), "rot": PI},
	{"nome": "DORSAL", "tecla": "usar", "txt": "E/SPACE", "bico": Vector2(96, 56), "dir": Vector2(0, 0), "rot": 0.0},
]

const VEL_LIMPEZA := 0.75                        # Fração limpa por segundo soprando
const CONSUMO_PRESSAO := 0.35                    # Pressão consumida por segundo de jato contínuo
const RECARGA_PRESSAO := 0.45                    # Recuperação de pressão sem jato
const TEMPO_FIM := 1.4

var demo := false
var t := 0.0
var poeira := [1.0, 1.0, 1.0, 1.0, 1.0]          # 1.0 = sujo de poeira lunar, 0.0 = 100% limpo
var bico_ativo := -1                             # Índice 0..4 do bico ativo neste quadro, ou -1
var pressao := 1.0                               # 0.0 a 1.0
var estado := "lavando"                          # "lavando", "concluido", "falhou"
var t_estado := 0.0
var t_aviso := 0.0
var aviso := ""
var cor_aviso := AMARELO
var e_liberado := false
var jogou := false

# Partículas dinâmicas de poeira lunar sendo sugadas
var particulas: Array = []                       # [pos, vel, cor, vida, vida_max]

# Métricas para taxa de erro
var t_jogando := 0.0
var t_desperdicio := 0.0                         # Tempo soprando zonas já limpas ou sem pressão


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()


func _input(ev: InputEvent) -> void:
	if estado != "lavando" or demo:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if BOTAO_X.grow(1).has_point(get_local_mouse_position()):
			cancelou.emit()
	elif ev.is_action_pressed("ui_cancel"):
		cancelou.emit()


func _process(delta: float) -> void:
	t += delta
	t_aviso = maxf(0.0, t_aviso - delta)
	
	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true

	if estado == "lavando":
		t_jogando += delta
		_atualizar_bico_ativo()
		_processar_jato(delta)
		_processar_particulas(delta)
		_verificar_conclusao()
	else:
		t_estado -= delta
		if t_estado <= 0.0:
			set_process(false)
			if estado == "concluido":
				terminou.emit()
			else:
				falhou.emit()
				
	queue_redraw()


func _atualizar_bico_ativo() -> void:
	bico_ativo = -1
	if demo:
		# Modo demonstração: purga cada bico em ordem até limpar tudo
		for i in ZONAS.size():
			if poeira[i] > 0.0:
				bico_ativo = i
				jogou = true
				return
		return

	# Checa se o mouse está sendo segurado sobre algum dos bicos ou regiões da cabine
	var mpos := get_local_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not BOTAO_X.grow(1).has_point(mpos):
		var cabine_mpos := mpos - JANELA
		for i in ZONAS.size():
			var bpos: Vector2 = ZONAS[i]["bico"]
			if cabine_mpos.distance_to(bpos) < 22.0:
				bico_ativo = i
				jogou = true
				return

	# Checa controles de teclado/gamepad
	if Input.is_action_pressed("cima") or Input.is_key_pressed(KEY_W):
		bico_ativo = 0
	elif Input.is_action_pressed("baixo") or Input.is_key_pressed(KEY_S):
		bico_ativo = 1
	elif Input.is_action_pressed("esquerda") or Input.is_key_pressed(KEY_A):
		bico_ativo = 2
	elif Input.is_action_pressed("direita") or Input.is_key_pressed(KEY_D):
		bico_ativo = 3
	elif e_liberado and (Input.is_action_pressed("usar") or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)):
		bico_ativo = 4

	if bico_ativo != -1:
		jogou = true


func _processar_jato(delta: float) -> void:
	if bico_ativo != -1 and pressao > 0.05:
		# Consome ar pressurizado
		pressao = maxf(0.0, pressao - CONSUMO_PRESSAO * delta)
		var i := bico_ativo
		if poeira[i] > 0.0:
			poeira[i] = maxf(0.0, poeira[i] - VEL_LIMPEZA * delta)
			if poeira[i] == 0.0:
				_avisar("%s DECONTAMINATED!" % str(ZONAS[i]["nome"]), VERDE_LIMA, 1.2)
			# Gera partículas de poeira desprendendo e voando para o ralo
			_emitir_particulas_poeira(i)
		else:
			# Bico ativo em zona que já está limpa conta como desperdício
			t_desperdicio += delta
	else:
		# Compressor recarrega pressão quando não há jato ativo
		pressao = minf(1.0, pressao + RECARGA_PRESSAO * delta)
		if bico_ativo != -1 and pressao <= 0.05:
			_avisar("PRESSURE LOW! RECHARGING...", VERMELHO_CLARO, 0.4)
			t_desperdicio += delta


func _emitir_particulas_poeira(zona_idx: int) -> void:
	var bico: Vector2 = JANELA + ZONAS[zona_idx]["bico"]
	var ralo := JANELA + Vector2(96, 104)         # Ralo de sucção no piso
	for k in 2:
		var p_inicio := bico + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		var vel := (ralo - p_inicio).normalized() * randf_range(60.0, 110.0)
		var cor := REGOLITO if randf() > 0.4 else REGOLITO_CLARO
		var vida_m := randf_range(0.25, 0.55)
		particulas.append([p_inicio, vel, cor, vida_m, vida_m])


func _processar_particulas(delta: float) -> void:
	var ralo := JANELA + Vector2(96, 104)
	var i := 0
	while i < particulas.size():
		var p: Array = particulas[i]
		p[3] = float(p[3]) - delta               # Reduz vida restante
		if float(p[3]) <= 0.0:
			particulas.remove_at(i)
			continue
		var pos_p: Vector2 = p[0]
		var vel_p: Vector2 = p[1]
		# Sucção gravitacional em direção ao ralo
		var forca_succao: Vector2 = (ralo - pos_p).normalized() * (120.0 * delta)
		vel_p += forca_succao
		pos_p += vel_p * delta
		p[0] = pos_p
		p[1] = vel_p
		i += 1


func _verificar_conclusao() -> void:
	var todas_limpas := true
	for p in poeira:
		if p > 0.0:
			todas_limpas = false
			break
			
	if todas_limpas:
		estado = "concluido"
		t_estado = TEMPO_FIM
		_avisar("DECONTAMINATION COMPLETE! SUIT CLEAN", VERDE_LIMA, 2.5)


func _avisar(txt: String, cor: Color, dur: float) -> void:
	aviso = txt
	cor_aviso = cor
	t_aviso = dur


## Taxa de erro (0 a 1) para o cálculo de rendimento da tarefa no mapa
func taxa_erro() -> float:
	return clampf(t_desperdicio / maxf(0.001, t_jogando), 0.0, 1.0)


## Informa se o jogador já começou a interagir com o minigame
func comecou() -> bool:
	return jogou


# ==============================================================================
# DESENHO (CanvasItem _draw)
# ==============================================================================
func _draw() -> void:
	# Fundo escuro semitransparente cobrindo a tela
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.75))

	_desenhar_moldura()
	_desenhar_cabine()
	_desenhar_particulas()
	_desenhar_jatos()
	_desenhar_vidro()
	_desenhar_painel_inferior()

	# Botão de fechar (X)
	_desenhar_botao_x()

	# Título superior
	Fonte.centralizado(self, "DECONTAMINATION CHAMBER", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 4, AMARELO)

	# Mensagem de aviso / feedback
	if t_aviso > 0.0:
		Fonte.centralizado(self, aviso, PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 14, cor_aviso)
	elif bico_ativo != -1:
		Fonte.centralizado(self, "PURGING: " + str(ZONAS[bico_ativo]["nome"]), PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 14, CIANO_CLARO)
	else:
		Fonte.centralizado(self, "HOLD KEY TO PURGE LUNAR DUST", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 14, METAL_CLARO)


func _desenhar_moldura() -> void:
	var p := PAINEL
	# Sombra externa
	draw_rect(p.grow(1), PRETO)
	# Fundo do painel
	draw_rect(p, FUNDO)
	# Bordas metálicas chanfradas
	draw_rect(Rect2(p.position, Vector2(p.size.x, 1)), METAL_CLARO)
	draw_rect(Rect2(p.position + Vector2(0, 1), Vector2(1, p.size.y - 2)), METAL)
	draw_rect(Rect2(p.position + Vector2(1, p.size.y - 1), Vector2(p.size.x - 1, 1)), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(p.size.x - 1, 1), Vector2(1, p.size.y - 2)), CINZA_ESC)
	# Parafusos industriais nos 4 cantos
	for c in [Vector2(3, 3), Vector2(p.size.x - 6, 3), Vector2(3, p.size.y - 6), Vector2(p.size.x - 6, p.size.y - 6)]:
		draw_rect(Rect2(p.position + c, Vector2(3, 3)), METAL)
		draw_rect(Rect2(p.position + c + Vector2.ONE, Vector2.ONE), CINZA_ESC)


func _desenhar_botao_x() -> void:
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X, VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)


func _desenhar_cabine() -> void:
	# Contorno escuro da janela da cabine
	draw_rect(Rect2(JANELA - Vector2.ONE, Vector2(194, 123)), PRETO)
	# Fundo interno com duto e 5 nichos
	draw_texture(TEX_FUNDO, JANELA)

	# Astronauta
	var astro_pos := JANELA + ASTRO_OFFSET
	draw_texture(TEX_ASTRO, astro_pos)

	# 5 Camadas de poeira lunar (opacidade conforme poeira[i])
	var texturas_poeira := [
		TEX_POEIRA_CIMA,
		TEX_POEIRA_BAIXO,
		TEX_POEIRA_ESQ,
		TEX_POEIRA_DIR,
		TEX_POEIRA_ATRAS
	]
	for i in 5:
		if poeira[i] > 0.0:
			draw_texture(texturas_poeira[i], astro_pos, Color(1, 1, 1, poeira[i]))

	# Indicadores LED ao redor dos 5 bicos injetores
	for i in ZONAS.size():
		var bpos: Vector2 = JANELA + ZONAS[i]["bico"]
		var limpo: bool = poeira[i] <= 0.0
		var ativo: bool = (bico_ativo == i and pressao > 0.05)
		var cor_led := VERDE_LIMA if limpo else (CIANO_CLARO if ativo else CINZA)
		draw_rect(Rect2(bpos - Vector2(1, 1), Vector2(3, 3)), PRETO)
		draw_rect(Rect2(bpos, Vector2.ONE), cor_led)


func _desenhar_jatos() -> void:
	if bico_ativo == -1 or pressao <= 0.05:
		return

	var idx := bico_ativo
	var frame_idx := int(t * 16.0) % 4
	var frame_rect := Rect2(frame_idx * 32, 0, 32, 32)
	var bpos: Vector2 = JANELA + ZONAS[idx]["bico"]

	# Desenha jato orientado a partir do bico ativo
	match idx:
		0: # Cima (sopra para baixo em direção ao capacete)
			for step in 2:
				var dy: float = bpos.y + 4 + step * 20
				draw_set_transform(Vector2(bpos.x, dy), PI / 2.0, Vector2(1, 1))
				draw_texture_rect_region(TEX_JATO, Rect2(-16, -16, 32, 32), frame_rect)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		1: # Baixo (sopra para cima em direção às botas)
			for step in 2:
				var dy: float = bpos.y - 4 - step * 18
				draw_set_transform(Vector2(bpos.x, dy), -PI / 2.0, Vector2(1, 1))
				draw_texture_rect_region(TEX_JATO, Rect2(-16, -16, 32, 32), frame_rect)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		2: # Esquerda (sopra para a direita em direção ao braço esquerdo)
			for step in 2:
				var dx: float = bpos.x + 8 + step * 22
				draw_set_transform(Vector2(dx, bpos.y), 0.0, Vector2(1, 1))
				draw_texture_rect_region(TEX_JATO, Rect2(-16, -16, 32, 32), frame_rect)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		3: # Direita (sopra para a esquerda em direção ao braço direito)
			for step in 2:
				var dx: float = bpos.x - 8 - step * 22
				draw_set_transform(Vector2(dx, bpos.y), PI, Vector2(1, 1))
				draw_texture_rect_region(TEX_JATO, Rect2(-16, -16, 32, 32), frame_rect)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		4: # Dorsal (sopra em vórtice circular em torno da mochila)
			for ang in [0.0, PI / 2.0, PI, -PI / 2.0]:
				var rot: float = ang + (t * 4.0)
				var dpos := bpos + Vector2(cos(rot), sin(rot)) * 12.0
				draw_set_transform(dpos, rot, Vector2(0.8, 0.8))
				draw_texture_rect_region(TEX_JATO, Rect2(-16, -16, 32, 32), frame_rect)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _desenhar_particulas() -> void:
	for p in particulas:
		var pos: Vector2 = p[0]
		var cor: Color = p[2]
		var alpha: float = clampf(float(p[3]) / float(p[4]), 0.0, 1.0)
		draw_rect(Rect2(pos.round(), Vector2.ONE), Color(cor, alpha))


func _desenhar_vidro() -> void:
	# Camada cilíndrica de vidro frontal translúcido com reflexos
	draw_texture(TEX_VIDRO, JANELA)


func _desenhar_painel_inferior() -> void:
	# Barra de ar comprimido / pressão no canto esquerdo
	var r_pressao := Rect2(PAINEL.position.x + 8, PAINEL.end.y - 18, 54, 4)
	draw_rect(r_pressao.grow(1), PRETO)
	draw_rect(r_pressao, NOITE)
	var w_pressao := roundf(r_pressao.size.x * pressao)
	var cor_p := CIANO_CLARO if pressao > 0.3 else VERMELHO_CLARO
	if w_pressao > 0:
		draw_rect(Rect2(r_pressao.position, Vector2(w_pressao, r_pressao.size.y)), cor_p)
	Fonte.desenhar(self, "AIR", Vector2(r_pressao.position.x, r_pressao.position.y - 7), METAL_CLARO)

	# 5 Sub-barras de progresso da descontaminação (uma para cada zona)
	var x_start := PAINEL.position.x + 68
	var w_seg := 30
	var espaco := 2
	for i in ZONAS.size():
		var bx := x_start + i * (w_seg + espaco)
		var by := PAINEL.end.y - 18
		var r_seg := Rect2(bx, by, w_seg, 4)
		draw_rect(r_seg.grow(1), PRETO)
		draw_rect(r_seg, NOITE)

		var limpo_pct: float = 1.0 - poeira[i]
		var w_limpo := roundf(r_seg.size.x * limpo_pct)
		var cor_seg := VERDE_LIMA if limpo_pct >= 1.0 else (AMARELO if limpo_pct > 0.0 else CINZA_ESC)
		if w_limpo > 0:
			draw_rect(Rect2(r_seg.position, Vector2(w_limpo, r_seg.size.y)), cor_seg)

		# Tecla / Sigla da zona acima de cada sub-barra
		var txt_tecla: String = str(ZONAS[i]["txt"])
		var cor_txt := BRANCO if bico_ativo == i else (VERDE_LIMA if limpo_pct >= 1.0 else METAL)
		Fonte.centralizado(self, txt_tecla, bx + w_seg / 2.0, by - 7, cor_txt)


func _criar_teclas() -> void:
	# Garante que as ações existam caso a cena seja testada isoladamente (F6)
	var mapear := {
		"usar": [KEY_E, KEY_X, KEY_SPACE, KEY_ENTER],
		"cima": [KEY_UP, KEY_W],
		"baixo": [KEY_DOWN, KEY_S],
		"esquerda": [KEY_LEFT, KEY_A],
		"direita": [KEY_RIGHT, KEY_D]
	}
	for acao in mapear:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			for k in mapear[acao]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(acao, ev)
