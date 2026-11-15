extends Control
## Tela do "Computador de Navegação": Sistema Operacional da Estação Lunar (ARTEMIS-OS).
## Possui 4 janelas/abas: Clima Espacial (NASA DONKI), Diário de Bordo, Previsão 7 Dias e Setores da Base.

signal fechou

const Fonte = preload("res://scripts/fonte.gd")

const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const LARANJA := Color("#e88b35")
const AZUL := Color("#73bed3")
const CINZA := Color("#819796")
const CINZA_ESCURO := Color("#354649")
const PRETO_FUNDO := Color("#060a0f")

enum Aba {
	CLIMA = 0,
	DIARIO = 1,
	PREVISAO = 2,
	SETORES = 3
}

var aba_atual: int = Aba.CLIMA
var indice_registro_donki: int = 0
var dia_diario_selecionado: int = 1
var dia_previsao_selecionado: int = 1
var tempo_anim: float = 0.0
var led_ativo: bool = true
var mapa: Node = null

@onready var textos: Control = $Textos


func _ready() -> void:
	textos.draw.connect(_desenhar_conteudo)
	if has_node("/root/Missao"):
		var m: Node = get_node("/root/Missao")
		dia_diario_selecionado = m.dia_atual
		dia_previsao_selecionado = m.dia_atual


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_N:
				get_viewport().set_input_as_handled()
				_fechar()
			KEY_1:
				_mudar_aba(Aba.CLIMA)
			KEY_2:
				_mudar_aba(Aba.DIARIO)
			KEY_3:
				_mudar_aba(Aba.PREVISAO)
			KEY_4:
				_mudar_aba(Aba.SETORES)
			KEY_TAB, KEY_E:
				_mudar_aba((aba_atual + 1) % 4)
			KEY_Q:
				_mudar_aba((aba_atual - 1 + 4) % 4)
			KEY_UP, KEY_W:
				get_viewport().set_input_as_handled()
				if aba_atual == Aba.PREVISAO:
					dia_previsao_selecionado = maxi(1, dia_previsao_selecionado - 1)
					textos.queue_redraw()
			KEY_DOWN, KEY_S:
				get_viewport().set_input_as_handled()
				if aba_atual == Aba.PREVISAO:
					dia_previsao_selecionado = mini(7, dia_previsao_selecionado + 1)
					textos.queue_redraw()
			KEY_LEFT, KEY_A:
				get_viewport().set_input_as_handled()
				if aba_atual == Aba.DIARIO:
					dia_diario_selecionado = maxi(1, dia_diario_selecionado - 1)
					textos.queue_redraw()
				elif aba_atual == Aba.CLIMA:
					_trocar_registro_donki(-1)
				elif aba_atual == Aba.PREVISAO:
					dia_previsao_selecionado = maxi(1, dia_previsao_selecionado - 1)
					textos.queue_redraw()
			KEY_RIGHT, KEY_D:
				get_viewport().set_input_as_handled()
				if aba_atual == Aba.DIARIO:
					dia_diario_selecionado = mini(7, dia_diario_selecionado + 1)
					textos.queue_redraw()
				elif aba_atual == Aba.CLIMA:
					_trocar_registro_donki(1)
				elif aba_atual == Aba.PREVISAO:
					dia_previsao_selecionado = mini(7, dia_previsao_selecionado + 1)
					textos.queue_redraw()
			KEY_SPACE:
				get_viewport().set_input_as_handled()
				if aba_atual == Aba.CLIMA:
					_trocar_registro_donki(1)
				elif aba_atual == Aba.DIARIO:
					dia_diario_selecionado = (dia_diario_selecionado % 7) + 1
					textos.queue_redraw()
				elif aba_atual == Aba.PREVISAO:
					dia_previsao_selecionado = (dia_previsao_selecionado % 7) + 1
					textos.queue_redraw()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		# Clique nas Abas (y entre 23 e 33)
		if pos.y >= 23 and pos.y <= 33:
			if pos.x >= 20 and pos.x <= 84:
				_mudar_aba(Aba.CLIMA)
			elif pos.x >= 86 and pos.x <= 154:
				_mudar_aba(Aba.DIARIO)
			elif pos.x >= 156 and pos.x <= 226:
				_mudar_aba(Aba.PREVISAO)
			elif pos.x >= 228 and pos.x <= 298:
				_mudar_aba(Aba.SETORES)
		# Botão de Fechar no canto superior direito [X] (pos: 288, 14 a 22)
		elif pos.y >= 13 and pos.y <= 22 and pos.x >= 284 and pos.x <= 300:
			_fechar()
		# Clique nos seletores do Diário
		elif aba_atual == Aba.DIARIO and pos.y >= 38 and pos.y <= 52:
			if pos.x >= 20 and pos.x <= 110:
				dia_diario_selecionado = maxi(1, dia_diario_selecionado - 1)
				textos.queue_redraw()
			elif pos.x >= 200 and pos.x <= 298:
				dia_diario_selecionado = mini(7, dia_diario_selecionado + 1)
				textos.queue_redraw()
		# Clique para trocar registro da NASA DONKI
		elif aba_atual == Aba.CLIMA and pos.y >= 134 and pos.y <= 146:
			if pos.x >= 20 and pos.x <= 220:
				_trocar_registro_donki(1)
		# Clique nas linhas da Previsão (y de 47 a 110)
		elif aba_atual == Aba.PREVISAO and pos.x >= 20 and pos.x <= 300:
			if pos.y >= 47 and pos.y < 110:
				var linha_idx: int = int((pos.y - 47) / 9.0) + 1
				dia_previsao_selecionado = clampi(linha_idx, 1, 7)
				textos.queue_redraw()


func _mudar_aba(nova_aba: int) -> void:
	get_viewport().set_input_as_handled()
	aba_atual = nova_aba
	textos.queue_redraw()


func _trocar_registro_donki(delta_idx: int) -> void:
	var m: Node = get_node_or_null("/root/Missao")
	if m and not m.eventos_donki.is_empty():
		var total: int = m.eventos_donki.size()
		indice_registro_donki = (indice_registro_donki + delta_idx + total) % total
	textos.queue_redraw()


func _process(delta: float) -> void:
	tempo_anim += delta
	if tempo_anim >= 0.4:
		tempo_anim = 0.0
		led_ativo = not led_ativo
		textos.queue_redraw()


func _desenhar_conteudo() -> void:
	var m: Node = get_node_or_null("/root/Missao")
	var dia_missao: int = m.dia_atual if m else 1
	var status_clima: Dictionary = m.obter_status_clima() if m else {
		"titulo": "SOL ESTAVEL",
		"risco": "BAIXO",
		"cor": VERDE,
		"vento_solar": "340 KM/S",
		"resumo": "SEM ERUPCOES.",
		"detalhes": "FLUXO DE RAIOS-X EM NIVEL BASAL."
	}

	# 1. Barra de Título Superior da Estação (ARTEMIS-OS)
	textos.draw_rect(Rect2(16, 12, 288, 12), Color("#0e151f"))
	Fonte.desenhar(textos, "ARTEMIS-OS v2.4", Vector2(20, 15), AMARELO)
	Fonte.desenhar(textos, "SHACKLETON BASE // SOL %d/7" % dia_missao, Vector2(100, 15), BRANCO)

	# LED indicador de alerta solar
	var cor_led: Color = status_clima.get("cor", VERDE)
	if not led_ativo and cor_led == VERMELHO:
		cor_led = Color(0.2, 0.05, 0.05)
	textos.draw_rect(Rect2(272, 16, 4, 4), cor_led)
	Fonte.desenhar(textos, "[X]", Vector2(288, 15), CINZA)

	# 2. Barra de Abas (Janelas)
	textos.draw_rect(Rect2(16, 24, 288, 11), Color("#131c26"))
	_desenhar_aba_botao(Aba.CLIMA, "1:CLIMA DONKI", Rect2(18, 24, 66, 10))
	_desenhar_aba_botao(Aba.DIARIO, "2:DIARIO BORDO", Rect2(86, 24, 68, 10))
	_desenhar_aba_botao(Aba.PREVISAO, "3:PREVISAO 7D", Rect2(156, 24, 68, 10))
	_desenhar_aba_botao(Aba.SETORES, "4:SETORES BASE", Rect2(226, 24, 72, 10))

	# Linha separadora ciano
	textos.draw_rect(Rect2(16, 35, 288, 1), Color("#285264"))

	# 3. Conteúdo da Janela Ativa
	match aba_atual:
		Aba.CLIMA:
			_desenhar_janela_clima(m, status_clima)
		Aba.DIARIO:
			_desenhar_janela_diario(m)
		Aba.PREVISAO:
			_desenhar_janela_previsao(dia_missao)
		Aba.SETORES:
			_desenhar_janela_setores(m)

	# 4. Efeito CRT: scanlines sutis semi-transparentes
	for y in range(36, 155, 3):
		textos.draw_rect(Rect2(16, y, 288, 1), Color(0.0, 0.0, 0.0, 0.12))

	# 5. Barra de Rodapé do Terminal
	textos.draw_rect(Rect2(16, 155, 288, 13), Color("#0a0f16"))
	textos.draw_rect(Rect2(16, 155, 288, 1), Color("#1b2b38"))
	var info_rodape: String = "[1-4 / TAB] MUDAR JANELA  |  [N / ESC] FECHAR SISTEMA"
	Fonte.desenhar(textos, info_rodape, Vector2(22, 158), CINZA)


func _desenhar_aba_botao(aba: int, rotulo: String, ret: Rect2) -> void:
	var ativa: bool = (aba_atual == aba)
	if ativa:
		textos.draw_rect(ret, Color("#1f3342"))
		textos.draw_rect(Rect2(ret.position.x, ret.position.y + ret.size.y - 1, ret.size.x, 1), AMARELO)
		Fonte.desenhar(textos, rotulo, ret.position + Vector2(3, 2), AMARELO)
	else:
		textos.draw_rect(ret, Color("#0d141d"))
		Fonte.desenhar(textos, rotulo, ret.position + Vector2(3, 2), CINZA)


# ------------------------------------------------------------- JANELA 1: CLIMA DONKI
func _desenhar_janela_clima(m: Node, status: Dictionary) -> void:
	# 1. Caixa de Status Atual compacta e elegante (y=38 a y=64)
	var cor_status: Color = status.get("cor", VERDE)
	textos.draw_rect(Rect2(20, 38, 280, 26), Color("#0d1622"))
	textos.draw_rect(Rect2(20, 38, 3, 26), cor_status)
	textos.draw_rect(Rect2(20, 38, 280, 1), Color("#182635"))
	textos.draw_rect(Rect2(20, 63, 280, 1), Color("#182635"))

	# Linha 1 (y=41)
	Fonte.desenhar(textos, "STATUS: " + str(status.get("titulo", "")), Vector2(26, 41), cor_status)
	Fonte.desenhar(textos, "VENTO: " + str(status.get("vento_solar", "")), Vector2(190, 41), BRANCO)

	# Linha 2 (y=49)
	Fonte.desenhar(textos, "RISCO: " + str(status.get("risco", "")), Vector2(26, 49), cor_status)
	Fonte.desenhar(textos, "REDE NASA DONKI / SDO", Vector2(175, 49), CINZA)

	# Linha 3 (y=57)
	Fonte.desenhar(textos, "FASE: " + str(status.get("resumo", "")), Vector2(26, 57), BRANCO)

	# 2. Título da Caixa de Registro da NASA (y=66)
	Fonte.desenhar(textos, "REGISTRO HISTORICO SELECIONADO (NASA DONKI):", Vector2(22, 66), AMARELO)

	# Dados do Evento Histórico da NASA
	var lista_donki: Array = m.eventos_donki if (m and not m.eventos_donki.is_empty()) else []
	var ev: Dictionary = {}
	if not lista_donki.is_empty():
		ev = lista_donki[indice_registro_donki % lista_donki.size()]
	else:
		ev = {
			"id": "CME-2023-04-21",
			"tipo": "EJICAO DE MASSA CORONAL (CME)",
			"fonte": "NASA GODDARD CCMC / SOHO",
			"data_real": "21/04/2023 - 18:12 UTC",
			"velocidade": "1.100 KM/S",
			"radiacao": "NIVEL CRITICO (CLASSE M1.7)",
			"tempo_impacto": "DIA 4 (JANELA 24-36H)",
			"descricao": "ONDA DE CHOQUE DE PLASMA SOLAR DETECTADA PELO OBSERVATORIO SDO.",
			"acao": "RECOLHA A EQUIPE AO ABRIGO OU REFORCE A BLINDAGEM!"
		}

	# 3. Caixa de Registro da NASA bem distribuída (y=72 a y=120)
	textos.draw_rect(Rect2(20, 72, 280, 48), Color("#080f18"))
	textos.draw_rect(Rect2(20, 72, 3, 48), AMARELO)
	textos.draw_rect(Rect2(20, 72, 280, 1), Color("#182635"))
	textos.draw_rect(Rect2(20, 119, 280, 1), Color("#182635"))

	# Distribuição interna confortável (passo de 11px: y=76, 87, 98, 109)
	Fonte.desenhar(textos, "ID: " + str(ev.get("id", "")), Vector2(26, 76), BRANCO)
	Fonte.desenhar(textos, "FONTE: " + str(ev.get("fonte", "")), Vector2(130, 76), CINZA)

	Fonte.desenhar(textos, "TIPO: " + str(ev.get("tipo", "")), Vector2(26, 87), AMARELO)

	Fonte.desenhar(textos, "VELOCIDADE: " + str(ev.get("velocidade", "")), Vector2(26, 98), BRANCO)
	Fonte.desenhar(textos, "PREVISAO: " + str(ev.get("tempo_impacto", "")), Vector2(140, 98), AZUL)

	Fonte.desenhar(textos, "RADIACAO: " + str(ev.get("radiacao", "")), Vector2(26, 109), LARANJA)

	# 4. Diretriz operacional clara em y=126
	var acao_limpa: String = str(ev.get("acao", "")).trim_prefix("ACAO: ").strip_edges()
	textos.draw_rect(Rect2(20, 124, 280, 11), Color(0.04, 0.12, 0.08, 0.6))
	textos.draw_rect(Rect2(20, 124, 3, 11), VERDE)
	textos.draw_rect(Rect2(20, 124, 280, 1), Color("#133022"))
	textos.draw_rect(Rect2(20, 134, 280, 1), Color("#133022"))
	Fonte.desenhar(textos, "DIRETRIZ: " + acao_limpa, Vector2(26, 126), VERDE)

	# 5. Instrução de troca "[ESPACO] TROCAR REGISTRO DA NASA (X/Y)" em y=138
	var qtd: int = lista_donki.size() if not lista_donki.is_empty() else 1
	var nav_txt: String = "[ESPACO] TROCAR REGISTRO DA NASA (%d/%d)" % [indice_registro_donki + 1, qtd]
	Fonte.desenhar(textos, nav_txt, Vector2(22, 138), AMARELO)


# ------------------------------------------------------------- JANELA 2: DIÁRIO DE BORDO
func _desenhar_janela_diario(m: Node) -> void:
	var y: float = 38.0

	# 1. Seletor de dia: [<- A] SOL X DE 7 [D ->]
	textos.draw_rect(Rect2(20, y, 280, 14), Color("#0e1722"))
	Fonte.desenhar(textos, "[<- A] DIA ANTERIOR", Vector2(24, y + 3), AMARELO if dia_diario_selecionado > 1 else CINZA_ESCURO)
	var txt_centro: String = "SOL %d DE 7" % dia_diario_selecionado
	Fonte.centralizado(textos, txt_centro, 160, y + 3, BRANCO)
	Fonte.desenhar(textos, "PROXIMO DIA [D ->]", Vector2(212, y + 3), AMARELO if dia_diario_selecionado < 7 else CINZA_ESCURO)

	y += 17.0 # y = 55.0
	var entrada: Dictionary = {}
	if m and m.has_method("obter_entrada_diario"):
		entrada = m.obter_entrada_diario(dia_diario_selecionado)
	elif m and m.diario_entradas and m.diario_entradas.has(dia_diario_selecionado):
		entrada = m.diario_entradas[dia_diario_selecionado]
	else:
		entrada = {
			"titulo": "SOL %d: REGISTRO DE TELEMETRIA" % dia_diario_selecionado,
			"autor": "CMD. LUNA / ARTEMIS BASE",
			"texto": "SISTEMAS OPERACIONAIS EM ROTINA.",
			"estado": "concluido"
		}

	var estado: String = entrada.get("estado", "concluido")
	var cor_titulo: Color = AMARELO
	var cor_badge: Color = VERDE
	var texto_badge: String = "[CONCLUIDO]"

	match estado:
		"ativo":
			cor_titulo = AMARELO
			cor_badge = AMARELO
			texto_badge = "[TURNO EM ANDAMENTO]"
		"bloqueado":
			cor_titulo = LARANJA
			cor_badge = CINZA
			texto_badge = "[FUTURO // BLOQUEADO]"
		_:
			cor_titulo = VERDE
			cor_badge = VERDE
			texto_badge = "[REGISTRO FINALIZADO]"

	# Linha 1: Título completo do Sol
	Fonte.desenhar(textos, str(entrada.get("titulo", "")), Vector2(22, y), cor_titulo)

	y += 8.0 # y = 63.0
	# Linha 2: Autor à esquerda e Tag de status à direita
	Fonte.desenhar(textos, "REGISTRO: " + str(entrada.get("autor", "")), Vector2(22, y), CINZA)
	Fonte.desenhar(textos, texto_badge, Vector2(178, y), cor_badge)

	y += 8.0 # y = 71.0
	# Caixa de texto do Diário (altura 72 px, de y=71 a y=143)
	textos.draw_rect(Rect2(20, y, 280, 72), Color("#070d14"))
	textos.draw_rect(Rect2(20, y, 280, 1), Color("#172635"))

	var linhas: Array[String] = _quebrar_texto(str(entrada.get("texto", "")), 58)
	var ly: float = y + 5.0 # ly começa em 76.0
	for l in linhas:
		if ly > 136.0:
			break
		Fonte.desenhar(textos, l, Vector2(24, ly), BRANCO)
		ly += 9.0

	# Linha de instrução de navegação em y=146
	Fonte.desenhar(textos, "[A/D ou SETAS] NAVEGAR ENTRADAS DO DIARIO", Vector2(22, 146), CINZA)


# ------------------------------------------------------------- JANELA 3: PREVISÃO 7 DIAS
func _desenhar_janela_previsao(dia_atual: int) -> void:
	var y: float = 37.0
	Fonte.desenhar(textos, "CRONOGRAMA DO CICLO DE 7 DIAS // MODELO ENLIL / DONKI", Vector2(22, y), AZUL)

	var cronograma := [
		{
			"dia": 1,
			"fase": "SOL 1: ESTAVEL",
			"risco": "BAIXO",
			"barra": 2,
			"cor": VERDE,
			"obs": "VENTO 340 KM/S",
			"titulo": "SOL 1: POUSO E ATIVACAO",
			"vento": "340 KM/S",
			"diretriz": "ROTINA NOMINAL. MONITORAR OBSERVATORIO SDO.",
			"detalhe": "FLUXO DE RAIOS-X EM NIVEL BASAL. SEM AMEACAS."
		},
		{
			"dia": 2,
			"fase": "SOL 2: REG. ATIVA",
			"risco": "MODERADO",
			"barra": 4,
			"cor": AMARELO,
			"obs": "REGIAO ATIVA",
			"titulo": "SOL 2: REGIAO AR-13283",
			"vento": "415 KM/S",
			"diretriz": "MANTER TELEMETRIA EM ALERTA E CHECAR BATERIAS.",
			"detalhe": "MANCHA SOLAR ATIVA EM ROTACAO ALINHADA A LUA."
		},
		{
			"dia": 3,
			"fase": "SOL 3: CME DETECTADA",
			"risco": "ELEVADO",
			"barra": 7,
			"cor": LARANJA,
			"obs": "CME 1.100 KM/S",
			"titulo": "SOL 3: ALERTA CME (24H)",
			"vento": "1.100 KM/S",
			"diretriz": "REFORCAR A BLINDAGEM DO ABRIGO COM REGOLITO!",
			"detalhe": "ONDA DE CHOQUE DE PLASMA EM TRANSITO PARA A LUA."
		},
		{
			"dia": 4,
			"fase": "SOL 4: IMPACTO CME",
			"risco": "CRITICO",
			"barra": 10,
			"cor": VERMELHO,
			"obs": "IMPACTO ABRIGO!",
			"titulo": "SOL 4: TEMPESTADE PROTONS",
			"vento": "1.280 KM/S",
			"diretriz": "ABRIGO OBRIGATORIO! TRANCAR EQUIPE NO MODULO.",
			"detalhe": "PARTICULAS ENERGETICAS ATINGEM A SUPERFICIE."
		},
		{
			"dia": 5,
			"fase": "SOL 5: RECUPERACAO",
			"risco": "MODERADO",
			"barra": 5,
			"cor": AMARELO,
			"obs": "LIMPAR PAINEIS",
			"titulo": "SOL 5: RESCALDO // POEIRA",
			"vento": "560 KM/S",
			"diretriz": "LIMPAR PAINEIS SOLARES E RECALIBRAR BATERIAS.",
			"detalhe": "PICO PASSOU. POEIRA IONIZADA AFETA GERACAO."
		},
		{
			"dia": 6,
			"fase": "SOL 6: ESTABILIZADO",
			"risco": "BAIXO",
			"barra": 2,
			"cor": VERDE,
			"obs": "SISTEMAS OK",
			"titulo": "SOL 6: SISTEMAS NOMINAIS",
			"vento": "370 KM/S",
			"diretriz": "NORMALIZAR ROTINAS E SUPORTE DE VIDA 100%.",
			"detalhe": "NIVEL DE RADIACAO NORMAL. CULTIVO NA ESTUFA OK."
		},
		{
			"dia": 7,
			"fase": "SOL 7: CONCLUIDO",
			"risco": "MINIMO",
			"barra": 1,
			"cor": AZUL,
			"obs": "MISSAO SALVA",
			"titulo": "SOL 7: CONCLUSAO MISSAO",
			"vento": "350 KM/S",
			"diretriz": "TRANSMITIR DADOS CIENTIFICOS AO GODDARD / NASA.",
			"detalhe": "BASE ARTEMIS HOMOLOGADA PARA PROXIMA ROTACAO."
		}
	]

	dia_previsao_selecionado = clampi(dia_previsao_selecionado, 1, 7)

	# Tabela dos 7 Dias (linhas compactas y=47 a y=109)
	y = 47.0
	for item in cronograma:
		var d: int = int(item["dia"])
		var eh_sel: bool = (d == dia_previsao_selecionado)
		var eh_hoje: bool = (d == dia_atual)

		var bg_col: Color = Color("#182937") if eh_sel else (Color("#101822") if eh_hoje else Color("#080e15"))
		textos.draw_rect(Rect2(20, y, 280, 8), bg_col)

		if eh_sel:
			textos.draw_rect(Rect2(20, y, 2, 8), AMARELO)
			Fonte.desenhar(textos, ">", Vector2(23, y + 2), AMARELO)
		elif eh_hoje:
			textos.draw_rect(Rect2(20, y, 2, 8), AZUL)
			Fonte.desenhar(textos, "*", Vector2(23, y + 2), AZUL)

		# Coluna 1: Dia e Fase (x=28 a x=110)
		var cor_col1: Color = AMARELO if eh_sel else (AZUL if eh_hoje else BRANCO)
		Fonte.desenhar(textos, str(item["fase"]), Vector2(28, y + 2), cor_col1)

		# Coluna 2: Barra visual de risco (x=115 a x=155)
		var bx: float = 115.0
		var num_barras: int = int(item["barra"])
		var cor_b: Color = item["cor"]
		for b in range(10):
			var b_cor: Color = cor_b if b < num_barras else Color("#141d24")
			textos.draw_rect(Rect2(bx + b * 4, y + 2, 3, 5), b_cor)

		# Coluna 3: Grau de Risco (x=160 a x=200)
		Fonte.desenhar(textos, str(item["risco"]), Vector2(160, y + 2), cor_b)

		# Coluna 4: Observação Curta (x=205 a x=295)
		Fonte.desenhar(textos, str(item["obs"]), Vector2(205, y + 2), BRANCO if eh_sel else CINZA)

		y += 9.0

	# Painel de Detalhe Expandido do Dia Selecionado (y=112 a y=146)
	var sel_item: Dictionary = cronograma[dia_previsao_selecionado - 1]
	var cor_sel: Color = sel_item["cor"]
	textos.draw_rect(Rect2(20, 112, 280, 34), Color("#091119"))
	textos.draw_rect(Rect2(20, 112, 280, 1), Color("#1b2f42"))
	textos.draw_rect(Rect2(20, 112, 2, 34), cor_sel)

	# Linha 1 de detalhe (y=115)
	Fonte.desenhar(textos, str(sel_item["titulo"]), Vector2(25, 115), AMARELO)
	if dia_previsao_selecionado == dia_atual:
		Fonte.desenhar(textos, "[HOJE]", Vector2(150, 115), AZUL)
	Fonte.desenhar(textos, "VENTO: " + str(sel_item["vento"]), Vector2(184, 115), BRANCO)

	# Linha 2 de detalhe (y=124)
	Fonte.desenhar(textos, "DIRETRIZ: " + str(sel_item["diretriz"]), Vector2(25, 124), cor_sel)

	# Linha 3 de detalhe (y=134)
	Fonte.desenhar(textos, "STATUS: " + str(sel_item["detalhe"]), Vector2(25, 134), CINZA)

	# Rodapé de navegação da janela (y=148)
	Fonte.desenhar(textos, "[W/S ou CIMA/BAIXO] SELECIONAR SOL  |  HOJE: SOL %d" % dia_atual, Vector2(22, 148), CINZA)


# ------------------------------------------------------------- JANELA 4: SETORES BASE
func _obter_tarefas_feitas() -> Dictionary:
	if mapa and "feitas" in mapa and mapa.feitas is Dictionary:
		return mapa.feitas
	var p: Node = get_parent()
	while p:
		if "feitas" in p and p.feitas is Dictionary:
			return p.feitas
		p = p.get_parent()
	if is_inside_tree() and get_tree().current_scene:
		var cena: Node = get_tree().current_scene
		if "feitas" in cena and cena.feitas is Dictionary:
			return cena.feitas
	return {}


func _desenhar_janela_setores(m: Node) -> void:
	var y: float = 37.0
	Fonte.desenhar(textos, "DIAGNOSTICO DOS MODULOS DA BASE ARTEMIS", Vector2(22, y), AZUL)

	var feitas: Dictionary = _obter_tarefas_feitas()

	# 1. ABRIGO BLINDADO
	var abrigo_reforcado: bool = (m != null and m.blindagem_reforcada) or feitas.has("abrigo/blindagem")
	var status_abrigo: String = "REFORCADO (100% BLINDAGEM - SEGURO)" if abrigo_reforcado else "VULNERAVEL (0% - ALTO RISCO DE RADIACAO)"
	var cor_abrigo: Color = VERDE if abrigo_reforcado else VERMELHO

	# 2. REDE DE ENERGIA (calculado com base nas tarefas de energia: paineis, baterias, distribuicao)
	var tarefas_energia := ["energia/paineis", "energia/baterias", "energia/distribuicao"]
	var energia_feitas: int = 0
	for t in tarefas_energia:
		if feitas.has(t):
			energia_feitas += 1
	var pct_energia: int = mini(100, 60 + energia_feitas * 15) if energia_feitas > 0 else 60
	var status_energia: String
	var cor_energia: Color
	if energia_feitas == 0:
		status_energia = "REQUER MANUTENCAO (60%)"
		cor_energia = AMARELO
	elif pct_energia >= 90:
		status_energia = "OPERACIONAL (%d%%)" % pct_energia
		cor_energia = VERDE
	else:
		status_energia = "OPERACIONAL (%d%%)" % pct_energia
		cor_energia = AMARELO

	# 3. SUPORTE DE VIDA
	var suporte_ok: bool = feitas.has("suporte/oxigenio") or feitas.has("suporte/gas")
	var status_suporte: String = "NOMINAL (O2: 21.2% | CO2: 0.04%)" if suporte_ok else "ATENCAO (O2: 19.8% | REQUER PURIFICACAO)"
	var cor_suporte: Color = VERDE if suporte_ok else AMARELO

	# 4. ESTUFA HIDROPONICA
	var estufa_ok: bool = feitas.has("estufa/regar")
	var status_estufa: String = "IRRIGADA (BIOMASSA 100%)" if estufa_ok else "SOLO SECO (REQUER IRRIGACAO)"
	var cor_estufa: Color = VERDE if estufa_ok else AMARELO

	# 5. MODULO HABITAT
	var habitat_ok: bool = feitas.has("habitat/agua") or feitas.has("habitat/refeicao")
	var status_habitat: String = "ABASTECIDO (TRIPULACAO NUTRIDA)" if habitat_ok else "SUPRIMENTOS PENDENTES (AGUA BAIXA)"
	var cor_habitat: Color = VERDE if habitat_ok else AMARELO

	var modulos := [
		{
			"nome": "ABRIGO BLINDADO",
			"status": status_abrigo,
			"cor": cor_abrigo,
			"desc": "PROTECAO DE REGOLITO CONTRA RADIACAO DA CME."
		},
		{
			"nome": "REDE DE ENERGIA",
			"status": status_energia,
			"cor": cor_energia,
			"desc": "BANCO DE BATERIAS E MATRIZ DE PAINEIS SOLARES."
		},
		{
			"nome": "SUPORTE DE VIDA",
			"status": status_suporte,
			"cor": cor_suporte,
			"desc": "PURIFICACAO DE AR, PRESSURIZACAO E FILTROS DE CO2."
		},
		{
			"nome": "ESTUFA HIDROPONICA",
			"status": status_estufa,
			"cor": cor_estufa,
			"desc": "CULTIVO DE BIOMASSA E HORTA LUNAR PARA ALIMENTO."
		},
		{
			"nome": "MODULO HABITAT",
			"status": status_habitat,
			"cor": cor_habitat,
			"desc": "ACOMODACOES, PREPARO DE REFEICOES E LEITOS."
		}
	]

	# Distribuição vertical com espaçamento de 18 px (5 módulos terminam em y=134)
	y = 46.0
	for mod in modulos:
		textos.draw_rect(Rect2(20, y, 280, 16), Color("#0a111a"))
		Fonte.desenhar(textos, str(mod["nome"]), Vector2(24, y + 2), AMARELO)
		Fonte.desenhar(textos, str(mod["status"]), Vector2(110, y + 2), mod["cor"])
		Fonte.desenhar(textos, str(mod["desc"]), Vector2(24, y + 9), CINZA)
		y += 18.0

	# Linha de status/dica em y=143 (com margem limpa antes do rodapé em y=155)
	if abrigo_reforcado:
		Fonte.desenhar(textos, "STATUS: ABRIGO REFORCADO // BASE PROTEGIDA CONTRA A CME", Vector2(22, 143), VERDE)
	else:
		Fonte.desenhar(textos, "DICA: REFORCE A BLINDAGEM NO ABRIGO ANTES DO DIA 4!", Vector2(22, 143), AMARELO)


# ------------------------------------------------------------- UTILITÁRIOS
func _quebrar_texto(texto: String, max_colunas: int) -> Array[String]:
	var palavras := texto.split(" ")
	var linhas: Array[String] = []
	var linha_atual := ""
	for p in palavras:
		if linha_atual == "":
			linha_atual = p
		elif linha_atual.length() + 1 + p.length() <= max_colunas:
			linha_atual += " " + p
		else:
			linhas.append(linha_atual)
			linha_atual = p
	if linha_atual != "":
		linhas.append(linha_atual)
	return linhas


func _fechar() -> void:
	fechou.emit()
	queue_free()
