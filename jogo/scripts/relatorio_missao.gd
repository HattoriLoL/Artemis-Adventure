extends Control
## Tela de Relatório Final da Missão (Debriefing de 7 Dias da Base Artemis).
## Exibe telemetria de sobrevivência, registros da NASA DONKI, classificação final e ações de rotação.

signal reiniciou
signal fechou

const Fonte = preload("res://scripts/fonte.gd")

# Paleta oficial (Apollo / Artemis 16-32 colors)
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const LARANJA := Color("#e88b35")
const AZUL := Color("#73bed3")
const CINZA := Color("#819796")
const CINZA_ESCURO := Color("#354649")
const PRETO_FUNDO := Color("#060a0f")

# Retângulos dos botões interativos
const BOTAO_REINICIAR := Rect2(10, 156, 210, 16)
const BOTAO_SAIR := Rect2(226, 156, 84, 16)

# Estado e estatísticas da missão
var dias_sobrevividos: int = 7
var total_dias: int = 7
var tripulacao_salva: int = 4
var total_tripulacao: int = 4
var blindagem_reforcada: bool = false
var nome_local: String = "CRATERA SHACKLETON"

# Dados do clima espacial NASA DONKI
var registro_donki_id: String = "CME-2023-04-21"
var registro_donki_tipo: String = "EJECAO DE MASSA CORONAL (CME)"
var registro_donki_vel: String = "1.100 KM/S"
var registro_donki_rad: String = "NIVEL CRITICO (M1.7)"
var registro_donki_fonte: String = "NASA DONKI / SDO"

# Controle de animação e foco
var tempo_anim: float = 0.0
var cursor_visivel: bool = true
var mouse_sobre_reiniciar: bool = false
var mouse_sobre_sair: bool = false

@onready var textos: Control = $Textos


func _ready() -> void:
	textos.draw.connect(_desenhar_conteudo)
	_carregar_dados_missao()
	if textos:
		textos.queue_redraw()


func _process(delta: float) -> void:
	tempo_anim += delta
	var novo_cursor: bool = int(tempo_anim * 2.5) % 2 == 0
	if novo_cursor != cursor_visivel:
		cursor_visivel = novo_cursor
		if textos:
			textos.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				get_viewport().set_input_as_handled()
				reiniciar_partida()
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				sair()

	elif event is InputEventMouseMotion:
		var pos: Vector2 = event.position
		var sobre_reiniciar: bool = BOTAO_REINICIAR.has_point(pos)
		var sobre_sair: bool = BOTAO_SAIR.has_point(pos)
		if sobre_reiniciar != mouse_sobre_reiniciar or sobre_sair != mouse_sobre_sair:
			mouse_sobre_reiniciar = sobre_reiniciar
			mouse_sobre_sair = sobre_sair
			if textos:
				textos.queue_redraw()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		if BOTAO_REINICIAR.has_point(pos):
			get_viewport().set_input_as_handled()
			reiniciar_partida()
		elif BOTAO_SAIR.has_point(pos):
			get_viewport().set_input_as_handled()
			sair()


func _carregar_dados_missao() -> void:
	if has_node("/root/Missao"):
		var m: Node = get_node("/root/Missao")
		dias_sobrevividos = m.dia_atual
		blindagem_reforcada = m.blindagem_reforcada
		if m.dados_local.has("titulo"):
			nome_local = str(m.dados_local["titulo"]).to_upper()
		elif m.local_pouso != "":
			nome_local = m.local_pouso.to_upper()

		if not m.evento_donki_ativo.is_empty():
			var ev: Dictionary = m.evento_donki_ativo
			registro_donki_id = ev.get("id", registro_donki_id)
			registro_donki_tipo = ev.get("tipo", registro_donki_tipo)
			registro_donki_vel = ev.get("velocidade", registro_donki_vel)
			registro_donki_rad = ev.get("radiacao", registro_donki_rad)
			registro_donki_fonte = ev.get("fonte", registro_donki_fonte)


## Permite configuração manual dos parâmetros para debriefings customizados ou testes
func configurar_dados(
	p_dias: int = 7,
	p_blindagem: bool = false,
	p_tripulacao: int = 4,
	p_local: String = "CRATERA SHACKLETON",
	p_donki: Dictionary = {}
) -> void:
	dias_sobrevividos = p_dias
	blindagem_reforcada = p_blindagem
	tripulacao_salva = p_tripulacao
	nome_local = p_local.to_upper()
	if not p_donki.is_empty():
		registro_donki_id = p_donki.get("id", registro_donki_id)
		registro_donki_tipo = p_donki.get("tipo", registro_donki_tipo)
		registro_donki_vel = p_donki.get("velocidade", registro_donki_vel)
		registro_donki_rad = p_donki.get("radiacao", registro_donki_rad)
		registro_donki_fonte = p_donki.get("fonte", registro_donki_fonte)
	if is_inside_tree() and textos:
		textos.queue_redraw()


## Reinicia a partida e reinicia o ciclo na cena de escolha de pouso
func reiniciar_partida() -> void:
	reiniciou.emit()
	if has_node("/root/Missao"):
		var m: Node = get_node("/root/Missao")
		m.dia_atual = 1
		m.blindagem_reforcada = false
		m.local_pouso = ""
		m.dados_local = {}
		m.condicoes = {}
	get_tree().change_scene_to_file("res://cenas/escolha_pouso.tscn")


## Fecha o relatório ou sai da aplicação
func sair() -> void:
	fechou.emit()
	if get_parent() != get_tree().root:
		queue_free()
	else:
		get_tree().quit()


# ------------------------------------------------------------- RENDERIZACAO
func _desenhar_conteudo() -> void:
	_desenhar_cabecalho()
	_desenhar_painel_sobrevivencia()
	_desenhar_painel_clima()
	_desenhar_painel_classificacao()
	_desenhar_efeito_crt()
	_desenhar_botoes()


func _desenhar_painel(ret: Rect2, cor_fundo: Color, cor_borda: Color) -> void:
	textos.draw_rect(ret, cor_fundo)
	textos.draw_rect(Rect2(ret.position.x, ret.position.y, ret.size.x, 1), cor_borda)
	textos.draw_rect(Rect2(ret.position.x, ret.position.y + ret.size.y - 1, ret.size.x, 1), cor_borda)
	textos.draw_rect(Rect2(ret.position.x, ret.position.y, 1, ret.size.y), cor_borda)
	textos.draw_rect(Rect2(ret.position.x + ret.size.x - 1, ret.position.y, 1, ret.size.y), cor_borda)


func _desenhar_cabecalho() -> void:
	var cabecalho_ret := Rect2(8, 7, 304, 18)
	_desenhar_painel(cabecalho_ret, Color("#0e1824"), Color("#285264"))

	var titulo := "RELATORIO FINAL DA MISSAO ARTEMIS // NASA EVALUATION"
	Fonte.centralizado(textos, _sanitizar(titulo), 160, 9, AMARELO)

	var sub_esq := "DEBRIEFING OPERACIONAL // CICLO 7 DIAS"
	var sub_dir := "ESTACAO ARTEMIS III"
	Fonte.desenhar(textos, _sanitizar(sub_esq), Vector2(14, 17), AZUL)
	Fonte.desenhar(textos, _sanitizar(sub_dir), Vector2(216, 17), CINZA)


func _desenhar_painel_sobrevivencia() -> void:
	var p_esq := Rect2(10, 27, 147, 74)
	_desenhar_painel(p_esq, Color("#0c131c"), Color("#1e2f3e"))

	# Faixa de título do painel
	textos.draw_rect(Rect2(10, 27, 147, 10), Color("#142230"))
	Fonte.desenhar(textos, "1. TELEMETRIA DA BASE", Vector2(14, 29), AZUL)

	# Linhas de estatísticas
	Fonte.desenhar(textos, "DIAS SOBREVIVIDOS:", Vector2(14, 39), CINZA)
	Fonte.desenhar(textos, "%d/%d" % [dias_sobrevividos, total_dias], Vector2(98, 39), VERDE)

	Fonte.desenhar(textos, "TRIPULACAO SALVA :", Vector2(14, 47), CINZA)
	Fonte.desenhar(textos, "%d/%d" % [tripulacao_salva, total_tripulacao], Vector2(98, 47), VERDE)

	Fonte.desenhar(textos, "BLINDAGEM ABRIGO :", Vector2(14, 55), CINZA)
	if blindagem_reforcada:
		Fonte.desenhar(textos, "REFORCADA (+100 PCT)", Vector2(14, 63), VERDE)
	else:
		Fonte.desenhar(textos, "SEM REFORCO (DANOS)", Vector2(14, 63), VERMELHO)

	Fonte.desenhar(textos, "SUPORTE DE VIDA  : NOMINAL (O2/H2O)", Vector2(14, 71), BRANCO)
	Fonte.desenhar(textos, "LOCAL: " + _sanitizar(nome_local).substr(0, 18), Vector2(14, 79), AMARELO)

	# Blocos de progresso dos 7 dias
	for d in range(7):
		var bx := 14 + d * 19
		var cor_bloco: Color = VERDE if d < dias_sobrevividos else CINZA_ESCURO
		textos.draw_rect(Rect2(bx, 88, 16, 7), cor_bloco)
		Fonte.desenhar(textos, "D%d" % (d + 1), Vector2(bx + 3, 89), Color("#060a0f"))


func _desenhar_painel_clima() -> void:
	var p_dir := Rect2(163, 27, 147, 74)
	_desenhar_painel(p_dir, Color("#0c131c"), Color("#1e2f3e"))

	# Faixa de título do painel
	textos.draw_rect(Rect2(163, 27, 147, 10), Color("#142230"))
	Fonte.desenhar(textos, "2. CLIMA ESPACIAL DONKI", Vector2(167, 29), AZUL)

	# Dados do evento registrado
	Fonte.desenhar(textos, "REGISTRO:", Vector2(167, 39), CINZA)
	Fonte.desenhar(textos, _sanitizar(registro_donki_id), Vector2(212, 39), AMARELO)

	Fonte.desenhar(textos, "EVENTO  :", Vector2(167, 47), CINZA)
	Fonte.desenhar(textos, _sanitizar(registro_donki_tipo).substr(0, 16), Vector2(212, 47), BRANCO)

	Fonte.desenhar(textos, "ONDA CHOQUE:", Vector2(167, 55), CINZA)
	Fonte.desenhar(textos, _sanitizar(registro_donki_vel), Vector2(236, 55), LARANJA)

	Fonte.desenhar(textos, "RADIACAO   :", Vector2(167, 63), CINZA)
	Fonte.desenhar(textos, _sanitizar(registro_donki_rad).substr(0, 14), Vector2(236, 63), VERMELHO)

	Fonte.desenhar(textos, "IMPACTO LUNAR: SOL 4 (CONFIRMADO)", Vector2(167, 71), BRANCO)
	Fonte.desenhar(textos, "MONITORAMENTO: SDO / SOHO / GOES", Vector2(167, 79), CINZA)

	# Indicador de integração telemetria
	Fonte.desenhar(textos, "> DADOS TELEMETRIA INTEGRADOS <", Vector2(167, 89), AZUL)


func _desenhar_painel_classificacao() -> void:
	var p_status := Rect2(10, 104, 300, 48)

	if blindagem_reforcada:
		_desenhar_painel(p_status, Color("#0d1e13"), Color("#2d5a37"))
		textos.draw_rect(Rect2(10, 104, 300, 11), Color("#183824"))
		Fonte.desenhar(textos, "CLASSIFICACAO FINAL // STATUS: SUCESSO EXCEPCIONAL", Vector2(14, 106), VERDE)
		Fonte.desenhar(textos, "GRAU A+", Vector2(272, 106), AMARELO)

		Fonte.desenhar(textos, "AVALIACAO NASA: A BASE SUPORTOU A ONDA DE CHOQUE SOLAR.", Vector2(14, 118), BRANCO)
		Fonte.desenhar(textos, "BLINDAGEM REFORCADA BLOQUEOU A DOSE CRITICA DE RADIACAO.", Vector2(14, 126), VERDE)
		Fonte.desenhar(textos, "TRIPULACAO ILESA E RECURSOS ASSEGURADOS PARA PROXIMA ROTACAO.", Vector2(14, 134), AMARELO)
		Fonte.desenhar(textos, "HOMOLOGACAO: ARTEMIS BASE ASSEGURADA // RUMO A MARTE", Vector2(14, 142), AZUL)
	else:
		_desenhar_painel(p_status, Color("#1f0f0f"), Color("#5c2525"))
		textos.draw_rect(Rect2(10, 104, 300, 11), Color("#381616"))
		Fonte.desenhar(textos, "CLASSIFICACAO FINAL // STATUS: DANOS REGISTRADOS", Vector2(14, 106), VERMELHO)
		Fonte.desenhar(textos, "GRAU C", Vector2(276, 106), LARANJA)

		Fonte.desenhar(textos, "AVALIACAO NASA: A ONDA DE CHOQUE ATINGIU A BASE SEM REFORCO.", Vector2(14, 118), BRANCO)
		Fonte.desenhar(textos, "RELES ELETRICOS SOBRECARREGADOS E FISSURAS NO ABRIGO.", Vector2(14, 126), VERMELHO)
		Fonte.desenhar(textos, "TRIPULACAO SALVA POR PROTOCOLO DE EMERGENCIA // DANOS SEVEROS.", Vector2(14, 134), LARANJA)
		Fonte.desenhar(textos, "HOMOLOGACAO: REQUER REPAROS URGENTES ANTES DO PROXIMO CICLO.", Vector2(14, 142), AMARELO)


func _desenhar_efeito_crt() -> void:
	# Linhas sutis de scanline retro CRT
	for y in range(26, 153, 3):
		textos.draw_rect(Rect2(8, y, 304, 1), Color(0.0, 0.0, 0.0, 0.12))


func _desenhar_botoes() -> void:
	# Barra de fundo do rodapé
	textos.draw_rect(Rect2(8, 154, 304, 19), Color("#0a0f16"))
	textos.draw_rect(Rect2(8, 154, 304, 1), Color("#1b2b38"))

	# Botão 1: Novo Ciclo de Rotação
	var cor_fundo_reiniciar: Color = Color("#1e384d") if mouse_sobre_reiniciar else Color("#111d28")
	var cor_borda_reiniciar: Color = AMARELO if mouse_sobre_reiniciar else Color("#20384d")
	_desenhar_painel(BOTAO_REINICIAR, cor_fundo_reiniciar, cor_borda_reiniciar)

	var prompt_reinicio: String = "> (ESPACO / ENTER) NOVO CICLO DE ROTACAO" if cursor_visivel else "  (ESPACO / ENTER) NOVO CICLO DE ROTACAO"
	Fonte.desenhar(textos, prompt_reinicio, Vector2(14, 161), AMARELO if mouse_sobre_reiniciar else BRANCO)

	# Botão 2: Sair
	var cor_fundo_sair: Color = Color("#301d24") if mouse_sobre_sair else Color("#1a1622")
	var cor_borda_sair: Color = LARANJA if mouse_sobre_sair else Color("#3b2a44")
	_desenhar_painel(BOTAO_SAIR, cor_fundo_sair, cor_borda_sair)

	var prompt_sair: String = "> (ESC) SAIR" if mouse_sobre_sair else "  (ESC) SAIR"
	Fonte.desenhar(textos, prompt_sair, Vector2(236, 161), LARANJA if mouse_sobre_sair else CINZA)


func _sanitizar(t: String) -> String:
	return t.replace("[", "(").replace("]", ")").replace("%", " PCT ")
