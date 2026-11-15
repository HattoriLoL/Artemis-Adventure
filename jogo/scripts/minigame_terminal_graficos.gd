# ==============================================================================
# Artemis Adventure - Procedural Breaker Panel Graphics (Pixel Art 16-bit)
# Arquivo: minigame_terminal_graficos.gd
# Art Director & Procedural Graphics Engineer: Agente 01 / Agente 02
# Resolução nativa: 320x180 | Paleta Oficial Apollo/Artemis
# ==============================================================================
class_name GraficosTerminal
extends RefCounted

const Fonte = preload("res://scripts/fonte.gd")

# ------------------------------------------------------------------------------
# PALETA OFICIAL DO PROJETO (Apollo / Artemis 16-bit)
# ------------------------------------------------------------------------------
const PRETO          := Color("#090a14")
const NOITE          := Color("#10141f")
const FUNDO          := Color("#151d28")
const AZUL_NOITE     := Color("#172038")
const CINZA_ESC      := Color("#394a50")
const CINZA          := Color("#577277")
const METAL          := Color("#819796")
const METAL_CLARO    := Color("#a8b5b2")
const BRANCO         := Color("#ebede9")
const BRANCO_SUJO    := Color("#c7cfcc")
const AMARELO        := Color("#e8c170")
const LARANJA        := Color("#de9e41")
const VERDE          := Color("#468232")
const VERDE_LIMA     := Color("#a8ca58")
const VERMELHO       := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const CIANO          := Color("#73bed3")
const APAGADO        := Color("#10141f")

# ------------------------------------------------------------------------------
# CONSTANTES DE GEOMETRIA E COORDENADAS INTEIRAS (320x180)
# ------------------------------------------------------------------------------
const TELA_LARGURA: int = 320
const TELA_ALTURA: int = 180

# Chassi principal: centralizado horizontal e verticalmente
# 44 + 232 = 276 (Margem esq: 44, dir: 44) | 14 + 152 = 166 (Margem topo: 14, base: 14)
const RECT_CHASSI := Rect2i(44, 14, 232, 152)

# Moldura superior de identificação industrial
const RECT_MOLDURA_TOPO := Rect2i(60, 19, 200, 18)

# Posições centrais harmônicas das 4 baias de disjuntores em X
const CENTROS_X: Array[int] = [80, 134, 188, 242]
const BAIAS_LARGURA: int = 36
const BAIAS_ALTURA: int = 99
const BAIAS_Y: int = 41

# Cavidade / slot mecânico onde a alavanca corre dentro de cada baia
const SLOT_LARGURA: int = 16
const SLOT_ALTURA: int = 40
const SLOT_OFFSET_Y: int = 36 # relativo a BAIAS_Y (41 + 36 = 77)

# Dimensões da alavanca física 3D
const ALAVANCA_LARGURA: int = 14
const ALAVANCA_ALTURA: int = 20
const CURSO_ALAVANCA: int = 20 # SLOT_ALTURA - ALAVANCA_ALTURA (40 - 20)

# Display digital inferior de status do barramento
const RECT_DISPLAY_STATUS := Rect2i(58, 144, 204, 16)

# Botão de fechar/cancelar rápido [X]
const RECT_BOTAO_X := Rect2i(263, 18, 9, 9)

# Nomes e especificações técnicas de cada circuito
const IDENTIFICACOES_CB: Array[String] = ["CB-1", "CB-2", "CB-3", "CB-4"]
const SUBSISTEMAS_CB: Array[String] = ["O2 SYS", "COMM 1", "BATT A", "NAV GYR"]
const AMPERAGEM_CB: Array[String] = ["20A", "15A", "30A", "10A"]


# ------------------------------------------------------------------------------
# ESTRUTURA DE DADOS DO PAINEL (Para facilitar consumo pelo minigame_terminal.gd)
# ------------------------------------------------------------------------------
class DadosPainel:
	var estado: int = 0                  # 0: MOSTRANDO, 1: JOGADOR, 2: ERRO, 3: CONCLUIDO
	var selecionado: int = 0             # 0 a 3
	var passo_jogador: int = 0           # 0 a 3
	var total_passos: int = 4
	var posicoes_alavancas: Array[float] = [0.0, 0.0, 0.0, 0.0] # 0.0 = OFF (baixo), 1.0 = ON (cima)
	var leds_cores: Array[Color] = [APAGADO, APAGADO, APAGADO, APAGADO]
	var leds_acesos: Array[bool] = [false, false, false, false]
	var tempo: float = 0.0
	var mensagem_customizada: String = ""
	var modo_emergencia: String = ""
	var tempo_restante_emergencia: float = 0.0


# ==============================================================================
# FUNÇÕES PRINCIPAIS DE DESENHO (DRAW ORCHESTRATOR)
# ==============================================================================

## Função principal com assinatura aberta direta para minigame_terminal.gd
static func desenhar_painel(
	ci: CanvasItem,
	estado: int,
	selecionado: int,
	passo_jogador: int,
	posicoes_alavancas: Array[float],
	leds_cores: Array[Color],
	leds_acesos: Array[bool],
	tempo: float,
	mensagem: String = "",
	modo_emergencia: String = "",
	tempo_restante_emergencia: float = 0.0
) -> void:
	var dados := DadosPainel.new()
	dados.estado = estado
	dados.selecionado = selecionado
	dados.passo_jogador = passo_jogador
	dados.posicoes_alavancas = posicoes_alavancas
	dados.leds_cores = leds_cores
	dados.leds_acesos = leds_acesos
	dados.tempo = tempo
	dados.mensagem_customizada = mensagem
	dados.modo_emergencia = modo_emergencia
	dados.tempo_restante_emergencia = tempo_restante_emergencia
	desenhar_painel_completo(ci, dados)


## Função para desenhar um disjuntor individual / baia modular completa
static func desenhar_disjuntor(
	ci: CanvasItem,
	rect_baia: Rect2i,
	indice: int,
	selecionada: bool,
	pos_alavanca: float,
	cor_led: Color,
	led_aceso: bool,
	tempo: float
) -> void:
	desenhar_baia(ci, rect_baia, indice, selecionada, pos_alavanca, cor_led, led_aceso, tempo)


## Função orquestradora que consome o objeto de estado DadosPainel
static func desenhar_painel_completo(ci: CanvasItem, dados: DadosPainel) -> void:
	# 1. Escurecimento do fundo externo para foco no painel
	desenhar_fundo_escuro(ci)

	# 2. Chassi metálico industrial com chanfros, relevo e parafusos
	desenhar_chassi(ci, RECT_CHASSI)

	# 3. Decalques industriais e listras de advertência
	desenhar_decoracoes_chassi(ci, RECT_CHASSI)

	# 4. Moldura superior rebitada com tipografia técnica
	desenhar_moldura_identificacao(ci, RECT_MOLDURA_TOPO, dados.tempo, dados.modo_emergencia, dados.tempo_restante_emergencia)

	# 5. As 4 baias de disjuntores
	for i in range(4):
		var x: int = CENTROS_X[i] - (BAIAS_LARGURA / 2)
		var rect_baia := Rect2i(x, BAIAS_Y, BAIAS_LARGURA, BAIAS_ALTURA)
		var esta_selecionada: bool = (dados.selecionado == i and dados.estado == 1)
		var pos_alavanca: float = dados.posicoes_alavancas[i] if i < dados.posicoes_alavancas.size() else 0.0
		var cor_led: Color = dados.leds_cores[i] if i < dados.leds_cores.size() else APAGADO
		var led_aceso: bool = dados.leds_acesos[i] if i < dados.leds_acesos.size() else false

		desenhar_baia(
			ci,
			rect_baia,
			i,
			esta_selecionada,
			pos_alavanca,
			cor_led,
			led_aceso,
			dados.tempo
		)

	# 6. Linhas de barramento elétrico conectando disjuntores ao display
	desenhar_barramento_eletrico(ci)

	# 7. Display digital inferior com prompt de comando e mensagens
	desenhar_display_status(ci, RECT_DISPLAY_STATUS, dados)

	# 8. Botão [X] de saída rápida / cancelar
	desenhar_botao_fechar(ci, RECT_BOTAO_X)


# ==============================================================================
# SUB-ROTINAS DE DESENHO PROCEDURAL
# ==============================================================================

## Desenha o fundo semitransparente escurecido fora do chassi
static func desenhar_fundo_escuro(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, TELA_LARGURA, TELA_ALTURA), Color(PRETO.r, PRETO.g, PRETO.b, 0.72))


## Desenha o chassi metálico industrial com chanfro 3D, placa escovada e parafusos
static func desenhar_chassi(ci: CanvasItem, r: Rect2i) -> void:
	# Sombra projetada do chassi na parede de fundo
	ci.draw_rect(Rect2(r.position.x + 2, r.position.y + 2, r.size.x, r.size.y), Color(PRETO.r, PRETO.g, PRETO.b, 0.60))

	# Borda externa preta sólida (contorno de pixel art)
	ci.draw_rect(Rect2(r), PRETO)

	# Face principal chanfrada da placa de aço
	# Highlights topo e esquerda (luz industrial zenital vindo do topo-esquerda)
	linha_h(ci, r.position.x + 1, r.position.y + 1, r.size.x - 2, BRANCO)
	linha_v(ci, r.position.x + 1, r.position.y + 1, r.size.y - 2, METAL_CLARO)

	# Sombras base e direita (relevo positivo)
	linha_h(ci, r.position.x + 1, r.position.y + r.size.y - 2, r.size.x - 2, PRETO)
	linha_v(ci, r.position.x + r.size.x - 2, r.position.y + 1, r.size.y - 2, CINZA_ESC)

	# Placa metálica interna
	var mi := Rect2i(r.position.x + 2, r.position.y + 2, r.size.x - 4, r.size.y - 4)
	ci.draw_rect(Rect2(mi), CINZA)

	# Segunda linha de chanfro interno para sensação de metal espesso de alta densidade
	linha_h(ci, mi.position.x, mi.position.y, mi.size.x, METAL_CLARO)
	linha_v(ci, mi.position.x, mi.position.y, mi.size.y, METAL)
	linha_h(ci, mi.position.x, mi.position.y + mi.size.y - 1, mi.size.x, CINZA_ESC)
	linha_v(ci, mi.position.x + mi.size.x - 1, mi.position.y, mi.size.y, CINZA_ESC)

	# Preenchimento do miolo da carcaça
	var corpo := Rect2i(mi.position.x + 1, mi.position.y + 1, mi.size.x - 2, mi.size.y - 2)
	ci.draw_rect(Rect2(corpo), FUNDO)

	# Micro-sulcos sutis de metal escovado / linhas de painel
	var y_linha := corpo.position.y + 23
	while y_linha < corpo.position.y + corpo.size.y - 20:
		linha_h(ci, corpo.position.x + 4, y_linha, corpo.size.x - 8, Color(AZUL_NOITE.r, AZUL_NOITE.g, AZUL_NOITE.b, 0.40))
		y_linha += 8

	# Parafusos industriais nos cantos (o canto superior direito é reservado para o botão de fechar X)
	desenhar_parafuso(ci, Vector2i(r.position.x + 7, r.position.y + 7), true)
	desenhar_parafuso(ci, Vector2i(r.position.x + 7, r.position.y + r.size.y - 8), false)
	desenhar_parafuso(ci, Vector2i(r.position.x + r.size.x - 8, r.position.y + r.size.y - 8), true)

	# Parafusos centrais de sustentação na borda
	desenhar_parafuso(ci, Vector2i(r.position.x + (r.size.x / 2), r.position.y + 7), true)
	desenhar_parafuso(ci, Vector2i(r.position.x + (r.size.x / 2), r.position.y + r.size.y - 8), true)


## Parafuso mecânico usinado com cabeça metálica, chanfro e fenda (+ ou x) gravada
static func desenhar_parafuso(ci: CanvasItem, centro: Vector2i, fenda_cruz: bool = true) -> void:
	# Base 5x5 do parafuso
	var r := Rect2i(centro.x - 2, centro.y - 2, 5, 5)
	ci.draw_rect(Rect2(r), PRETO)

	# Cabeça metálica circularchanfrada (cantos cortados)
	px(ci, Vector2i(r.position.x + 1, r.position.y), METAL_CLARO)
	px(ci, Vector2i(r.position.x + 2, r.position.y), METAL_CLARO)
	px(ci, Vector2i(r.position.x + 3, r.position.y), METAL_CLARO)

	px(ci, Vector2i(r.position.x, r.position.y + 1), METAL_CLARO)
	px(ci, Vector2i(r.position.x + 1, r.position.y + 1), METAL)
	px(ci, Vector2i(r.position.x + 2, r.position.y + 1), METAL)
	px(ci, Vector2i(r.position.x + 3, r.position.y + 1), CINZA)
	px(ci, Vector2i(r.position.x + 4, r.position.y + 1), CINZA_ESC)

	px(ci, Vector2i(r.position.x, r.position.y + 2), METAL)
	px(ci, Vector2i(r.position.x + 1, r.position.y + 2), METAL)
	px(ci, Vector2i(r.position.x + 2, r.position.y + 2), CINZA)
	px(ci, Vector2i(r.position.x + 3, r.position.y + 2), CINZA_ESC)
	px(ci, Vector2i(r.position.x + 4, r.position.y + 2), PRETO)

	px(ci, Vector2i(r.position.x, r.position.y + 3), CINZA)
	px(ci, Vector2i(r.position.x + 1, r.position.y + 3), CINZA_ESC)
	px(ci, Vector2i(r.position.x + 2, r.position.y + 3), CINZA_ESC)
	px(ci, Vector2i(r.position.x + 3, r.position.y + 3), PRETO)
	px(ci, Vector2i(r.position.x + 4, r.position.y + 3), PRETO)

	px(ci, Vector2i(r.position.x + 1, r.position.y + 4), CINZA_ESC)
	px(ci, Vector2i(r.position.x + 2, r.position.y + 4), PRETO)
	px(ci, Vector2i(r.position.x + 3, r.position.y + 4), PRETO)

	# Fenda gravada no metal
	if fenda_cruz:
		# Fenda "+"
		px(ci, Vector2i(centro.x, centro.y), PRETO)
		px(ci, Vector2i(centro.x - 1, centro.y), PRETO)
		px(ci, Vector2i(centro.x + 1, centro.y), PRETO)
		px(ci, Vector2i(centro.x, centro.y - 1), PRETO)
		px(ci, Vector2i(centro.x, centro.y + 1), PRETO)
		# Highlight na borda da fenda
		px(ci, Vector2i(centro.x + 1, centro.y + 1), BRANCO)
	else:
		# Fenda diagonal "x"
		px(ci, Vector2i(centro.x, centro.y), PRETO)
		px(ci, Vector2i(centro.x - 1, centro.y - 1), PRETO)
		px(ci, Vector2i(centro.x + 1, centro.y + 1), PRETO)
		px(ci, Vector2i(centro.x + 1, centro.y - 1), PRETO)
		px(ci, Vector2i(centro.x - 1, centro.y + 1), PRETO)
		px(ci, Vector2i(centro.x, centro.y + 1), BRANCO)


## Desenha decorações industriais, avisos de alta voltagem e números de série
static func desenhar_decoracoes_chassi(ci: CanvasItem, r: Rect2i) -> void:
	# Pequenas listras diagonais de advertência (hazard stripes 16-bit) nas laterais do chassi
	desenhar_listras_hazard(ci, Rect2i(r.position.x + 4, r.position.y + 40, 4, 30))
	desenhar_listras_hazard(ci, Rect2i(r.position.x + r.size.x - 8, r.position.y + 40, 4, 30))

	# Estêncil técnico nas bordas laterais
	Fonte.desenhar(ci, "28V", Vector2(r.position.x + 4, r.position.y + 78), CINZA_ESC, 1, false)
	Fonte.desenhar(ci, "DC", Vector2(r.position.x + 6, r.position.y + 86), CINZA_ESC, 1, false)

	Fonte.desenhar(ci, "BUS", Vector2(r.position.x + r.size.x - 14, r.position.y + 78), CINZA_ESC, 1, false)
	Fonte.desenhar(ci, "1A", Vector2(r.position.x + r.size.x - 12, r.position.y + 86), CINZA_ESC, 1, false)

	# Número de registro do painel da Artemis
	Fonte.desenhar(ci, "ARTEMIS P-402", Vector2(r.position.x + 8, r.position.y + r.size.y - 10), CINZA_ESC, 1, false)
	Fonte.desenhar(ci, "NASA-JSC", Vector2(r.position.x + r.size.x - 38, r.position.y + r.size.y - 10), CINZA_ESC, 1, false)


## Listras de perigo industriais (amarelo e preto alternados a 45 graus)
static func desenhar_listras_hazard(ci: CanvasItem, area: Rect2i) -> void:
	ci.draw_rect(Rect2(area), PRETO)
	for y in range(area.position.y, area.position.y + area.size.y):
		for x in range(area.position.x, area.position.x + area.size.x):
			if (x + y) % 4 < 2:
				px(ci, Vector2i(x, y), AMARELO)


## Moldura superior rebitada com tipografia técnica oficial do painel
static func desenhar_moldura_identificacao(
	ci: CanvasItem,
	r: Rect2i,
	tempo: float,
	modo_emergencia: String = "",
	tempo_restante: float = 0.0
) -> void:
	# Base rebaixada em preto
	ci.draw_rect(Rect2(r), PRETO)

	# Chanfro interno em relevo invertido (sombra no topo/esquerda, luz na base/direita)
	linha_h(ci, r.position.x, r.position.y, r.size.x, NOITE)
	linha_v(ci, r.position.x, r.position.y, r.size.y, NOITE)
	linha_h(ci, r.position.x, r.position.y + r.size.y - 1, r.size.x, METAL)
	linha_v(ci, r.position.x + r.size.x - 1, r.position.y, r.size.y, METAL)

	# Placa de acrílico/metal militar interna
	var placa := Rect2i(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2)
	ci.draw_rect(Rect2(placa), AZUL_NOITE)

	# Rebites nas extremidades da placa
	desenhar_rebite(ci, Vector2i(placa.position.x + 4, placa.position.y + 8))
	desenhar_rebite(ci, Vector2i(placa.position.x + placa.size.x - 5, placa.position.y + 8))

	var tag_esq: String = "(MAIN BUS)"
	var cor_tag_esq: Color = CIANO
	var titulo: String = "CIRCUIT BREAKER PANEL"
	var cor_titulo: Color = AMARELO
	var pulso_pwr: float = 0.8 + 0.2 * sin(tempo * 4.0)
	var tag_dir: String = "28V DC"
	var cor_tag_dir: Color = Color(VERDE_LIMA.r, VERDE_LIMA.g, VERDE_LIMA.b, pulso_pwr)

	if modo_emergencia == "surge":
		tag_esq = "(OVERLOAD)"
		cor_tag_esq = VERMELHO_CLARO
		titulo = "SOLAR SURGE BUS"
		cor_titulo = AMARELO if fmod(tempo, 0.4) < 0.2 else VERMELHO_CLARO
		tag_dir = "%02d SEC" % ceili(tempo_restante)
		cor_tag_dir = VERMELHO_CLARO if fmod(tempo, 0.3) < 0.15 else BRANCO
	elif modo_emergencia == "blackout":
		tag_esq = "(BLACKOUT)"
		cor_tag_esq = VERMELHO_CLARO
		titulo = "GRID RESTORATION"
		cor_titulo = CIANO if fmod(tempo, 0.5) < 0.25 else AMARELO
		tag_dir = "%02d SEC" % ceili(tempo_restante)
		cor_tag_dir = VERMELHO_CLARO if fmod(tempo, 0.3) < 0.15 else BRANCO

	Fonte.desenhar(ci, tag_esq, Vector2(placa.position.x + 10, placa.position.y + 6), cor_tag_esq, 1, true)
	Fonte.centralizado(ci, titulo, placa.position.x + (placa.size.x / 2.0), placa.position.y + 6, cor_titulo, 1)
	Fonte.desenhar(ci, tag_dir, Vector2(placa.position.x + placa.size.x - 38, placa.position.y + 6), cor_tag_dir, 1, true)


## Rebite metálico pequeno (3x3 pixels)
static func desenhar_rebite(ci: CanvasItem, centro: Vector2i) -> void:
	ci.draw_rect(Rect2(centro.x - 1, centro.y - 1, 3, 3), PRETO)
	px(ci, Vector2i(centro.x - 1, centro.y - 1), BRANCO)
	px(ci, Vector2i(centro.x, centro.y - 1), METAL_CLARO)
	px(ci, Vector2i(centro.x - 1, centro.y), METAL_CLARO)
	px(ci, Vector2i(centro.x, centro.y), METAL)
	px(ci, Vector2i(centro.x + 1, centro.y + 1), CINZA_ESC)


## Desenha uma baia individual de disjuntor com todos seus subsistemas
static func desenhar_baia(
	ci: CanvasItem,
	r: Rect2i,
	indice: int,
	selecionada: bool,
	pos_alavanca: float,
	cor_led: Color,
	led_aceso: bool,
	tempo: float
) -> void:
	# 1. Nicho rebaixado no chassi (cavidade 3D com sombras internas)
	desenhar_nicho_rebaixado(ci, r)

	# 2. Plaqueta superior de identificação do disjuntor ("CB-1", "CB-2", etc.)
	var r_plaqueta := Rect2i(r.position.x + 3, r.position.y + 3, r.size.x - 6, 10)
	ci.draw_rect(Rect2(r_plaqueta), PRETO)
	linha_h(ci, r_plaqueta.position.x, r_plaqueta.position.y, r_plaqueta.size.x, CINZA_ESC)
	linha_v(ci, r_plaqueta.position.x, r_plaqueta.position.y, r_plaqueta.size.y, CINZA_ESC)
	linha_h(ci, r_plaqueta.position.x, r_plaqueta.position.y + r_plaqueta.size.y - 1, r_plaqueta.size.x, METAL_CLARO)
	linha_v(ci, r_plaqueta.position.x + r_plaqueta.size.x - 1, r_plaqueta.position.y, r_plaqueta.size.y, METAL_CLARO)

	var texto_cb: String = IDENTIFICACOES_CB[indice] if indice < IDENTIFICACOES_CB.size() else "CB"
	Fonte.centralizado(ci, texto_cb, r_plaqueta.position.x + (r_plaqueta.size.x / 2.0), r_plaqueta.position.y + 3, BRANCO, 1)

	# 3. Sub-rótulo do subsistema (ex: "O2 SYS", "20A")
	var texto_sub: String = SUBSISTEMAS_CB[indice] if indice < SUBSISTEMAS_CB.size() else ""
	Fonte.centralizado(ci, texto_sub, r.position.x + (r.size.x / 2.0), r.position.y + 15, CIANO, 1)

	# 4. Indicador LED com difusão/glow em pixel art
	var centro_led := Vector2i(r.position.x + (r.size.x / 2), r.position.y + 25)
	desenhar_led_glow(ci, centro_led, cor_led, led_aceso, tempo)

	# 5. Inscrições estêncil ON / OFF nas bordas da alavanca
	var cor_on: Color = VERDE_LIMA if pos_alavanca > 0.6 else CINZA_ESC
	var cor_off: Color = VERMELHO_CLARO if pos_alavanca < 0.4 else CINZA_ESC
	Fonte.centralizado(ci, "ON", r.position.x + (r.size.x / 2.0), r.position.y + 31, cor_on, 1)
	Fonte.centralizado(ci, "OFF", r.position.x + (r.size.x / 2.0), r.position.y + 79, cor_off, 1)

	# 6. Cavidade mecânica e chave basculante / alavanca 3D
	var x_slot: int = r.position.x + ((r.size.x - SLOT_LARGURA) / 2)
	var y_slot: int = r.position.y + SLOT_OFFSET_Y
	var r_slot := Rect2i(x_slot, y_slot, SLOT_LARGURA, SLOT_ALTURA)

	desenhar_alavanca_3d(ci, r_slot, pos_alavanca)

	# 7. Amperagem e número da baia no rodapé da baia
	var texto_amp: String = AMPERAGEM_CB[indice] if indice < AMPERAGEM_CB.size() else ""
	Fonte.centralizado(ci, texto_amp, r.position.x + (r.size.x / 2.0), r.position.y + 86, CINZA, 1)

	var cor_num: Color = AMARELO if selecionada else CINZA_ESC
	Fonte.centralizado(ci, "%d" % (indice + 1), r.position.x + (r.size.x / 2.0), r.position.y + 92, cor_num, 1)

	# 8. Cursor tático de seleção do jogador (se selecionada)
	if selecionada:
		desenhar_cursor_selecao(ci, r, tempo)


## Nicho rebaixado com relevo negativo (sombra interna superior e esquerda)
static func desenhar_nicho_rebaixado(ci: CanvasItem, r: Rect2i) -> void:
	# Contorno externo preto
	ci.draw_rect(Rect2(r), PRETO)

	# Sombra profunda interna no topo e na esquerda (nicho rebaixado)
	linha_h(ci, r.position.x + 1, r.position.y + 1, r.size.x - 2, PRETO)
	linha_v(ci, r.position.x + 1, r.position.y + 1, r.size.y - 2, PRETO)
	linha_h(ci, r.position.x + 2, r.position.y + 2, r.size.x - 4, NOITE)
	linha_v(ci, r.position.x + 2, r.position.y + 2, r.size.y - 4, NOITE)

	# Highlight de rebatimento de luz na base e na direita
	linha_h(ci, r.position.x + 1, r.position.y + r.size.y - 2, r.size.x - 2, METAL)
	linha_v(ci, r.position.x + r.size.x - 2, r.position.y + 1, r.size.y - 2, METAL)
	linha_h(ci, r.position.x, r.position.y + r.size.y - 1, r.size.x, METAL_CLARO)
	linha_v(ci, r.position.x + r.size.x - 1, r.position.y, r.size.y, METAL_CLARO)

	# Preenchimento interno do nicho
	var mi := Rect2i(r.position.x + 3, r.position.y + 3, r.size.x - 6, r.size.y - 6)
	ci.draw_rect(Rect2(mi), FUNDO)


## Indicador LED com difusão e glow de pixel art com halo suave em 1 a 2 pixels
static func desenhar_led_glow(
	ci: CanvasItem,
	centro: Vector2i,
	cor: Color,
	aceso: bool,
	tempo: float
) -> void:
	# Caixa/moldura de montagem do LED
	var moldura := Rect2i(centro.x - 5, centro.y - 4, 11, 9)
	ci.draw_rect(Rect2(moldura), PRETO)
	linha_h(ci, moldura.position.x, moldura.position.y, moldura.size.x, CINZA_ESC)
	linha_v(ci, moldura.position.x, moldura.position.y, moldura.size.y, CINZA_ESC)
	linha_h(ci, moldura.position.x, moldura.position.y + moldura.size.y - 1, moldura.size.x, METAL_CLARO)
	linha_v(ci, moldura.position.x + moldura.size.x - 1, moldura.position.y, moldura.size.y, METAL_CLARO)

	# Berço interno escuro
	var berco := Rect2i(centro.x - 4, centro.y - 3, 9, 7)
	ci.draw_rect(Rect2(berco), NOITE)

	if not aceso:
		# LED desligado: lente escura com reflexo de vidro opaco
		ci.draw_rect(Rect2(centro.x - 2, centro.y - 2, 5, 5), CINZA_ESC)
		ci.draw_rect(Rect2(centro.x - 1, centro.y - 1, 3, 3), NOITE)
		# Reflexo especular 1px
		px(ci, Vector2i(centro.x - 1, centro.y - 1), METAL)
	else:
		# LED ACESO:
		# Camada 3: Halo difuso externo (1 a 2 pixels além da lente, transparência controlada)
		var halo_ext := Color(cor.r, cor.g, cor.b, 0.18 + 0.05 * sin(tempo * 12.0))
		ci.draw_rect(Rect2(centro.x - 4, centro.y - 3, 9, 7), halo_ext)

		# Camada 2: Halo difuso intermediário
		var halo_int := Color(cor.r, cor.g, cor.b, 0.45 + 0.10 * sin(tempo * 12.0))
		ci.draw_rect(Rect2(centro.x - 3, centro.y - 2, 7, 5), halo_int)

		# Camada 1: Corpo da lente saturada
		ci.draw_rect(Rect2(centro.x - 2, centro.y - 2, 5, 5), cor)

		# Camada 0: Núcleo incandescente de alta energia (centro branco quente)
		ci.draw_rect(Rect2(centro.x - 1, centro.y - 1, 3, 3), BRANCO)

		# Reflexo brilhante no canto superior
		px(ci, Vector2i(centro.x - 1, centro.y - 2), BRANCO)


## Chave basculante / alavanca mecânica 3D em pixel art com interpolação suave
# pos_alavanca: 0.0 = desligado/baixo (OFF), 1.0 = ligado/cima (ON)
static func desenhar_alavanca_3d(ci: CanvasItem, slot: Rect2i, pos_alavanca: float) -> void:
	pos_alavanca = clampf(pos_alavanca, 0.0, 1.0)

	# 1. Cavidade mecânica do slot (fundo escuro e trilhos internos)
	ci.draw_rect(Rect2(slot), PRETO)

	# Sombra profunda no topo e bordas internas do slot
	linha_h(ci, slot.position.x + 1, slot.position.y + 1, slot.size.x - 2, NOITE)
	linha_v(ci, slot.position.x + 1, slot.position.y + 1, slot.size.y - 2, NOITE)
	linha_v(ci, slot.position.x + slot.size.x - 2, slot.position.y + 1, slot.size.y - 2, NOITE)

	# Trilho mecânico central onde o pivô se desloca
	var trilho_x: int = slot.position.x + (slot.size.x / 2) - 1
	ci.draw_rect(Rect2(trilho_x, slot.position.y + 2, 2, slot.size.y - 4), AZUL_NOITE)

	# 2. Posição Y calculada da alavanca física
	# Quando pos_alavanca = 0.0 (OFF), y está no fundo do slot (slot.position.y + CURSO_ALAVANCA)
	# Quando pos_alavanca = 1.0 (ON), y está no topo do slot (slot.position.y)
	var offset_y: int = roundi((1.0 - pos_alavanca) * float(CURSO_ALAVANCA))
	var alavanca_y: int = slot.position.y + offset_y
	var alavanca_x: int = slot.position.x + 1

	var r_alavanca := Rect2i(alavanca_x, alavanca_y, ALAVANCA_LARGURA, ALAVANCA_ALTURA)

	# 3. Haste interna / colar visível no espaço aberto
	# Se a alavanca estiver para baixo (OFF), exibe o eixo superior com anel de alerta vermelho/branco
	if offset_y > 4:
		var r_haste := Rect2i(alavanca_x + 3, slot.position.y + 2, ALAVANCA_LARGURA - 6, offset_y - 2)
		ci.draw_rect(Rect2(r_haste), CINZA_ESC)
		# Colar de advertência mecânica "TRIPPED / OPEN" típico de aeronáutica Apollo
		if r_haste.size.y >= 3:
			ci.draw_rect(Rect2(r_haste.position.x, r_haste.position.y + r_haste.size.y - 3, r_haste.size.x, 2), VERMELHO_CLARO)
			linha_h(ci, r_haste.position.x, r_haste.position.y + r_haste.size.y - 2, r_haste.size.x, BRANCO)

	# Se a alavanca estiver para cima (ON), o espaço inferior do slot fica escuro com sombra projetada
	elif offset_y < CURSO_ALAVANCA - 4:
		var sobra_y: int = alavanca_y + ALAVANCA_ALTURA
		var altura_sobra: int = (slot.position.y + slot.size.y) - sobra_y
		ci.draw_rect(Rect2(alavanca_x + 2, sobra_y, ALAVANCA_LARGURA - 4, altura_sobra), PRETO)

	# 4. Renderização 3D da alavanca (Rocker Switch)
	# Sombra de contato da alavanca
	ci.draw_rect(Rect2(r_alavanca), PRETO)

	# Chanfro externo da alavanca
	# A luz bate no topo se estiver inclinada para cima (ON), ou na base se inclinada para baixo
	var cor_topo: Color = BRANCO if pos_alavanca >= 0.5 else CINZA_ESC
	var cor_base: Color = PRETO if pos_alavanca >= 0.5 else METAL
	var cor_face: Color = METAL if pos_alavanca >= 0.5 else CINZA

	# Borda superior chanfrada
	linha_h(ci, r_alavanca.position.x + 1, r_alavanca.position.y + 1, r_alavanca.size.x - 2, cor_topo)
	# Borda esquerda com highlight de luz
	linha_v(ci, r_alavanca.position.x + 1, r_alavanca.position.y + 1, r_alavanca.size.y - 2, METAL_CLARO)
	# Borda direita com sombra de oclusão
	linha_v(ci, r_alavanca.position.x + r_alavanca.size.x - 2, r_alavanca.position.y + 1, r_alavanca.size.y - 2, PRETO)
	# Borda inferior
	linha_h(ci, r_alavanca.position.x + 1, r_alavanca.position.y + r_alavanca.size.y - 2, r_alavanca.size.x - 2, cor_base)

	# Face frontal sólida da manopla
	var face_manopla := Rect2i(r_alavanca.position.x + 2, r_alavanca.position.y + 2, r_alavanca.size.x - 4, r_alavanca.size.y - 4)
	ci.draw_rect(Rect2(face_manopla), cor_face)

	# 5. Empunhadura texturizada antiderrapante (Grip Ribs / ranhuras industriais)
	# 4 ranhuras horizontais em relevo
	var ranhuras_y: Array[int] = [
		face_manopla.position.y + 3,
		face_manopla.position.y + 6,
		face_manopla.position.y + 9,
		face_manopla.position.y + 12
	]

	for ry: int in ranhuras_y:
		if ry < face_manopla.position.y + face_manopla.size.y - 1:
			# Linha de sulco profundo
			linha_h(ci, face_manopla.position.x + 1, ry, face_manopla.size.x - 2, PRETO)
			# Linha de crista iluminada imediatamente acima
			linha_h(ci, face_manopla.position.x + 1, ry - 1, face_manopla.size.x - 2, METAL_CLARO)

	# 6. Ponto central indicador na ponta da chave (marca visual mecânica)
	var ponto_y: int = face_manopla.position.y + (face_manopla.size.y / 2)
	px(ci, Vector2i(face_manopla.position.x + (face_manopla.size.x / 2), ponto_y), BRANCO if pos_alavanca > 0.5 else CINZA_ESC)


## Cursor de seleção do jogador com colchetes táticos nos 4 cantos e pulso suave
static func desenhar_cursor_selecao(ci: CanvasItem, baia: Rect2i, tempo: float) -> void:
	# Pulso suave de transparência e brilho
	var onda: float = 0.5 + 0.5 * sin(tempo * 6.0)
	var cor_cursor := Color(AMARELO.r, AMARELO.g, AMARELO.b, 0.75 + 0.25 * onda)
	var cor_brilho := Color(BRANCO.r, BRANCO.g, BRANCO.b, 0.90)

	# Colchetes táticos expandidos 2px ao redor da baia
	var x0: int = baia.position.x - 2
	var y0: int = baia.position.y - 2
	var x1: int = baia.position.x + baia.size.x + 1
	var y1: int = baia.position.y + baia.size.y + 1
	var braco: int = 5 # Comprimento das pontas dos colchetes

	# Canto Superior Esquerdo ┌
	linha_h(ci, x0, y0, braco, cor_cursor)
	linha_h(ci, x0, y0 + 1, braco, cor_brilho)
	linha_v(ci, x0, y0, braco, cor_cursor)
	linha_v(ci, x0 + 1, y0, braco, cor_brilho)

	# Canto Superior Direito ┐
	linha_h(ci, x1 - braco + 1, y0, braco, cor_cursor)
	linha_h(ci, x1 - braco + 1, y0 + 1, braco, cor_brilho)
	linha_v(ci, x1, y0, braco, cor_cursor)
	linha_v(ci, x1 - 1, y0, braco, cor_brilho)

	# Canto Inferior Esquerdo └
	linha_h(ci, x0, y1, braco, cor_cursor)
	linha_h(ci, x0, y1 - 1, braco, cor_brilho)
	linha_v(ci, x0, y1 - braco + 1, braco, cor_cursor)
	linha_v(ci, x0 + 1, y1 - braco + 1, braco, cor_brilho)

	# Canto Inferior Direito ┘
	linha_h(ci, x1 - braco + 1, y1, braco, cor_cursor)
	linha_h(ci, x1 - braco + 1, y1 - 1, braco, cor_brilho)
	linha_v(ci, x1, y1 - braco + 1, braco, cor_cursor)
	linha_v(ci, x1 - 1, y1 - braco + 1, braco, cor_brilho)

	# Marcador em seta indicadora superior (▲) apontando para a baia ativa
	var topo_centro_x: int = baia.position.x + (baia.size.x / 2)
	var seta_y: int = y0 - 3
	px(ci, Vector2i(topo_centro_x, seta_y + 1), cor_cursor)
	px(ci, Vector2i(topo_centro_x - 1, seta_y), cor_cursor)
	px(ci, Vector2i(topo_centro_x, seta_y), cor_brilho)
	px(ci, Vector2i(topo_centro_x + 1, seta_y), cor_cursor)


## Traços de circuito elétrico conectando as saídas das 4 baias ao barramento geral
static func desenhar_barramento_eletrico(ci: CanvasItem) -> void:
	for i in range(4):
		var cx: int = CENTROS_X[i]
		# Linha vertical saindo da baia até a calha do barramento
		linha_v(ci, cx, BAIAS_Y + BAIAS_ALTURA + 1, 3, CINZA_ESC)
		px(ci, Vector2i(cx, BAIAS_Y + BAIAS_ALTURA + 2), METAL)

	# Barra horizontal comum de cobre/metal
	linha_h(ci, CENTROS_X[0] - 8, BAIAS_Y + BAIAS_ALTURA + 3, (CENTROS_X[3] - CENTROS_X[0]) + 16, CINZA_ESC)
	linha_h(ci, CENTROS_X[0] - 8, BAIAS_Y + BAIAS_ALTURA + 4, (CENTROS_X[3] - CENTROS_X[0]) + 16, NOITE)


## Display LCD/LED digital inferior com moldura de proteção e mensagens dinâmicas
static func desenhar_display_status(ci: CanvasItem, r: Rect2i, dados: DadosPainel) -> void:
	# Moldura externa em metal escuro
	ci.draw_rect(Rect2(r), PRETO)
	linha_h(ci, r.position.x, r.position.y, r.size.x, CINZA_ESC)
	linha_v(ci, r.position.x, r.position.y, r.size.y, CINZA_ESC)
	linha_h(ci, r.position.x, r.position.y + r.size.y - 1, r.size.x, METAL)
	linha_v(ci, r.position.x + r.size.x - 1, r.position.y, r.size.y, METAL)

	# Fundo do display tipo tela CRT militar verde/azul escura
	var tela := Rect2i(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2)
	ci.draw_rect(Rect2(tela), AZUL_NOITE)

	# Linhas de varredura sutis (scanlines 16-bit)
	for y: int in range(tela.position.y + 1, tela.position.y + tela.size.y, 2):
		linha_h(ci, tela.position.x, y, tela.size.x, Color(NOITE.r, NOITE.g, NOITE.b, 0.45))

	# Luz indicadora de status do sistema na ponta esquerda do display
	var led_status_pos := Vector2i(tela.position.x + 6, tela.position.y + (tela.size.y / 2))
	var cor_status := AMARELO
	match dados.estado:
		0: cor_status = AMARELO         # MOSTRANDO
		1: cor_status = CIANO           # JOGADOR
		2: cor_status = VERMELHO_CLARO  # ERRO
		3: cor_status = VERDE_LIMA      # CONCLUIDO

	desenhar_led_glow(ci, led_status_pos, cor_status, true, dados.tempo)

	# Montagem do texto do display de acordo com o estado do minigame
	var texto: String = ""
	var cor_texto: Color = BRANCO

	match dados.estado:
		0: # MOSTRANDO
			texto = "OBSERVE A SEQUENCIA DE REINICIALIZACAO..."
			cor_texto = AMARELO
		1: # JOGADOR
			texto = "PASSO %d/%d: ARME OS DISJUNTORES NA ORDEM" % [dados.passo_jogador + 1, dados.total_passos]
			cor_texto = BRANCO
		2: # ERRO
			texto = "FALHA DE SEQUENCIA! REINICIANDO BARRAMENTO..."
			cor_texto = VERMELHO_CLARO
		3: # CONCLUIDO
			texto = "SISTEMA RESTAURADO // BARRAMENTO 28V ONLINE!"
			cor_texto = VERDE_LIMA

	if not dados.mensagem_customizada.is_empty():
		texto = dados.mensagem_customizada

	# Renderização da tipografia centralizada no display
	Fonte.centralizado(ci, texto, tela.position.x + (tela.size.x / 2.0) + 4, tela.position.y + 5, cor_texto, 1)


## Desenha o botão [X] mecânico com relevo chanfrado no canto superior direito
static func desenhar_botao_fechar(ci: CanvasItem, r: Rect2i) -> void:
	# Moldura externa preta com chanfro
	ci.draw_rect(Rect2(r), PRETO)
	linha_h(ci, r.position.x + 1, r.position.y + 1, r.size.x - 2, CINZA_ESC)
	linha_v(ci, r.position.x + 1, r.position.y + 1, r.size.y - 2, CINZA_ESC)
	ci.draw_rect(Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2), NOITE)

	# Cruz 'X' em pixel art vermelho escuro / claro
	var bx: int = r.position.x + 2
	var by: int = r.position.y + 2
	for i in range(5):
		px(ci, Vector2i(bx + i, by + i), VERMELHO_CLARO)
		px(ci, Vector2i(bx + 4 - i, by + i), VERMELHO_CLARO)


# ==============================================================================
# PRIMITIVAS DE PIXEL ART (Coordenadas Inteiras Estritas)
# ==============================================================================

## Plota um pixel único estrito
static func px(ci: CanvasItem, p: Vector2i, cor: Color) -> void:
	ci.draw_rect(Rect2(p.x, p.y, 1, 1), cor)


## Linha horizontal de pixels contíguos com coordenadas inteiras
static func linha_h(ci: CanvasItem, x: int, y: int, comprimento: int, cor: Color) -> void:
	if comprimento > 0:
		ci.draw_rect(Rect2(x, y, comprimento, 1), cor)


## Linha vertical de pixels contíguos com coordenadas inteiras
static func linha_v(ci: CanvasItem, x: int, y: int, comprimento: int, cor: Color) -> void:
	if comprimento > 0:
		ci.draw_rect(Rect2(x, y, 1, comprimento), cor)
