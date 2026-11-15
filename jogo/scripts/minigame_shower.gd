extends Control
## Minigame "Banho / Chuveiro de Descontaminação" (SHOWER):
## O astronauta entra na cabine de descontaminação e deve ligar os jatos de ar pressurizado:
## - Atrás (S)
## - Esquerda (A)
## - Direita (D)
## - Em Cima (W)
## - Em Baixo (E)
## Ao segurar cada tecla, o ar pressurizado é acionado naquela direção e preenche
## a sub-barra correspondente na barra inferior. Quando as 5 sub-barras estiverem
## completas, a tarefa é concluída.
##
## NOTA DE DESIGN:
## Desenvolvido com formas geométricas básicas e nós separados para que a arte
## conceitual possa ser facilmente substituída por pixel art (sprites / texturas).

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")

# Cores da paleta oficial (paleta_v3.hex / Apollo)
const PRETO := Color("#090a14")
const NOITE := Color("#10141f")
const FUNDO_PAINEL := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const AZUL := Color("#4f8fba")
const CIANO := Color("#73bed3")
const CIANO_BRILHO := Color("#a4dddb")

const TOTAL_BARRAS := 5
const TEMPO_ENCHER := 1.0  # Segundos segurando a tecla para completar cada sub-barra

# Índices das sub-barras e bicos
enum Bicos { ATRAS = 0, ESQUERDA = 1, DIREITA = 2, CIMA = 3, BAIXO = 4 }

var demo := false
var progressos := [0.0, 0.0, 0.0, 0.0, 0.0]
var ativo := [false, false, false, false, false]
var acabou := false
var mensagem := ""
var tempo_anim := 0.0

# Referências aos nós visuais (fáceis de trocar por Pixel Art)
@onready var painel: ColorRect = $Painel
@onready var cabine: ColorRect = $Painel/Cabine
@onready var astronauta: ColorRect = $Painel/Cabine/Astronauta
@onready var bico_cima: ColorRect = $Painel/Cabine/BicoCima
@onready var bico_baixo: ColorRect = $Painel/Cabine/BicoBaixo
@onready var bico_atras: ColorRect = $Painel/Cabine/BicoAtras
@onready var bico_esq: ColorRect = $Painel/Cabine/BicoEsquerda
@onready var bico_dir: ColorRect = $Painel/Cabine/BicoDireita
@onready var jatos_ar: Control = $Painel/Cabine/JatosAr
@onready var barra_container: HBoxContainer = $Painel/BarraSubdividida
@onready var textos: Control = $Painel/Textos

@onready var sub_barras := [
	$Painel/BarraSubdividida/SubBarra1/Preenchimento,
	$Painel/BarraSubdividida/SubBarra2/Preenchimento,
	$Painel/BarraSubdividida/SubBarra3/Preenchimento,
	$Painel/BarraSubdividida/SubBarra4/Preenchimento,
	$Painel/BarraSubdividida/SubBarra5/Preenchimento
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	jatos_ar.draw.connect(_desenhar_jatos_ar)
	textos.draw.connect(_desenhar_textos)
	_atualizar_barras()


func _input(ev: InputEvent) -> void:
	if acabou or demo:
		return
	# Fechar no botão X ou Esc
	var botao_x := Rect2(painel.position + Vector2(painel.size.x - 14, 4), Vector2(10, 10))
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if botao_x.grow(2).has_point(get_local_mouse_position()):
			cancelou.emit()
	elif ev.is_action_pressed("ui_cancel"):
		cancelou.emit()


func _process(delta: float) -> void:
	tempo_anim += delta

	if acabou:
		jatos_ar.queue_redraw()
		textos.queue_redraw()
		return

	_processar_entradas(delta)
	_atualizar_visuais()

	# Checa se todas as 5 sub-barras foram preenchidas
	if _todas_completas():
		_terminar("DESCONTAMINACAO CONCLUIDA")

	jatos_ar.queue_redraw()
	textos.queue_redraw()


func _processar_entradas(delta: float) -> void:
	for i in TOTAL_BARRAS:
		ativo[i] = false

	if demo:
		# No modo demo, completa as sub-barras sequencialmente
		for i in TOTAL_BARRAS:
			if progressos[i] < 1.0:
				ativo[i] = true
				break
	else:
		# Teclas pressionadas pelo jogador:
		# Atrás: S ou Seta Baixo
		if Input.is_action_pressed("baixo"):
			ativo[Bicos.ATRAS] = true
		# Esquerda: A ou Seta Esquerda
		if Input.is_action_pressed("esquerda"):
			ativo[Bicos.ESQUERDA] = true
		# Direita: D ou Seta Direita
		if Input.is_action_pressed("direita"):
			ativo[Bicos.DIREITA] = true
		# Em Cima: W ou Seta Cima
		if Input.is_action_pressed("cima"):
			ativo[Bicos.CIMA] = true
		# Em Baixo: Tecla E ou Usar (ou Espaço / Enter)
		if Input.is_action_pressed("usar"):
			ativo[Bicos.BAIXO] = true

	# Preenche o progresso das sub-barras ativas
	for i in TOTAL_BARRAS:
		if ativo[i] and progressos[i] < 1.0:
			progressos[i] = minf(1.0, progressos[i] + (1.0 / TEMPO_ENCHER) * delta)


func _todas_completas() -> bool:
	for p in progressos:
		if p < 1.0:
			return false
	return true


func _atualizar_visuais() -> void:
	# Atualiza cores dos bicos de acordo com o acionamento
	bico_cima.color = CIANO_BRILHO if ativo[Bicos.CIMA] else CINZA_ESC
	bico_baixo.color = CIANO_BRILHO if ativo[Bicos.BAIXO] else CINZA_ESC
	bico_atras.color = CIANO_BRILHO if ativo[Bicos.ATRAS] else CINZA_ESC
	bico_esq.color = CIANO_BRILHO if ativo[Bicos.ESQUERDA] else CINZA_ESC
	bico_dir.color = CIANO_BRILHO if ativo[Bicos.DIREITA] else CINZA_ESC

	_atualizar_barras()


func _atualizar_barras() -> void:
	for i in TOTAL_BARRAS:
		var preenchimento: ColorRect = sub_barras[i]
		var pai: ColorRect = preenchimento.get_parent() as ColorRect
		var larg_total := pai.size.x
		preenchimento.size.x = larg_total * progressos[i]
		preenchimento.color = VERDE if progressos[i] >= 1.0 else CIANO


func _desenhar_jatos_ar() -> void:
	# Desenha linhas/fluxo de ar pressurizado quando os bicos estão ativos
	var pulso := fmod(tempo_anim * 8.0, 1.0)

	# 1. Jato Superior (Cima -> Astronauta)
	if ativo[Bicos.CIMA]:
		var y_ini := bico_cima.position.y + bico_cima.size.y
		var y_fim := astronauta.position.y
		for k in 4:
			var x := bico_cima.position.x + 3.0 + float(k) * 5.5
			var offset_y := fmod(pulso + float(k) * 0.25, 1.0) * (y_fim - y_ini)
			jatos_ar.draw_line(Vector2(x, y_ini + offset_y), Vector2(x, minf(y_fim, y_ini + offset_y + 4.0)), CIANO_BRILHO, 1.5)

	# 2. Jato Inferior / Em Baixo (Chão -> Botas/Pernas do Astronauta)
	if ativo[Bicos.BAIXO]:
		var y_ini := bico_baixo.position.y
		var y_fim := astronauta.position.y + astronauta.size.y
		for k in 4:
			var x := bico_baixo.position.x + 3.0 + float(k) * 5.5
			var offset_y := fmod(pulso + float(k) * 0.25, 1.0) * (y_ini - y_fim)
			jatos_ar.draw_line(Vector2(x, y_ini - offset_y), Vector2(x, maxf(y_fim, y_ini - offset_y - 4.0)), CIANO_BRILHO, 1.5)

	# 3. Jato Traseiro (Atrás / Costas do Astronauta)
	if ativo[Bicos.ATRAS]:
		for k in 5:
			var y := astronauta.position.y + 4.0 + float(k) * 5.5
			var x_ini := astronauta.position.x
			var offset_x := fmod(pulso + float(k) * 0.2, 1.0) * 12.0
			jatos_ar.draw_line(Vector2(x_ini - offset_x, y), Vector2(maxf(x_ini - 14.0, x_ini - offset_x - 3.0), y), CIANO_BRILHO, 1.5)
			var x_dir := astronauta.position.x + astronauta.size.x
			jatos_ar.draw_line(Vector2(x_dir + offset_x, y), Vector2(minf(x_dir + 14.0, x_dir + offset_x + 3.0), y), CIANO_BRILHO, 1.5)

	# 4. Jato Esquerdo (Esquerda -> Astronauta)
	if ativo[Bicos.ESQUERDA]:
		var x_ini := bico_esq.position.x + bico_esq.size.x
		var x_fim := astronauta.position.x
		for k in 4:
			var y := bico_esq.position.y + 3.0 + float(k) * 5.5
			var offset_x := fmod(pulso + float(k) * 0.25, 1.0) * (x_fim - x_ini)
			jatos_ar.draw_line(Vector2(x_ini + offset_x, y), Vector2(minf(x_fim, x_ini + offset_x + 4.0), y), CIANO_BRILHO, 1.5)

	# 5. Jato Direito (Direita -> Astronauta)
	if ativo[Bicos.DIREITA]:
		var x_ini := bico_dir.position.x
		var x_fim := astronauta.position.x + astronauta.size.x
		for k in 4:
			var y := bico_dir.position.y + 3.0 + float(k) * 5.5
			var offset_x := fmod(pulso + float(k) * 0.25, 1.0) * (x_ini - x_fim)
			jatos_ar.draw_line(Vector2(x_ini - offset_x, y), Vector2(maxf(x_fim, x_ini - offset_x - 4.0), y), CIANO_BRILHO, 1.5)


func _desenhar_textos() -> void:
	var cx := painel.size.x / 2.0

	# Título do Painel
	Fonte.centralizado(textos, "DESCONTAMINACAO", cx, 6, AMARELO)

	# Botão de Fechar (X)
	var bx := painel.size.x - 14.0
	var by := 5.0
	textos.draw_rect(Rect2(bx, by, 8, 8), VERMELHO)
	for k in 4:
		textos.draw_rect(Rect2(bx + 2 + k, by + 2 + k, 1, 1), BRANCO)
		textos.draw_rect(Rect2(bx + 5 - k, by + 2 + k, 1, 1), BRANCO)

	# Mensagem de Instrução / Status
	if acabou:
		Fonte.centralizado(textos, mensagem, cx, 114, VERDE)
	else:
		var completas := 0
		for p in progressos:
			if p >= 1.0:
				completas += 1

		if completas == 4 and progressos[Bicos.BAIXO] < 1.0:
			Fonte.centralizado(textos, "SEGURE [E] PARA AR EM BAIXO", cx, 114, AMARELO)
		else:
			Fonte.centralizado(textos, "SEGURE: S(ATRAS) A(ESQ) D(DIR) W(CIMA) E(BAIXO)", cx, 114, BRANCO)

	# Legendas das 5 sub-barras
	var nomes := ["S: ATRAS", "A: ESQ", "D: DIR", "W: CIMA", "E: BAIXO"]
	var bar_y := barra_container.position.y + barra_container.size.y + 3.0

	for i in TOTAL_BARRAS:
		var bar: Control = barra_container.get_child(i) as Control
		var bar_cx := barra_container.position.x + bar.position.x + bar.size.x / 2.0
		var cor_label := VERDE if progressos[i] >= 1.0 else (CIANO_BRILHO if ativo[i] else CINZA)
		Fonte.centralizado(textos, nomes[i], bar_cx, bar_y, cor_label)


func _terminar(texto: String) -> void:
	acabou = true
	mensagem = texto
	_atualizar_visuais()
	await get_tree().create_timer(0.8).timeout
	terminou.emit()


func _criar_teclas() -> void:
	var teclas := {
		"esquerda": [KEY_A, KEY_LEFT],
		"direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER, KEY_SPACE]
	}
	for acao in teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
		for k in teclas[acao]:
			var ja_tem := false
			for ev in InputMap.action_get_events(acao):
				if ev is InputEventKey and ev.physical_keycode == k:
					ja_tem = true
					break
			if not ja_tem:
				var ev_nova := InputEventKey.new()
				ev_nova.physical_keycode = k
				InputMap.action_add_event(acao, ev_nova)
