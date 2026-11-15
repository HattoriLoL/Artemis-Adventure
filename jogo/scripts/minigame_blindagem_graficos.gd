class_name GraficosBlindagem
extends RefCounted
## Sistema Gráfico, de Materiais e VFX para o Minigame de Blindagem (Artemis Adventure).
## Resolução nativa: 320x180 | Paleta oficial Apollo/Artemis | Renderização procedural e pixel-art.

const Fonte = preload("res://scripts/fonte.gd")

# ==============================================================================
# PALETA OFICIAL APOLLO / ARTEMIS
# ==============================================================================
const PRETO := Color("#090a14")
const NOITE := Color("#10141f")
const FUNDO := Color("#151d28")
const AZUL_NOITE := Color("#172038")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const LARANJA := Color("#de9e41")
const LARANJA_ESC := Color("#be772b")
const VERDE_ESC := Color("#25562e")
const VERDE := Color("#468232")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const CIANO := Color("#73bed3")
const DOURADO_MLI := Color("#d4af37")
const DOURADO_ESC := Color("#8b7500")

# ==============================================================================
# CONSTANTES DE LAYOUT & ESTRUTURA
# ==============================================================================
const RES_LARGURA := 320
const RES_ALTURA := 180

# Chassi principal da antepara estrutural (Bulkhead Wall)
const CHASSI := Rect2(40, 16, 240, 148)

# Dimensões das placas científicas e cavidades de montagem
const TAMANHO_PLACA := 40
const BAIAS := [
	Rect2(60, 56, TAMANHO_PLACA, TAMANHO_PLACA),   # Baia 1: X=60, Y=56
	Rect2(140, 78, TAMANHO_PLACA, TAMANHO_PLACA),  # Baia 2: X=140, Y=78
	Rect2(220, 56, TAMANHO_PLACA, TAMANHO_PLACA)   # Baia 3: X=220, Y=56
]

# Nomes científicos e especificações das 3 placas
const NOMES_BAIAS := ["BAY 1: REGOLITH", "BAY 2: TI-ALLOY", "BAY 3: BORATED PE"]
const SUBTITULOS_BAIAS := [
	"SINTERED REGOLITH CERAMIC",
	"TI-6AL-4V IMPACT ALLOY",
	"BORATED UHMWPE / KEVLAR"
]

# Botão de saída rápida [X]
const BOTAO_X := Rect2(266, 18, 10, 10)

# Tolerância para ativação do alinhamento magnético
const DISTANCIA_ALINHADO := 8.0

# Tipos de placas
enum TipoPlaca {
	REGOLITO = 0,
	TITANIO = 1,
	KEVLAR = 2
}

# ==============================================================================
# SUBCLASSE DE PARTÍCULA DE FAÍSCA (PIXEL-ART VFX)
# ==============================================================================
class Faisca extends RefCounted:
	var pos: Vector2
	var vel: Vector2
	var vida: float
	var vida_max: float
	var cor: Color

	func _init(p_pos: Vector2, p_vel: Vector2, p_vida: float, p_cor: Color) -> void:
		pos = p_pos
		vel = p_vel
		vida = p_vida
		vida_max = p_vida
		cor = p_cor

# ==============================================================================
# VARIÁVEIS DE ESTADO E CACHE
# ==============================================================================
var tempo := 0.0
var modo_emergencia := false
var faiscas: Array[Faisca] = []
var tempo_jitter := 0.0
var forca_jitter := 1.0

# Texturas procedurais geradas uma única vez para performance máxima em GL Compatibility
var tex_mli: ImageTexture
var tex_regolito: ImageTexture
var tex_titanio: ImageTexture
var tex_kevlar: ImageTexture


# ==============================================================================
# INICIALIZAÇÃO
# ==============================================================================
func _init() -> void:
	_gerar_texturas_procedurais()


func _gerar_texturas_procedurais() -> void:
	tex_mli = _criar_textura_mli()
	tex_regolito = _criar_textura_regolito()
	tex_titanio = _criar_textura_titanio()
	tex_kevlar = _criar_textura_kevlar()


# ==============================================================================
# ATUALIZAÇÃO E SIMULAÇÃO DE VFX
# ==============================================================================
func atualizar(delta: float) -> void:
	tempo += delta
	if tempo_jitter > 0.0:
		tempo_jitter = maxf(0.0, tempo_jitter - delta)

	# Atualiza faíscas ativas
	var i := faiscas.size() - 1
	while i >= 0:
		var f := faiscas[i]
		f.vida -= delta
		if f.vida <= 0.0:
			faiscas.remove_at(i)
		else:
			f.pos += f.vel * delta
			f.vel.y += 160.0 * delta  # Gravidade suave
			# Gradiente térmico da faísca (Branco -> Amarelo -> Laranja -> Vermelho)
			var frac := f.vida / f.vida_max
			if frac > 0.7:
				f.cor = BRANCO
			elif frac > 0.4:
				f.cor = AMARELO
			elif frac > 0.2:
				f.cor = LARANJA
			else:
				f.cor = VERMELHO_CLARO
		i -= 1


func obter_jitter() -> Vector2:
	if tempo_jitter <= 0.0:
		return Vector2.ZERO
	var ang := randf() * TAU
	var dist := randf_range(0.5, forca_jitter)
	return Vector2(cos(ang) * dist, sin(ang) * dist).round()


func disparar_jitter(duracao := 0.15, forca := 1.0) -> void:
	tempo_jitter = duracao
	forca_jitter = forca


func adicionar_faiscas(origem: Vector2, qtd := 6, direcao := Vector2.ZERO) -> void:
	for k in qtd:
		var ang: float
		if direcao == Vector2.ZERO:
			ang = randf_range(-PI * 0.9, -PI * 0.1) # Spray para cima
		else:
			ang = direcao.angle() + randf_range(-0.6, 0.6)
		var vel := Vector2(cos(ang), sin(ang)) * randf_range(25.0, 75.0)
		var vida := randf_range(0.18, 0.38)
		faiscas.append(Faisca.new(origem, vel, vida, BRANCO))


# ==============================================================================
# RENDERIZADOR COMPLETO (MASTER DRAW)
# ==============================================================================
func desenhar_tudo(
	ci: CanvasItem,
	pos_cursor: Vector2,
	placa_atual: int,
	placas_fixadas: Array,
	progresso_parafuso: float,
	alinhado: bool,
	acabou: bool,
	mensagem: String,
	hover_x := false
) -> void:
	# 1. Estrutura da Antepara do Abrigo (Bulkhead Wall com I-Beams e Hazard Stripes)
	desenhar_antepara(ci)

	# 2. Baias de montagem rebaixadas com manta MLI e placas já fixadas
	desenhar_baias(ci, placas_fixadas, placa_atual, progresso_parafuso)

	# 3. Retícula tática militar e cursor carregando a placa da vez
	if not acabou and placa_atual < 3:
		desenhar_cursor_e_reticula(ci, pos_cursor, placa_atual, alinhado, progresso_parafuso)

	# 4. Efeitos visuais de faíscas em pixel-art
	desenhar_faiscas(ci)

	# 5. Display e banners superior/inferior de status
	desenhar_hud(ci, placa_atual, acabou, mensagem, hover_x)


# ==============================================================================
# 1. ESTRUTURA DA ANTEPARA DO ABRIGO (BULKHEAD WALL)
# ==============================================================================
func desenhar_antepara(ci: CanvasItem) -> void:
	# Fundo do compartimento do abrigo
	ci.draw_rect(Rect2(0, 0, RES_LARGURA, RES_ALTURA), NOITE)

	# Chassi principal da antepara estrutural: Rect2(40, 16, 240, 148)
	var r := CHASSI

	# Sombra projetada do chassi
	ci.draw_rect(Rect2(r.position.x + 2, r.position.y + 2, r.size.x, r.size.y), PRETO)

	# Placa de blindagem estrutural base
	ci.draw_rect(r, FUNDO)

	# Textura de chapas de aço naval/aeroespacial (divisões modulares)
	ci.draw_line(Vector2(120, r.position.y + 14), Vector2(120, r.end.y - 14), CINZA_ESC, 1.0)
	ci.draw_line(Vector2(200, r.position.y + 14), Vector2(200, r.end.y - 14), CINZA_ESC, 1.0)
	ci.draw_line(Vector2(121, r.position.y + 14), Vector2(121, r.end.y - 14), NOITE, 1.0)
	ci.draw_line(Vector2(201, r.position.y + 14), Vector2(201, r.end.y - 14), NOITE, 1.0)

	# Bordas duplas chanfradas em relevo (luz topo/esq em METAL_CLARO, sombra base/dir em PRETO)
	# Chanfro externo
	ci.draw_line(r.position, Vector2(r.end.x, r.position.y), METAL_CLARO, 1.0)
	ci.draw_line(r.position, Vector2(r.position.x, r.end.y), METAL_CLARO, 1.0)
	ci.draw_line(Vector2(r.end.x, r.position.y), r.end, PRETO, 1.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), r.end, PRETO, 1.0)

	# Chanfro interno
	var ri := Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2)
	ci.draw_line(ri.position, Vector2(ri.end.x, ri.position.y), METAL, 1.0)
	ci.draw_line(ri.position, Vector2(ri.position.x, ri.end.y), METAL, 1.0)
	ci.draw_line(Vector2(ri.end.x, ri.position.y), ri.end, AZUL_NOITE, 1.0)
	ci.draw_line(Vector2(ri.position.x, ri.end.y), ri.end, AZUL_NOITE, 1.0)

	# Vigas industriais duplas em I (Superior e Inferior) com hazard stripes e rebites
	_desenhar_viga_industrial(ci, Rect2(r.position.x + 2, r.position.y + 2, r.size.x - 4, 10), true)
	_desenhar_viga_industrial(ci, Rect2(r.position.x + 2, r.end.y - 12, r.size.x - 4, 10), false)

	# Rebites circulares industriais nas arestas verticais
	for y in range(int(r.position.y) + 18, int(r.end.y) - 16, 14):
		_desenhar_rebite(ci, Vector2(r.position.x + 5, y))
		_desenhar_rebite(ci, Vector2(r.end.x - 5, y))

	# Luzes de sinalização e emergência nas extremidades da viga
	_desenhar_baliza_emergencia(ci, Vector2(r.position.x + 12, r.position.y + 7))
	_desenhar_baliza_emergencia(ci, Vector2(r.end.x - 12, r.position.y + 7))

	# Decalques técnicos estêncil com Fonte.gd
	Fonte.centralizado(ci, "SECTOR 04 - STORM SHELTER // STRUCTURAL BULKHEAD", 160, 31, BRANCO_SUJO)
	Fonte.centralizado(ci, "RADIATION SHIELD: COMPOSITE REGOLITH / UHMWPE", 160, 39, CIANO)

	# Linha técnica de divisão
	ci.draw_line(Vector2(r.position.x + 16, 47), Vector2(r.end.x - 16, 47), CINZA_ESC, 1.0)
	ci.draw_line(Vector2(r.position.x + 16, 48), Vector2(r.end.x - 16, 48), NOITE, 1.0)


func _desenhar_viga_industrial(ci: CanvasItem, rect: Rect2, superior: bool) -> void:
	# Alma da viga de aço
	ci.draw_rect(rect, CINZA_ESC)

	# Flange metálica
	if superior:
		ci.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), METAL_CLARO, 1.0)
		ci.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, METAL, 1.0)
	else:
		ci.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), METAL, 1.0)
		ci.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, PRETO, 1.0)

	# Listras diagonais de advertência a 45° (Hazard Stripes)
	var faixa_x_inicio := float(rect.position.x + 24)
	var faixa_x_fim := float(rect.position.x + rect.size.x - 24)
	var y0 := float(rect.position.y + 2)
	var y1 := float(rect.position.y + rect.size.y - 2)
	var h := y1 - y0

	ci.draw_rect(Rect2(faixa_x_inicio, y0, faixa_x_fim - faixa_x_inicio, h), AMARELO)
	var passo := 7.0
	var x_cursor := faixa_x_inicio - h
	while x_cursor < faixa_x_fim + h:
		var p_inicio := Vector2(x_cursor, y1)
		var p_fim := Vector2(x_cursor + h, y0)
		var t0 := (faixa_x_inicio - p_inicio.x) / h
		var t1 := (faixa_x_fim - p_inicio.x) / h
		var t_min := clampf(maxf(0.0, t0), 0.0, 1.0)
		var t_max := clampf(minf(1.0, t1), 0.0, 1.0)
		if t_min < t_max:
			var pt_a := p_inicio.lerp(p_fim, t_min)
			var pt_b := p_inicio.lerp(p_fim, t_max)
			ci.draw_line(pt_a, pt_b, PRETO, 2.5)
		x_cursor += passo

	# Rebites ao longo da flange da viga
	for rx in range(faixa_x_inicio - 16, faixa_x_fim + 20, 28):
		if rx > rect.position.x + 4 and rx < rect.end.x - 4:
			_desenhar_rebite(ci, Vector2(rx, rect.position.y + rect.size.y / 2.0))


func _desenhar_rebite(ci: CanvasItem, pos: Vector2) -> void:
	# Rebite circular industrial 3D (highlight topo/esq, sombra base/dir)
	ci.draw_rect(Rect2(pos.x - 1, pos.y - 1, 3, 3), PRETO)
	ci.draw_rect(Rect2(pos.x - 1, pos.y - 1, 2, 2), METAL_CLARO)
	ci.draw_rect(Rect2(pos.x, pos.y, 1, 1), METAL)


func _desenhar_baliza_emergencia(ci: CanvasItem, pos: Vector2) -> void:
	# Base da baliza
	ci.draw_rect(Rect2(pos.x - 3, pos.y - 3, 6, 6), PRETO)
	ci.draw_rect(Rect2(pos.x - 2, pos.y - 2, 4, 4), CINZA_ESC)

	var cor_luz := VERDE
	if modo_emergencia:
		# Pulso de alarme de tempestade SEP / CME
		var pisca := sin(tempo * 10.0) > 0.0
		cor_luz = VERMELHO_CLARO if pisca else LARANJA_ESC
	else:
		# Operação padrão: pulso suave
		cor_luz = VERDE_LIMA if sin(tempo * 3.0) > -0.2 else VERDE

	ci.draw_rect(Rect2(pos.x - 1, pos.y - 1, 2, 2), cor_luz)


# ==============================================================================
# 2. BAIAS DE MONTAGEM E MANTA MLI DA NASA
# ==============================================================================
func desenhar_baias(ci: CanvasItem, placas_fixadas: Array, placa_atual: int, progresso_parafuso: float) -> void:
	for i in 3:
		var baia: Rect2 = BAIAS[i]
		var fixada: bool = (i < placas_fixadas.size() and placas_fixadas[i])

		# Cavidade rebaixada com chanfro invertido (sombra no topo/esq, luz na base/dir)
		ci.draw_rect(Rect2(baia.position.x - 2, baia.position.y - 2, baia.size.x + 4, baia.size.y + 4), PRETO)
		ci.draw_rect(Rect2(baia.position.x - 1, baia.position.y - 1, baia.size.x + 2, baia.size.y + 2), AZUL_NOITE)

		# Textura de isolamento térmico dourado NASA MLI no fundo da cavidade
		ci.draw_texture(tex_mli, baia.position)

		# 4 orifícios rosqueados de fixação nos 4 cantos da baia
		_desenhar_furo_fixacao(ci, baia.position + Vector2(5, 5))
		_desenhar_furo_fixacao(ci, baia.position + Vector2(baia.size.x - 5, 5))
		_desenhar_furo_fixacao(ci, baia.position + Vector2(5, baia.size.y - 5))
		_desenhar_furo_fixacao(ci, baia.position + Vector2(baia.size.x - 5, baia.size.y - 5))

		# Se já está fixada, desenha a placa científica instalada com parafusos travados
		if fixada:
			desenhar_placa(ci, i, baia, false, 1.0)
		elif i == placa_atual:
			# Destaque tático na cavidade da vez
			var pulse := (sin(tempo * 6.0) + 1.0) * 0.5
			var cor_alvo := AMARELO.lerp(BRANCO, pulse * 0.5)
			_desenhar_cantoneiras_baia(ci, baia, cor_alvo)

		# Indicador estêncil de identificação de cada baia
		var pos_texto_y := baia.end.y + 3
		var cor_label := VERDE_LIMA if fixada else (AMARELO if i == placa_atual else METAL)
		Fonte.centralizado(ci, NOMES_BAIAS[i], baia.position.x + baia.size.x / 2.0, pos_texto_y, cor_label)


func _desenhar_furo_fixacao(ci: CanvasItem, pos: Vector2) -> void:
	ci.draw_circle(pos, 2.5, PRETO)
	ci.draw_arc(pos, 2.5, 0, TAU, 8, CINZA_ESC, 1.0)
	ci.draw_rect(Rect2(pos.x - 0.5, pos.y - 0.5, 1, 1), NOITE)


func _desenhar_cantoneiras_baia(ci: CanvasItem, r: Rect2, cor: Color) -> void:
	var tam := 5.0
	# Cantos de alinhamento tático ao redor da baia
	# TL
	ci.draw_line(r.position, r.position + Vector2(tam, 0), cor, 1.0)
	ci.draw_line(r.position, r.position + Vector2(0, tam), cor, 1.0)
	# TR
	var tr := Vector2(r.end.x, r.position.y)
	ci.draw_line(tr, tr + Vector2(-tam, 0), cor, 1.0)
	ci.draw_line(tr, tr + Vector2(0, tam), cor, 1.0)
	# BL
	var bl := Vector2(r.position.x, r.end.y)
	ci.draw_line(bl, bl + Vector2(tam, 0), cor, 1.0)
	ci.draw_line(bl, bl + Vector2(0, -tam), cor, 1.0)
	# BR
	ci.draw_line(r.end, r.end + Vector2(-tam, 0), cor, 1.0)
	ci.draw_line(r.end, r.end + Vector2(0, -tam), cor, 1.0)


# ==============================================================================
# 3. RENDERIZAÇÃO PROCEDURAL DAS 3 PLACAS CIENTÍFICAS (40x40 CADA)
# ==============================================================================
func desenhar_placa(ci: CanvasItem, tipo: int, rect: Rect2, com_sombra := true, progresso_parafusos := 1.0) -> void:
	# Sombra projetada se a placa estiver suspensa/sendo carregada
	if com_sombra:
		ci.draw_rect(Rect2(rect.position.x + 3, rect.position.y + 4, rect.size.x, rect.size.y), Color(0.05, 0.06, 0.1, 0.6))

	# Desenha a textura procedural de material científico correspondente
	match tipo:
		TipoPlaca.REGOLITO:
			ci.draw_texture(tex_regolito, rect.position)
		TipoPlaca.TITANIO:
			ci.draw_texture(tex_titanio, rect.position)
		TipoPlaca.KEVLAR:
			ci.draw_texture(tex_kevlar, rect.position)

	# Aro perimetral de titânio chanfrado em relevo
	ci.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), METAL_CLARO, 1.0)
	ci.draw_line(rect.position, Vector2(rect.position.x, rect.end.y), METAL_CLARO, 1.0)
	ci.draw_line(Vector2(rect.end.x, rect.position.y), rect.end, CINZA_ESC, 1.0)
	ci.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, CINZA_ESC, 1.0)

	# 4 Parafusos pneumáticos animados nos cantos da placa
	desenhar_parafusos(ci, rect, progresso_parafusos)


# ==============================================================================
# 4. OS 4 PARAFUSOS PNEUMÁTICOS ANIMADOS
# ==============================================================================
func desenhar_parafusos(ci: CanvasItem, rect: Rect2, progresso: float) -> void:
	var cantos := [
		rect.position + Vector2(5, 5),               # Superior Esquerdo
		rect.position + Vector2(rect.size.x - 5, 5),  # Superior Direito
		rect.position + Vector2(5, rect.size.y - 5),  # Inferior Esquerdo
		rect.position + Vector2(rect.size.x - 5, rect.size.y - 5) # Inferior Direito
	]

	for i in 4:
		var pos_parafuso: Vector2 = cantos[i]

		# Cálculo do progresso individual por parafuso (sequencial ou unificado)
		var prog_bolt := clampf((progresso - i * 0.22) / 0.34, 0.0, 1.0)
		if progresso >= 1.0:
			prog_bolt = 1.0

		if prog_bolt <= 0.0:
			# Estado 1: Ausente (orifício escuro rosqueado à espera do parafuso)
			ci.draw_circle(pos_parafuso, 3.0, PRETO)
			ci.draw_arc(pos_parafuso, 3.0, 0, TAU, 8, CINZA_ESC, 1.0)
		elif prog_bolt < 1.0:
			# Estado 2: Em rotação rápida com fenda girando e faíscas dinâmicas
			ci.draw_circle(pos_parafuso, 3.2, METAL)
			var ang := tempo * 45.0 + i * 1.57
			var dir := Vector2(cos(ang), sin(ang)) * 2.2
			ci.draw_line(pos_parafuso - dir, pos_parafuso + dir, PRETO, 1.5)
			# Anel metálico de atrito
			ci.draw_arc(pos_parafuso, 3.2, 0, TAU, 8, METAL_CLARO, 1.0)

			# Dispara faíscas periódicas durante o aperto pneumático
			if randf() < 0.25:
				adicionar_faiscas(pos_parafuso, 2)
		else:
			# Estado 3: Totalmente parafusado, cravado com highlight 3D e fenda travada
			ci.draw_circle(pos_parafuso, 3.5, METAL)
			# Chanfro 3D
			ci.draw_arc(pos_parafuso, 3.5, PI * 0.75, PI * 1.75, 8, BRANCO, 1.0)
			ci.draw_arc(pos_parafuso, 3.5, -PI * 0.25, PI * 0.75, 8, PRETO, 1.0)
			# Fenda em cruz industrial travada
			ci.draw_line(pos_parafuso - Vector2(2, 0), pos_parafuso + Vector2(2, 0), PRETO, 1.0)
			ci.draw_line(pos_parafuso - Vector2(0, 2), pos_parafuso + Vector2(0, 2), PRETO, 1.0)
			ci.draw_rect(Rect2(pos_parafuso.x - 0.5, pos_parafuso.y - 0.5, 1, 1), BRANCO_SUJO)


# ==============================================================================
# 5. RETÍCULA TÁTICA E FEEDBACK DE ALINHAMENTO
# ==============================================================================
func desenhar_cursor_e_reticula(
	ci: CanvasItem,
	pos_cursor: Vector2,
	placa_idx: int,
	alinhado: bool,
	progresso_parafuso: float
) -> void:
	var rect_cursor := Rect2(pos_cursor, Vector2(TAMANHO_PLACA, TAMANHO_PLACA))
	var centro_cursor := pos_cursor + Vector2(TAMANHO_PLACA / 2.0, TAMANHO_PLACA / 2.0)
	var baia_alvo: Rect2 = BAIAS[placa_idx]
	var centro_alvo := baia_alvo.position + Vector2(TAMANHO_PLACA / 2.0, TAMANHO_PLACA / 2.0)
	var dist := centro_cursor.distance_to(centro_alvo)

	# Desenha a placa que o jogador está manipulando
	desenhar_placa(ci, placa_idx, rect_cursor, true, progresso_parafuso)

	# Mira militar em eixos X e Y
	if not alinhado:
		# Distante (> 8px): Mira âmbar tracejada com linha indicadora de distância
		var cor_mira := AMARELO

		# Linha de vetor guia tracejada até a baia alvo
		_desenhar_linha_tracejada(ci, centro_cursor, centro_alvo, cor_mira)

		# Retícula militar nos eixos
		_desenhar_reticula_militar(ci, rect_cursor, cor_mira, false)

		# Leitura tática de distância
		Fonte.centralizado(ci, "DIST: %d PX" % int(dist), centro_cursor.x, rect_cursor.end.y + 4, AMARELO)
	else:
		# Alinhado (<= 8px): Magnetismo suave e retícula pulsando em VERDE_LIMA brilhante
		var pulse := (sin(tempo * 12.0) + 1.0) * 0.5
		var cor_alinhado := VERDE_LIMA.lerp(BRANCO, pulse * 0.4)

		# Retícula cravada com pulso e conector magnético
		_desenhar_reticula_militar(ci, rect_cursor, cor_alinhado, true)

		# Indicação de pronto para parafusar
		Fonte.centralizado(ci, "[READY TO BOLT]", centro_cursor.x, rect_cursor.position.y - 8, VERDE_LIMA)
		Fonte.centralizado(ci, "APERTE [E] PARA FIXAR", centro_cursor.x, rect_cursor.end.y + 4, BRANCO)


func _desenhar_reticula_militar(ci: CanvasItem, r: Rect2, cor: Color, travado: bool) -> void:
	var tam := 6.0 if not travado else 8.0
	# Cantoneiras táticas
	ci.draw_line(r.position, r.position + Vector2(tam, 0), cor, 1.5)
	ci.draw_line(r.position, r.position + Vector2(0, tam), cor, 1.5)

	var tr := Vector2(r.end.x, r.position.y)
	ci.draw_line(tr, tr + Vector2(-tam, 0), cor, 1.5)
	ci.draw_line(tr, tr + Vector2(0, tam), cor, 1.5)

	var bl := Vector2(r.position.x, r.end.y)
	ci.draw_line(bl, bl + Vector2(tam, 0), cor, 1.5)
	ci.draw_line(bl, bl + Vector2(0, -tam), cor, 1.5)

	ci.draw_line(r.end, r.end + Vector2(-tam, 0), cor, 1.5)
	ci.draw_line(r.end, r.end + Vector2(0, -tam), cor, 1.5)

	# Marcadores centrais de cruz
	var c := r.position + r.size / 2.0
	ci.draw_line(Vector2(c.x - 3, c.y), Vector2(c.x + 3, c.y), cor, 1.0)
	ci.draw_line(Vector2(c.x, c.y - 3), Vector2(c.x, c.y + 3), cor, 1.0)


func _desenhar_linha_tracejada(ci: CanvasItem, de: Vector2, para: Vector2, cor: Color) -> void:
	var total := de.distance_to(para)
	if total < 2.0:
		return
	var dir := (para - de).normalized()
	var seg_len := 4.0
	var espaco := 3.0
	var d := 0.0
	while d < total:
		var p1 := de + dir * d
		var p2 := de + dir * minf(d + seg_len, total)
		ci.draw_line(p1, p2, cor, 1.0)
		d += seg_len + espaco


# ==============================================================================
# 6. EFEITOS VISUAIS, FAÍSCAS E HUD DE EMERGÊNCIA
# ==============================================================================
func desenhar_faiscas(ci: CanvasItem) -> void:
	for f in faiscas:
		ci.draw_rect(Rect2(f.pos.x, f.pos.y, 1.5, 1.5), f.cor)


func desenhar_hud(ci: CanvasItem, placa_atual: int, acabou: bool, mensagem: String, hover_x: bool) -> void:
	# Banner Superior: Status da missão e nível de radiação
	ci.draw_rect(Rect2(0, 0, RES_LARGURA, 14), PRETO)
	ci.draw_line(Vector2(0, 14), Vector2(RES_LARGURA, 14), CINZA_ESC, 1.0)

	if modo_emergencia:
		var pisca := sin(tempo * 8.0) > 0.0
		var cor_alerta := VERMELHO_CLARO if pisca else AMARELO
		Fonte.desenhar(ci, "! ALERT: CME SOLAR STORM IN PROGRESS !", Vector2(10, 4), cor_alerta)
	else:
		Fonte.desenhar(ci, "ARTEMIS SHELTER // STRUCTURAL SEALING", Vector2(10, 4), BRANCO_SUJO)

	# Indicador de progresso de blindagem
	var prog_str := "PROGRESS: %d/3" % mini(placa_atual, 3)
	Fonte.desenhar(ci, prog_str, Vector2(210, 4), AMARELO if not acabou else VERDE_LIMA)

	# Botão [X] de saída rápida
	desenhar_botao_x(ci, hover_x)

	# Banner Inferior: Guia tático de comandos ou conclusão
	ci.draw_rect(Rect2(0, RES_ALTURA - 14, RES_LARGURA, 14), PRETO)
	ci.draw_line(Vector2(0, RES_ALTURA - 14), Vector2(RES_LARGURA, RES_ALTURA - 14), CINZA_ESC, 1.0)

	if acabou:
		var txt := mensagem if not mensagem.is_empty() else "BLINDAGEM ESTRUTURAL REFORCADA!"
		Fonte.centralizado(ci, txt, 160, RES_ALTURA - 10, VERDE_LIMA)
	else:
		var rodape := "[WASD / SETAS] MOVER    [E] PARAFUSAR    [ESC] SAIR"
		Fonte.centralizado(ci, rodape, 160, RES_ALTURA - 10, BRANCO_SUJO)


func desenhar_botao_x(ci: CanvasItem, hover := false) -> void:
	var r := BOTAO_X
	var bg_cor := CINZA_ESC if hover else NOITE
	var borda_cor := VERMELHO_CLARO if hover else METAL

	ci.draw_rect(r, bg_cor)
	ci.draw_rect(r, borda_cor, false, 1.0)

	# Ícone 'X' em pixel-art
	var c := r.position + r.size / 2.0
	var cor_x := BRANCO if hover else BRANCO_SUJO
	ci.draw_line(Vector2(c.x - 2, c.y - 2), Vector2(c.x + 3, c.y + 3), cor_x, 1.0)
	ci.draw_line(Vector2(c.x - 2, c.y + 2), Vector2(c.x + 3, c.y - 3), cor_x, 1.0)


# ==============================================================================
# PROCEDURAL TEXTURE GENERATORS (40x40 PIXEL ART NATIVO)
# ==============================================================================
func _criar_textura_mli() -> ImageTexture:
	# Manta de Isolamento Térmico Dourada da NASA (Multi-Layer Insulation)
	var img := Image.create(TAMANHO_PLACA, TAMANHO_PLACA, false, Image.FORMAT_RGBA8)

	for y in TAMANHO_PLACA:
		for x in TAMANHO_PLACA:
			# Padrão losangular acolchoado de costura aeroespacial
			var s1 := (x + y) % 8
			var s2 := (x - y + 400) % 8
			var cor := DOURADO_MLI

			if s1 == 0 or s2 == 0:
				# Costura e vinco do isolamento térmico
				cor = DOURADO_ESC
			else:
				# Micro-rugas e reflexo especular do filme de poliamida aluminizada
				var crinkle := ((x * 13 + y * 19 + (x ^ y) * 7) % 11)
				if crinkle == 0:
					cor = AMARELO
				elif crinkle == 1:
					cor = BRANCO_SUJO
				elif crinkle >= 8:
					cor = LARANJA_ESC
				else:
					cor = DOURADO_MLI

			img.set_pixel(x, y, cor)

	return ImageTexture.create_from_image(img)


func _criar_textura_regolito() -> ImageTexture:
	# Placa 1: Rególito Lunar Sinterizado (Cerâmica Basáltica Compactada)
	var img := Image.create(TAMANHO_PLACA, TAMANHO_PLACA, false, Image.FORMAT_RGBA8)

	for y in TAMANHO_PLACA:
		for x in TAMANHO_PLACA:
			# Aro perimetral de titânio (2px)
			if x < 2 or y < 2 or x >= TAMANHO_PLACA - 2 or y >= TAMANHO_PLACA - 2:
				var cor_borda := METAL
				if x == 0 or y == 0:
					cor_borda = METAL_CLARO
				elif x == TAMANHO_PLACA - 1 or y == TAMANHO_PLACA - 1:
					cor_borda = CINZA_ESC
				img.set_pixel(x, y, cor_borda)
				continue

			# Cavidade central com alça metálica de fixação e manuseio
			if y >= 17 and y <= 22 and x >= 11 and x <= 28:
				if y == 19 or y == 20:
					# Barra da alça
					img.set_pixel(x, y, METAL_CLARO if y == 19 else METAL)
				elif x == 12 or x == 13 or x == 26 or x == 27:
					# Suportes laterais da alça
					img.set_pixel(x, y, METAL)
				else:
					# Sombra do rebaixo da alça
					img.set_pixel(x, y, PRETO)
				continue

			# Matriz mineral rugosa com micro-granulação (vidros de impacto e anortosito)
			var h := int((x * 37 + y * 73 + (x ^ y) * 19) & 0x7FFFFFFF)
			var val := float(h % 100) / 100.0
			var cor := CINZA_ESC

			if val < 0.22:
				cor = NOITE        # Poro ou grânulo escuro de ilmenita
			elif val < 0.55:
				cor = CINZA_ESC    # Matriz sinterizada padrão
			elif val < 0.82:
				cor = CINZA        # Grânulo de basalto lunar
			elif val < 0.94:
				cor = METAL        # Inclusão vítrea de impacto
			else:
				cor = BRANCO_SUJO  # Cristal de plagioclásio/anortosito

			img.set_pixel(x, y, cor)

	return ImageTexture.create_from_image(img)


func _criar_textura_titanio() -> ImageTexture:
	# Placa 2: Liga Titânio-Alumínio (Ti-6Al-4V escovado com nervuras diagonais)
	var img := Image.create(TAMANHO_PLACA, TAMANHO_PLACA, false, Image.FORMAT_RGBA8)

	for y in TAMANHO_PLACA:
		for x in TAMANHO_PLACA:
			# Aro perimetral
			if x < 2 or y < 2 or x >= TAMANHO_PLACA - 2 or y >= TAMANHO_PLACA - 2:
				var cor_b := METAL
				if x == 0 or y == 0:
					cor_b = METAL_CLARO
				elif x == TAMANHO_PLACA - 1 or y == TAMANHO_PLACA - 1:
					cor_b = CINZA_ESC
				img.set_pixel(x, y, cor_b)
				continue

			# Metal escovado direcional (linhas horizontais finas)
			var brush := (y * 11 + x / 3) % 5
			var cor := METAL
			if brush == 0 or brush == 3:
				cor = METAL_CLARO
			elif brush == 1:
				cor = CINZA
			else:
				cor = METAL

			# Nervuras estruturais diagonais a 45° para absorção de impacto micrometeórico
			# Nervura central e nervuras laterais de reforço
			var d_centro := (x - y)
			var e_nervura := absi(d_centro) <= 1 or absi(d_centro - 12) <= 1 or absi(d_centro + 12) <= 1

			if e_nervura:
				# Relevo 3D da nervura (luz no topo-esquerdo, sombra na base-direita)
				var borda_sup := (d_centro == -1 or d_centro == 11 or d_centro == -13)
				var borda_inf := (d_centro == 1 or d_centro == 13 or d_centro == -11)
				if borda_sup:
					cor = BRANCO_SUJO
				elif borda_inf:
					cor = CINZA_ESC
				else:
					cor = METAL_CLARO

			# Brilho direcional metálico em ângulo oposto
			var sheen := absi((x + y) - 38)
			if sheen <= 2:
				cor = cor.lerp(BRANCO, 0.45)
			elif sheen <= 5:
				cor = cor.lerp(METAL_CLARO, 0.25)

			img.set_pixel(x, y, cor)

	return ImageTexture.create_from_image(img)


func _criar_textura_kevlar() -> ImageTexture:
	# Placa 3: Polietileno Borado / Kevlar (Malha Hexagonal Honeycomb para blindagem de nêutrons)
	var img := Image.create(TAMANHO_PLACA, TAMANHO_PLACA, false, Image.FORMAT_RGBA8)

	for y in TAMANHO_PLACA:
		for x in TAMANHO_PLACA:
			# Casing protetor perimetral
			if x < 2 or y < 2 or x >= TAMANHO_PLACA - 2 or y >= TAMANHO_PLACA - 2:
				var cor_c := CINZA_ESC
				if x == 0 or y == 0:
					cor_c = METAL_CLARO
				elif x == TAMANHO_PLACA - 1 or y == TAMANHO_PLACA - 1:
					cor_c = NOITE
				img.set_pixel(x, y, cor_c)
				continue

			# Geometria da malha hexagonal celular (Honeycomb)
			var gx := x % 8
			var gy := y % 6
			var row := y / 6
			if row % 2 == 1:
				gx = (x + 4) % 8

			var e_borda := false
			var borda_iluminada := false

			if (gy == 0 or gy == 5) and (gx >= 2 and gx <= 5):
				e_borda = true
				borda_iluminada = (gy == 0)
			elif (gy == 1 or gy == 4) and (gx == 1 or gx == 6):
				e_borda = true
				borda_iluminada = (gy == 1)
			elif (gy == 2 or gy == 3) and (gx == 0 or gx == 7):
				e_borda = true
				borda_iluminada = (gx == 0)

			var cor := BRANCO_SUJO
			if e_borda:
				# Paredes hexagonais de Kevlar reforçado
				cor = BRANCO if borda_iluminada else CINZA
			else:
				# Núcleo de polietileno carregado com boro (UHMWPE-B)
				if gy <= 2:
					cor = BRANCO.lerp(CIANO, 0.15)
				elif gy == 3:
					cor = BRANCO_SUJO
				else:
					cor = METAL_CLARO.lerp(CIANO, 0.10)

			img.set_pixel(x, y, cor)

	return ImageTexture.create_from_image(img)
