extends Control
## Minigame "Calibrar Tanques Criogênicos // Célula de Combustível" (Apollo 13 Fuel Cells).
## Cockpit analógico de manômetros circulares com tubulação de vasos comunicantes (Crossfeed)
## e válvula de purga criogênica (Venting para alívio de sobrepressão).
## Controles:
##   A / D: Seleciona válvula (0: Crossfeed A-B, 1: Crossfeed B-C, 2: Purga Criogênica)
##   W / S: Abre fluxo na direção direta ou reversa da válvula selecionada
##   E (ou Usar): Ativa purga criogênica de escape a qualquer momento
## Condição de vitória: Manter os 3 tanques na faixa verde [55 PSI, 72 PSI] por 2.0 segundos contínuos.
## Contrato com o mapa: sinais `terminou`, `falhou`, `cancelou`, taxa_erro(), comecou() e `demo`.
## Arte (paleta Apollo) em res://assets/minigames/tanques/painel.png (228x86, com o canto em ORIGEM_PAINEL): a chapa,
## os aros dos manômetros, os canos, as flanges das válvulas e o bocal da purga. Sem o arquivo, o minigame desenha
## tudo isso em código. Ponteiros, faixas do mostrador, volantes, fluido, vapor e textos são sempre desenhados aqui.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")

# Paleta Apollo 13
const PRETO := Color("#090a14")
const NOITE := Color("#10141f")
const FUNDO := Color("#151d28")
const AZUL_NOITE := Color("#172038")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO_SUJO := Color("#c7cfcc")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const LARANJA := Color("#de9e41")
const LARANJA_ESC := Color("#be772b")
const VERDE_ESC := Color("#25562e")
const VERDE := Color("#468232")
const VERDE_CLARO := Color("#75a743")
const VERDE_LIMA := Color("#a8ca58")
const VINHO := Color("#752438")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const CIANO := Color("#73bed3")
const CIANO_CLARO := Color("#a4dddb")

# Dimensões e Layout
const PAINEL := Rect2(36, 8, 248, 164)
const BOTAO_X := Rect2(268, 11, 8, 8)
const BARRA_ESTAB := Rect2(60, 134, 200, 7)
const ARTE_PAINEL := "res://assets/minigames/tanques/painel.png"
const ORIGEM_PAINEL := Vector2(46, 34)

# Geometria dos Manômetros Circulares
const CENTROS_X: Array[float] = [84.0, 160.0, 236.0]
const DIAL_Y: float = 65.0
const RAIO_DIAL: float = 19.0
const RAIO_INTERNO: float = 16.0

const ROTULOS_CABECALHO: Array[String] = ["TANK A (H2)", "TANK B (O2)", "FUEL CELL"]
const CORES_GAS: Array[Color] = [CIANO_CLARO, CIANO, LARANJA]

# Parâmetros de Pressão e Física
const PRESSAO_INICIAL: Array[float] = [92.0, 38.0, 76.0]
const FAIXA_MIN: float = 55.0
const FAIXA_MAX: float = 72.0
const ZONA_SUB: float = 30.0
const ZONA_SOBRE: float = 82.0
const ALVO_IDEAL: float = 63.5

const VEL_TRANSF: float = 16.0
const VEL_PURGA: float = 14.0
const TEMPO_ESTABILIDADE: float = 2.0
const TEMPO_FIM: float = 1.3
const MAX_ERROS: int = 6
const TEMPO_ERRO: float = 0.6

# Posições das Válvulas no Cockpit
const POS_VALVULAS: Array[Vector2] = [Vector2(122.0, 65.0), Vector2(198.0, 65.0), Vector2(160.0, 107.0)]
const NOMES_VALVULAS: Array[String] = ["VALVE A-B (CROSSFEED)", "VALVE B-C (CROSSFEED)", "PURGE VALVE (VENT)"]

# Estado Público
var demo: bool = false

# Estado do Jogo
var pressoes: Array[float] = [92.0, 38.0, 76.0]
var angulos_agulha: Array[float] = [-2.356, -2.356, -2.356]
var rotacao_valvulas: Array[float] = [0.0, 0.0, 0.0]

var selecionado: int = 0
var ajuste: float = 0.0
var purga_ativa: bool = false

var tempo_estavel: float = 0.0
var t_demo: float = 0.0
var acabou: bool = false
var perdeu: bool = false
var t: float = 0.0
var t_fim: float = -1.0
var acertos: int = 0
var erros: int = 0
var estava_na_faixa: Array[bool] = [false, false, false]
var estava_critico: Array[bool] = [true, false, false]
var t_erro: float = 0.0
var t_troca: float = 0.0
var tempo_operando: float = 0.0

# Efeitos Visuais Procedurais
var particulas_fluido: Array[Dictionary] = []
var pluma_vapor: Array[Dictionary] = []

# Áudio Procedural
var sfx_fluxo: AudioStreamPlayer = null
var sfx_purga: AudioStreamPlayer = null
var sfx_sucesso: AudioStreamPlayer = null
var sfx_troca: AudioStreamPlayer = null
var sfx_alerta: AudioStreamPlayer = null
var sucesso_tocado: bool = false
var tex_painel: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	if ResourceLoader.exists(ARTE_PAINEL):
		tex_painel = load(ARTE_PAINEL)
	pressoes = PRESSAO_INICIAL.duplicate()
	for i: int in 3:
		var rad_ini: float = deg_to_rad(-135.0 + (clampf(pressoes[i], 0.0, 100.0) / 100.0) * 270.0)
		angulos_agulha[i] = rad_ini
		estava_na_faixa[i] = _na_faixa(i)
		estava_critico[i] = pressoes[i] > ZONA_SOBRE or pressoes[i] < ZONA_SUB

	# Inicializar partículas dos tubos de fluido
	for k: int in 6:
		particulas_fluido.append({"tubo": 0, "pos": float(k) / 6.0, "vel": 1.2})
	for k: int in 6:
		particulas_fluido.append({"tubo": 1, "pos": float(k) / 6.0, "vel": 1.2})

	_configurar_audio()


func _configurar_audio() -> void:
	sfx_fluxo = AudioStreamPlayer.new()
	sfx_fluxo.stream = _sintetizar_fluxo()
	add_child(sfx_fluxo)

	sfx_purga = AudioStreamPlayer.new()
	sfx_purga.stream = _sintetizar_purga()
	add_child(sfx_purga)

	sfx_sucesso = AudioStreamPlayer.new()
	sfx_sucesso.stream = _sintetizar_sucesso()
	add_child(sfx_sucesso)

	sfx_troca = AudioStreamPlayer.new()
	sfx_troca.stream = _sintetizar_troca()
	add_child(sfx_troca)

	sfx_alerta = AudioStreamPlayer.new()
	sfx_alerta.stream = _sintetizar_alerta()
	add_child(sfx_alerta)


func _input(ev: InputEvent) -> void:
	if acabou or demo:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos: Vector2 = get_local_mouse_position()
		if BOTAO_X.grow(2).has_point(mouse_pos):
			_parar_fluxo_e_purga()
			cancelou.emit()
			return
		# Seleção de válvula por clique
		for idx: int in POS_VALVULAS.size():
			if POS_VALVULAS[idx].distance_to(mouse_pos) <= 12.0:
				if selecionado != idx:
					selecionado = idx
					t_troca = 0.2
					_tocar_troca()
				break
	elif ev.is_action_pressed("ui_cancel"):
		_parar_fluxo_e_purga()
		cancelou.emit()


func _process(delta: float) -> void:
	t += delta
	t_troca = maxf(0.0, t_troca - delta)
	t_erro = maxf(0.0, t_erro - delta)

	_atualizar_particulas(delta)
	_atualizar_agulhas(delta)

	if acabou:
		ajuste = 0.0
		purga_ativa = false
		_parar_fluxo_e_purga()
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
			if get_parent() == get_tree().root:
				queue_free()
		queue_redraw()
		return

	if demo:
		_jogar_sozinho(delta)
	else:
		_controles(delta)

	_aplicar_fisica(delta)
	_contar_lances()
	_atualizar_audio()

	if perdeu:
		queue_redraw()
		return

	# Checagem de estabilidade contínua de 2.0 segundos
	if _todos_na_faixa():
		tempo_estavel += delta
		if tempo_estavel >= TEMPO_ESTABILIDADE and not acabou:
			acabou = true
			t_fim = TEMPO_FIM
			_parar_fluxo_e_purga()
			_tocar_sucesso()
	else:
		tempo_estavel = 0.0

	queue_redraw()


func _controles(_delta: float) -> void:
	var antes: int = selecionado
	if Input.is_action_just_pressed("esquerda"):
		selecionado = wrapi(selecionado - 1, 0, 3)
	elif Input.is_action_just_pressed("direita"):
		selecionado = wrapi(selecionado + 1, 0, 3)

	if selecionado != antes:
		t_troca = 0.2
		_tocar_troca()

	var tecla_purga: bool = Input.is_action_pressed("usar")
	ajuste = Input.get_axis("baixo", "cima")

	# Purga se ativa por tecla direta ou pela válvula de purga
	if tecla_purga or (selecionado == 2 and absf(ajuste) > 0.1):
		purga_ativa = true
		ajuste = 0.0
	else:
		purga_ativa = false


func _jogar_sozinho(delta: float) -> void:
	t_demo += delta
	var soma: float = pressoes[0] + pressoes[1] + pressoes[2]
	var alvo: float = soma / 3.0

	# 1. Se a soma estiver acima da faixa ótima equilibrada (3 * 63.5 = 190.5), purgar excesso
	if soma > 190.5:
		if selecionado != 2:
			selecionado = 2
			_tocar_troca()
		purga_ativa = true
		ajuste = 0.0
		return

	purga_ativa = false

	# 2. Equalizar Tanque A através da Válvula A-B
	if absf(pressoes[0] - alvo) > 1.0:
		if selecionado != 0:
			selecionado = 0
			_tocar_troca()
		if pressoes[0] > alvo:
			ajuste = 1.0   # A -> B
		else:
			ajuste = -1.0  # B -> A
	# 3. Equalizar Tanque C através da Válvula B-C
	elif absf(pressoes[2] - alvo) > 1.0:
		if selecionado != 1:
			selecionado = 1
			_tocar_troca()
		if pressoes[2] > alvo:
			ajuste = -1.0  # C -> B
		else:
			ajuste = 1.0   # B -> C
	else:
		ajuste = 0.0


func _aplicar_fisica(delta: float) -> void:
	if purga_ativa:
		tempo_operando += delta
		rotacao_valvulas[2] += delta * 8.0
		var soma: float = pressoes[0] + pressoes[1] + pressoes[2]
		if soma > 0.01:
			for i: int in 3:
				var alivia: float = VEL_PURGA * delta * (pressoes[i] / soma)
				pressoes[i] = maxf(0.0, pressoes[i] - alivia)
	elif selecionado == 0 and absf(ajuste) > 0.1:
		tempo_operando += delta
		rotacao_valvulas[0] += delta * 6.0 * ajuste
		var delta_p: float = VEL_TRANSF * delta * ajuste
		if delta_p > 0.0:
			var fluxo: float = minf(delta_p, pressoes[0])
			pressoes[0] -= fluxo
			pressoes[1] = minf(100.0, pressoes[1] + fluxo)
		else:
			var fluxo: float = minf(-delta_p, pressoes[1])
			pressoes[1] -= fluxo
			pressoes[0] = minf(100.0, pressoes[0] + fluxo)
	elif selecionado == 1 and absf(ajuste) > 0.1:
		tempo_operando += delta
		rotacao_valvulas[1] += delta * 6.0 * ajuste
		var delta_p: float = VEL_TRANSF * delta * ajuste
		if delta_p > 0.0:
			var fluxo: float = minf(delta_p, pressoes[1])
			pressoes[1] -= fluxo
			pressoes[2] = minf(100.0, pressoes[2] + fluxo)
		else:
			var fluxo: float = minf(-delta_p, pressoes[2])
			pressoes[2] -= fluxo
			pressoes[1] = minf(100.0, pressoes[1] + fluxo)


func _contar_lances() -> void:
	var operando: bool = purga_ativa or absf(ajuste) > 0.1
	for i: int in 3:
		var dentro: bool = _na_faixa(i)
		var critico: bool = pressoes[i] > ZONA_SOBRE or pressoes[i] < ZONA_SUB

		if operando:
			# Se tanque estava seguro e saiu da faixa por manobra
			if estava_na_faixa[i] and not dentro:
				erros += 1
				t_erro = TEMPO_ERRO
				_tocar_alerta()
				if erros >= MAX_ERROS:
					perdeu = true
					acabou = true
					t_fim = TEMPO_FIM
			# Se tanque estava fora e entrou na faixa
			elif not estava_na_faixa[i] and dentro:
				acertos += 1

			# Alerta se entrar em sobrepressão ou subpressão crítica
			if not estava_critico[i] and critico:
				erros += 1
				t_erro = TEMPO_ERRO
				_tocar_alerta()
				if erros >= MAX_ERROS:
					perdeu = true
					acabou = true
					t_fim = TEMPO_FIM

		estava_na_faixa[i] = dentro
		estava_critico[i] = critico


func _atualizar_particulas(delta: float) -> void:
	# Partículas de fluido nas tubulações
	if selecionado == 0 and absf(ajuste) > 0.1 and not acabou:
		for p: Dictionary in particulas_fluido:
			if p["tubo"] == 0:
				p["pos"] = fposmod(p["pos"] + p["vel"] * ajuste * delta, 1.0)
	elif selecionado == 1 and absf(ajuste) > 0.1 and not acabou:
		for p: Dictionary in particulas_fluido:
			if p["tubo"] == 1:
				p["pos"] = fposmod(p["pos"] + p["vel"] * ajuste * delta, 1.0)

	# Pluma de vapor criogênico na purga
	if purga_ativa and not acabou:
		for k: int in 3:
			pluma_vapor.append({
				"pos": Vector2(160.0 + randf_range(-2.0, 2.0), 118.0),
				"vel": Vector2(randf_range(-14.0, 14.0), randf_range(20.0, 38.0)),
				"alpha": randf_range(0.7, 0.95),
				"tam": randf_range(1.5, 3.0),
				"vida": 0.42
			})

	var vapor_ativas: Array[Dictionary] = []
	for p: Dictionary in pluma_vapor:
		p["vida"] -= delta
		if p["vida"] > 0.0:
			p["pos"] += p["vel"] * delta
			p["tam"] += delta * 6.5
			p["alpha"] = clampf(p["vida"] / 0.42, 0.0, 1.0)
			vapor_ativas.append(p)
	pluma_vapor = vapor_ativas


func _atualizar_agulhas(delta: float) -> void:
	for i: int in 3:
		var p_clamped: float = clampf(pressoes[i], 0.0, 100.0)
		var alvo_rad: float = deg_to_rad(-135.0 + (p_clamped / 100.0) * 270.0)
		angulos_agulha[i] = lerpf(angulos_agulha[i], alvo_rad, clampf(delta * 12.0, 0.0, 1.0))


func _atualizar_audio() -> void:
	if purga_ativa and not acabou:
		if sfx_purga and not sfx_purga.playing:
			sfx_purga.play()
		if sfx_fluxo and sfx_fluxo.playing:
			sfx_fluxo.stop()
	elif (selecionado == 0 or selecionado == 1) and absf(ajuste) > 0.1 and not acabou:
		if sfx_fluxo and not sfx_fluxo.playing:
			sfx_fluxo.play()
		if sfx_purga and sfx_purga.playing:
			sfx_purga.stop()
	else:
		_parar_fluxo_e_purga()


func _parar_fluxo_e_purga() -> void:
	if sfx_fluxo and sfx_fluxo.playing:
		sfx_fluxo.stop()
	if sfx_purga and sfx_purga.playing:
		sfx_purga.stop()


func _tocar_sucesso() -> void:
	if sfx_sucesso and not sucesso_tocado:
		sucesso_tocado = true
		sfx_sucesso.play()


func _tocar_troca() -> void:
	if sfx_troca:
		sfx_troca.stop()
		sfx_troca.play()


func _tocar_alerta() -> void:
	if sfx_alerta:
		sfx_alerta.stop()
		sfx_alerta.play()


func _na_faixa(i: int) -> bool:
	return pressoes[i] >= FAIXA_MIN and pressoes[i] <= FAIXA_MAX


func _todos_na_faixa() -> bool:
	for i: int in 3:
		if not _na_faixa(i):
			return false
	return true


func taxa_erro() -> float:
	return float(erros) / maxf(1.0, float(erros + acertos))


func comecou() -> bool:
	return erros > 0 or acertos > 0 or tempo_estavel > 0.0 or tempo_operando > 0.1


func _criar_teclas() -> void:
	var teclas: Dictionary = {
		"esquerda": [KEY_A, KEY_LEFT],
		"direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]
	}
	for acao: String in teclas:
		if InputMap.has_action(acao):
			continue
		InputMap.add_action(acao)
		for k: int in teclas[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k as Key
			InputMap.action_add_event(acao, ev)


func _dial_to_godot_ang(deg: float) -> float:
	return -PI * 0.5 + deg_to_rad(deg)


# --- Desenho Procedural CanvasItem ---
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.75))
	_moldura()

	# Cabeçalho Principal (y = 12)
	Fonte.centralizado(self, "CHECK THE TANKS // CRYOGENIC FUEL CELLS", 160.0, 12.0, AMARELO)

	# Status Superior (y = 26)
	var seguros: int = 0
	for i: int in 3:
		seguros += 1 if _na_faixa(i) else 0
	Fonte.desenhar(self, "STABLE: %d/3" % seguros, Vector2(50.0, 26.0), VERDE_LIMA if seguros == 3 else BRANCO_SUJO)
	Fonte.desenhar(self, "ERRORS: %d/%d" % [erros, MAX_ERROS], Vector2(220.0, 26.0), VERMELHO_CLARO if erros >= 3 else CINZA)

	# Linha divisória suave abaixo do status (y = 33)
	draw_line(Vector2(46.0, 33.0), Vector2(274.0, 33.0), CINZA_ESC, 1.0)

	# Botão fechar (X)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X, VERMELHO)
	for k: int in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)

	# Tubulações de Vasos Comunicantes e Escape (na arte, o painel já traz canos, aros, flanges e bocal)
	if tex_painel:
		draw_texture(tex_painel, ORIGEM_PAINEL)
	else:
		_desenhar_tubulacoes()

	# Partículas de Fluido e Pluma de Vapor
	_desenhar_particulas()

	# Manômetros Circulares Analógicos
	for i: int in 3:
		_desenhar_manometro(i)

	# Válvulas e Retículo de Seleção
	_desenhar_valvulas()

	# Painel Inferior: Mensagens e Barra de Estabilidade
	_desenhar_painel_inferior()


func _desenhar_tubulacoes() -> void:
	# Tubo horizontal A <-> B (entre dials: x=103 a 141 em y=65)
	draw_rect(Rect2(103, 63, 38, 4), CINZA_ESC)
	draw_rect(Rect2(103, 64, 38, 2), AZUL_NOITE)
	draw_line(Vector2(103, 63), Vector2(141, 63), METAL_CLARO, 1.0)
	draw_line(Vector2(103, 67), Vector2(141, 67), METAL, 1.0)

	# Tubo horizontal B <-> C (entre dials: x=179 a 217 em y=65)
	draw_rect(Rect2(179, 63, 38, 4), CINZA_ESC)
	draw_rect(Rect2(179, 64, 38, 2), AZUL_NOITE)
	draw_line(Vector2(179, 63), Vector2(217, 63), METAL_CLARO, 1.0)
	draw_line(Vector2(179, 67), Vector2(217, 67), METAL, 1.0)

	# Manifolds verticais descendo para o coletor de purga (de y=71 a y=96)
	draw_rect(Rect2(120, 71, 4, 25), CINZA_ESC)
	draw_rect(Rect2(121, 71, 2, 25), AZUL_NOITE)

	draw_rect(Rect2(196, 71, 4, 25), CINZA_ESC)
	draw_rect(Rect2(197, 71, 2, 25), AZUL_NOITE)

	# Tubo coletor horizontal inferior (em y=96)
	draw_rect(Rect2(120, 96, 80, 4), CINZA_ESC)
	draw_rect(Rect2(120, 97, 80, 2), AZUL_NOITE)
	draw_line(Vector2(120, 96), Vector2(200, 96), METAL, 1.0)
	draw_line(Vector2(120, 100), Vector2(200, 100), METAL, 1.0)

	# Tubo vertical entrando na válvula de purga (y=100 a 103)
	draw_rect(Rect2(158, 100, 4, 4), AZUL_NOITE)
	draw_line(Vector2(158, 100), Vector2(158, 104), METAL, 1.0)
	draw_line(Vector2(162, 100), Vector2(162, 104), METAL, 1.0)

	# Bocal cônico de escape de purga criogênica (y=112 a 118)
	var bocal_pontos: PackedVector2Array = [
		Vector2(157.0, 112.0),
		Vector2(163.0, 112.0),
		Vector2(166.0, 118.0),
		Vector2(154.0, 118.0)
	]
	draw_colored_polygon(bocal_pontos, CINZA_ESC)
	draw_polyline(bocal_pontos, METAL_CLARO, 1.0)
	draw_line(Vector2(154.0, 118.0), Vector2(166.0, 118.0), NOITE, 1.5)


func _desenhar_particulas() -> void:
	# Partículas de fluxo no tubo A-B
	for p: Dictionary in particulas_fluido:
		if p["tubo"] == 0:
			var px: float = 105.0 + float(p["pos"]) * 34.0
			var cor_p: Color = CIANO_CLARO if (selecionado == 0 and absf(ajuste) > 0.1) else CINZA
			draw_rect(Rect2(px, 64.0, 2.0, 2.0), cor_p)
		elif p["tubo"] == 1:
			var px: float = 181.0 + float(p["pos"]) * 34.0
			var cor_p: Color = CIANO_CLARO if (selecionado == 1 and absf(ajuste) > 0.1) else CINZA
			draw_rect(Rect2(px, 64.0, 2.0, 2.0), cor_p)

	# Pluma de vapor criogênico na purga (saindo do bocal y=118)
	for p: Dictionary in pluma_vapor:
		var c_externo := Color(CIANO_CLARO.r, CIANO_CLARO.g, CIANO_CLARO.b, p["alpha"] * 0.40)
		var c_interno := Color(BRANCO.r, BRANCO.g, BRANCO.b, p["alpha"] * 0.70)
		draw_circle(p["pos"], p["tam"], c_externo)
		draw_circle(p["pos"], p["tam"] * 0.5, c_interno)


func _desenhar_manometro(i: int) -> void:
	var centro := Vector2(CENTROS_X[i], DIAL_Y)

	# Rótulo Único e Nítido do Tanque (y = 36.0, bem acima do aro y=46)
	Fonte.centralizado(self, ROTULOS_CABECALHO[i], centro.x, 36.0, CORES_GAS[i])

	if not tex_painel:                         # na arte, o painel já traz o aro e o mostrador escuro
		# Moldura metálica circular externa (raio 19.0)
		draw_circle(centro, RAIO_DIAL + 1.5, CINZA_ESC)
		draw_circle(centro, RAIO_DIAL, METAL)
		draw_circle(centro, RAIO_DIAL - 1.2, METAL_CLARO)
		draw_circle(centro, RAIO_DIAL - 2.2, NOITE)

		# Rebites metálicos na moldura (8 pontos)
		for k: int in 8:
			var a_rebite: float = k * (TAU / 8.0)
			var pos_r: Vector2 = centro + Vector2(cos(a_rebite), sin(a_rebite)) * (RAIO_DIAL - 0.8)
			draw_rect(Rect2(pos_r.x - 0.5, pos_r.y - 0.5, 1.0, 1.0), METAL_CLARO)

		# Mostrador interno escuro
		draw_circle(centro, RAIO_INTERNO, NOITE)

	# Faixas Coloridas do Mostrador:
	# 1. Subpressão (< 30 PSI): Vermelho escuro
	draw_arc(centro, 13.5, _dial_to_godot_ang(-135.0), _dial_to_godot_ang(-54.0), 12, Color(VERMELHO, 0.7), 2.0)
	# 2. Pressão Normal Baixa (30 a 55 PSI): Cinza
	draw_arc(centro, 13.5, _dial_to_godot_ang(-54.0), _dial_to_godot_ang(13.5), 14, Color(CINZA, 0.35), 1.5)
	# 3. Faixa Ideal Segura [55 a 72 PSI]: Verde Luminous
	draw_arc(centro, 13.5, _dial_to_godot_ang(13.5), _dial_to_godot_ang(59.4), 16, Color(VERDE_CLARO, 0.35), 3.5)
	draw_arc(centro, 13.5, _dial_to_godot_ang(13.5), _dial_to_godot_ang(59.4), 16, VERDE_LIMA, 2.0)
	# 4. Zona de Cuidado (72 a 82 PSI): Laranja
	draw_arc(centro, 13.5, _dial_to_godot_ang(59.4), _dial_to_godot_ang(86.4), 10, Color(LARANJA, 0.6), 2.0)
	# 5. Sobrepressão Crítica (> 82 PSI): Vermelho Vivo
	draw_arc(centro, 13.5, _dial_to_godot_ang(86.4), _dial_to_godot_ang(135.0), 12, Color(VERMELHO_CLARO, 0.85), 2.0)

	# Marcações Radiais (Ticks)
	for psi_step: int in range(0, 101, 25):
		var a_d: float = -135.0 + (float(psi_step) / 100.0) * 270.0
		var v_dir: Vector2 = Vector2(sin(deg_to_rad(a_d)), -cos(deg_to_rad(a_d)))
		draw_line(centro + v_dir * 11.5, centro + v_dir * 15.0, BRANCO_SUJO, 1.0)

	for m: float in [12.5, 37.5, 62.5, 87.5]:
		var a_d: float = -135.0 + (m / 100.0) * 270.0
		var v_dir: Vector2 = Vector2(sin(deg_to_rad(a_d)), -cos(deg_to_rad(a_d)))
		draw_line(centro + v_dir * 13.0, centro + v_dir * 15.0, CINZA, 1.0)

	# Reflexo de vidro no quadrante superior
	draw_arc(centro, 12.5, -PI * 0.85, -PI * 0.15, 12, Color(BRANCO, 0.12), 1.0)

	# Ponteiro Analógico Fino
	var ang: float = angulos_agulha[i]
	var v_ponteiro: Vector2 = Vector2(sin(ang), -cos(ang))
	var p_cauda: Vector2 = centro - v_ponteiro * 3.0
	var p_corpo: Vector2 = centro + v_ponteiro * 10.5
	var p_ponta: Vector2 = centro + v_ponteiro * 14.5

	draw_line(p_cauda, p_corpo, BRANCO, 1.0)
	var cor_ponta: Color = VERMELHO_CLARO if pressoes[i] > ZONA_SOBRE or pressoes[i] < ZONA_SUB else AMARELO
	draw_line(p_corpo, p_ponta, cor_ponta, 1.2)

	# Cubo central metálico
	draw_circle(centro, 2.5, METAL_CLARO)
	draw_circle(centro, 1.4, CINZA_ESC)
	draw_rect(Rect2(centro.x - 0.5, centro.y - 0.5, 1.0, 1.0), BRANCO)

	# Leitura Digital de Pressão em PSI (y = 87.0, bem abaixo do dial y=84)
	var cor_txt: Color
	if _na_faixa(i):
		cor_txt = VERDE_LIMA
	elif pressoes[i] > ZONA_SOBRE or pressoes[i] < ZONA_SUB:
		cor_txt = VERMELHO_CLARO
	else:
		cor_txt = AMARELO
	Fonte.centralizado(self, "%d PSI" % roundi(pressoes[i]), centro.x, 87.0, cor_txt)


func _desenhar_valvulas() -> void:
	# Válvulas A-B (idx 0) e B-C (idx 1)
	for idx: int in 2:
		var pos: Vector2 = POS_VALVULAS[idx]
		var rot: float = rotacao_valvulas[idx]

		# Rótulo de identificação ACIMA da válvula (y = 53.0)
		var rotulo: String = "V-AB" if idx == 0 else "V-BC"
		var cor_rotulo: Color = AMARELO if selecionado == idx else CINZA
		Fonte.centralizado(self, rotulo, pos.x, 53.0, cor_rotulo)

		draw_circle(pos, 5.5, METAL)
		draw_circle(pos, 4.0, CINZA_ESC)

		# Raios giratórios da manopla da válvula
		for k: int in 4:
			var a_raio: float = rot + k * (TAU / 4.0)
			var p_raio: Vector2 = pos + Vector2(cos(a_raio), sin(a_raio)) * 4.0
			draw_line(pos, p_raio, METAL_CLARO, 1.0)
		draw_circle(pos, 1.6, METAL_CLARO)

		# Indicador de fluxo quando ativo
		if selecionado == idx and absf(ajuste) > 0.1 and not acabou:
			var dir_seta: float = signf(ajuste)
			var p_seta: Vector2 = pos + Vector2(dir_seta * 8.0, 0.0)
			draw_rect(Rect2(p_seta.x - 1.0, p_seta.y - 1.0, 2.0, 2.0), AMARELO)

	# Válvula de Purga (idx 2, pos y=107.0)
	var pos_purga: Vector2 = POS_VALVULAS[2]
	draw_circle(pos_purga, 5.5, METAL)
	draw_circle(pos_purga, 4.2, VINHO if purga_ativa else CINZA_ESC)
	for k: int in 3:
		var a_raio: float = rotacao_valvulas[2] + k * (TAU / 3.0)
		var p_raio: Vector2 = pos_purga + Vector2(cos(a_raio), sin(a_raio)) * 4.2
		draw_line(pos_purga, p_raio, LARANJA if purga_ativa else METAL_CLARO, 1.0)
	draw_circle(pos_purga, 1.8, AMARELO if purga_ativa else METAL_CLARO)

	# Rótulos laterais da purga: "PURGA" à esquerda e "VENT" à direita (sem sobreposição!)
	var cor_purga_lbl: Color = LARANJA if purga_ativa else (AMARELO if selecionado == 2 else CINZA)
	Fonte.desenhar(self, "PURGE", Vector2(126.0, 105.0), cor_purga_lbl)
	Fonte.desenhar(self, "VENT", Vector2(174.0, 105.0), cor_purga_lbl)

	# Retículo HUD de Seleção da Válvula Ativa
	if not acabou:
		var pos_sel: Vector2 = POS_VALVULAS[selecionado]
		var pulso: float = 0.75 + 0.25 * sin(t * 8.0)
		var cor_sel: Color = Color(AMARELO.r, AMARELO.g, AMARELO.b, pulso)
		var d: float = 8.0

		draw_line(pos_sel + Vector2(-d, -d), pos_sel + Vector2(-d + 3, -d), cor_sel, 1.0)
		draw_line(pos_sel + Vector2(-d, -d), pos_sel + Vector2(-d, -d + 3), cor_sel, 1.0)

		draw_line(pos_sel + Vector2(d, -d), pos_sel + Vector2(d - 3, -d), cor_sel, 1.0)
		draw_line(pos_sel + Vector2(d, -d), pos_sel + Vector2(d, -d + 3), cor_sel, 1.0)

		draw_line(pos_sel + Vector2(-d, d), pos_sel + Vector2(-d + 3, d), cor_sel, 1.0)
		draw_line(pos_sel + Vector2(-d, d), pos_sel + Vector2(-d, d - 3), cor_sel, 1.0)

		draw_line(pos_sel + Vector2(d, d), pos_sel + Vector2(d - 3, d), cor_sel, 1.0)
		draw_line(pos_sel + Vector2(d, d), pos_sel + Vector2(d, d - 3), cor_sel, 1.0)


func _desenhar_painel_inferior() -> void:
	# Banner de status textual (y = 124.0)
	var y_txt: float = 124.0
	if acabou:
		var pisca_ok: bool = fmod(t, 0.3) < 0.15
		var cor_sucesso: Color = BRANCO if pisca_ok else VERDE_LIMA
		Fonte.centralizado(self, "PRESSURE BALANCED // FUEL CELL ONLINE", 160.0, y_txt, cor_sucesso)
	elif perdeu:
		Fonte.centralizado(self, "CRITICAL OVERPRESSURE // SYSTEM FAILED", 160.0, y_txt, VERMELHO_CLARO)
	elif tempo_estavel > 0.0:
		var rest: float = maxf(0.0, TEMPO_ESTABILIDADE - tempo_estavel)
		Fonte.centralizado(self, "PRESSURE EQUALIZED - STABILIZING: %.1f S" % rest, 160.0, y_txt, VERDE_CLARO)
	elif t_erro > 0.0:
		Fonte.centralizado(self, "ALERT: PRESSURE OUT OF THE SAFE RANGE [55-72]", 160.0, y_txt, VERMELHO_CLARO)
	else:
		if selecionado == 0:
			Fonte.centralizado(self, "CROSSFEED A-B // [W] A->B   [S] B->A", 160.0, y_txt, BRANCO)
		elif selecionado == 1:
			Fonte.centralizado(self, "CROSSFEED B-C // [W] B->C   [S] C->B", 160.0, y_txt, BRANCO)
		else:
			Fonte.centralizado(self, "CRYO PURGE // [W / E] VENT THE GAS", 160.0, y_txt, AMARELO)

	# Barra de Estabilidade (y = 134.0 a 141.0)
	draw_rect(BARRA_ESTAB.grow(1), PRETO)
	draw_rect(BARRA_ESTAB, CINZA_ESC)
	draw_rect(Rect2(BARRA_ESTAB.position + Vector2(1, 1), BARRA_ESTAB.size - Vector2(2, 2)), NOITE)

	var progresso: float = clampf(tempo_estavel / TEMPO_ESTABILIDADE, 0.0, 1.0)
	var w_prog: float = roundf(progresso * (BARRA_ESTAB.size.x - 4.0))
	if w_prog > 0.0:
		var cor_b: Color = VERDE_LIMA if progresso >= 1.0 else VERDE
		draw_rect(Rect2(BARRA_ESTAB.position + Vector2(2, 2), Vector2(w_prog, BARRA_ESTAB.size.y - 4.0)), cor_b)
		draw_rect(Rect2(BARRA_ESTAB.position + Vector2(2, 2), Vector2(w_prog, 1.0)), BRANCO if progresso >= 1.0 else VERDE_LIMA)

	# Guia de Atalhos no Rodapé (y = 147.0) com cor BRANCO_SUJO de alto contraste sobre FUNDO escuro
	Fonte.centralizado(self, "A/D: VALVE   W/S: FLOW   E: QUICK PURGE", 160.0, 147.0, BRANCO_SUJO)


func _moldura() -> void:
	var p := PAINEL
	draw_rect(p, PRETO)
	draw_rect(p.grow(-1), CINZA)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(p.size.x - 2, 1)), METAL_CLARO)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(1, p.size.y - 2)), METAL)
	draw_rect(Rect2(p.position + Vector2(2, p.size.y - 2), Vector2(p.size.x - 3, 1)), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(p.size.x - 2, 2), Vector2(1, p.size.y - 3)), CINZA_ESC)

	# Rebites de fixação metálicos nos 4 cantos do painel
	for c: Vector2 in [Vector2(4, 4), Vector2(p.size.x - 7, 4), Vector2(4, p.size.y - 7), Vector2(p.size.x - 7, p.size.y - 7)]:
		draw_rect(Rect2(p.position + c, Vector2(3, 3)), METAL_CLARO)
		draw_rect(Rect2(p.position + c + Vector2.ONE, Vector2.ONE), CINZA_ESC)

	# Barra do cabeçalho
	draw_rect(Rect2(p.position + Vector2(8, 3), Vector2(p.size.x - 16, 12)), FUNDO)

	# Janela interior escura dos instrumentos (cobre TODO o restante do console!)
	draw_rect(Rect2(p.position + Vector2(6, 17), Vector2(p.size.x - 12, p.size.y - 23)), FUNDO)
	draw_rect(Rect2(p.position + Vector2(6, 17), Vector2(p.size.x - 12, p.size.y - 23)), CINZA_ESC, false, 1.0)


# --- Síntese Procedural de Áudio (AudioStreamWAV) ---
static func _sintetizar_fluxo() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.25
	var sample_count: int = int(duracao * 22050.0)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count

	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var seed_val: int = 12345
	for i: int in range(sample_count):
		var t_s: float = float(i) / 22050.0
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var ruido: float = (float(seed_val) / 0x3fffffff) - 1.0
		var tom: float = sin(t_s * 320.0 * TAU) * 0.15
		var sample: float = (ruido * 0.35 + tom) * 0.35
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream


static func _sintetizar_purga() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.30
	var sample_count: int = int(duracao * 22050.0)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count

	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var seed_val: int = 54321
	for i: int in range(sample_count):
		var t_s: float = float(i) / 22050.0
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var ruido: float = (float(seed_val) / 0x3fffffff) - 1.0
		var rumble: float = sin(t_s * 75.0 * TAU) * 0.4 + sin(t_s * 110.0 * TAU) * 0.3
		var sample: float = (ruido * 0.5 + rumble * 0.5) * 0.45
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream


static func _sintetizar_sucesso() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.75
	var sample_count: int = int(duracao * 22050.0)

	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t_s: float = float(i) / 22050.0
		var f: float = 523.25
		if t_s > 0.48:
			f = 1046.50
		elif t_s > 0.32:
			f = 783.99
		elif t_s > 0.16:
			f = 659.25

		var harm: float = sin(t_s * f * TAU) * 0.65 + sin(t_s * f * 2.0 * TAU) * 0.25
		var env: float = exp(-t_s * 3.5)
		var sample: float = harm * env * 0.65
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream


static func _sintetizar_troca() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.04
	var sample_count: int = int(duracao * 22050.0)

	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t_s: float = float(i) / 22050.0
		var sample: float = sin(t_s * 1200.0 * TAU) * exp(-t_s * 80.0) * 0.4
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream


static func _sintetizar_alerta() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.08
	var sample_count: int = int(duracao * 22050.0)

	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t_s: float = float(i) / 22050.0
		var sample: float = sin(t_s * 880.0 * TAU) * exp(-t_s * 30.0) * 0.35
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream
