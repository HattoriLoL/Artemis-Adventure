class_name MinigameBlindagem
extends Control
## Minigame "Reforçar Blindagem do Abrigo Lunar" (Bulkhead Radiation & Debris Shielding).
## O jogador deve manusear e fixar 3 placas científicas nos setores vulneráveis da antepara:
##   - Placa 0: Rególito Sinterizado (Baia 1: 60, 56)
##   - Placa 1: Liga Titânio-Alumínio (Baia 2: 140, 78)
##   - Placa 2: Polietileno Borado / Kevlar (Baia 3: 220, 56)
##
## Contrato de integração com mapa.gd:
##   - Sinais: `terminou`, `falhou`, `cancelou`
##   - Métodos: `comecou() -> bool`, `taxa_erro() -> float`
##   - Propriedades: `demo: bool`, `modo_emergencia: String`, `tempo_restante_emergencia: float`

signal terminou
signal falhou
signal cancelou

const Graficos = preload("res://scripts/minigame_blindagem_graficos.gd")
const Audio = preload("res://scripts/minigame_blindagem_audio.gd")

enum Estado {
	INTRO,
	POSICIONANDO,
	PARAFUSANDO,
	FIXADA,
	CONCLUIDO,
	FALHA
}

# Constantes de mecânica e jogabilidade
const VELOCIDADE: float = 95.0 # pixels por segundo (movimentação no teclado)
const DISTANCIA_SNAP: float = 8.0 # tolerância máxima para captura magnética
const MAX_ERROS: int = 4 # limite de erros permitidos antes da falha total
const DURACAO_PARAFUSO: float = 1.3 # tempo em segundos para fixar os 4 parafusos de uma placa

# Posições de surgimento de cada placa (bancada/chassi)
const POSICOES_INICIAIS: Array[Vector2] = [
	Vector2(140.0, 110.0), # Placa 0 surge no centro inferior
	Vector2(60.0, 110.0),  # Placa 1 surge à esquerda inferior
	Vector2(140.0, 110.0)  # Placa 2 surge no centro inferior
]

# Máquina de estados
var estado: Estado = Estado.INTRO
var tempo_estado: float = 0.0

# Gestão das 3 placas
var placa_atual: int = 0
var placas_fixadas: Array[bool] = [false, false, false]
var pos_cursor: Vector2 = Vector2(140.0, 110.0)
var alinhado: bool = false
var progresso_parafuso: float = 0.0
var tempo_parafuso: float = 0.0
var ultimo_parafuso_audio: int = -1

# Controle de entrada (Teclado e Mouse)
var arrastando_mouse: bool = false
var offset_arrasto: Vector2 = Vector2.ZERO
var hover_x: bool = false
var e_liberado: bool = false

# Contrato de métricas com mapa.gd
var demo: bool = false
var interagiu: bool = false
var erros_cometidos: int = 0
var acabou: bool = false
var finalizado: bool = false # Idempotência de encerramento

# Mensagens e alertas no HUD
var mensagem: String = ""
var mensagem_erro: String = ""
var tempo_mensagem_erro: float = 0.0

# Suporte ao modo de emergência (ex: Tempestade Solar / Chuva de Meteoros)
var modo_emergencia: String = ""
var tempo_restante_emergencia: float = 0.0
var tempo_alarme_emergencia: float = 0.0

# Instâncias dos módulos auxiliares
var graficos: GraficosBlindagem = null
var audio: AudioBlindagem = null

@onready var painel: Control = $Painel


func _ready() -> void:
	_criar_teclas()
	_inicializar_modulos()
	_iniciar_minigame()


func _inicializar_modulos() -> void:
	graficos = GraficosBlindagem.new()
	audio = AudioBlindagem.new()
	audio.name = "AudioBlindagem"
	add_child(audio)
	painel.draw.connect(_desenhar_conteudo)


func _iniciar_minigame() -> void:
	placa_atual = 0
	placas_fixadas = [false, false, false]
	pos_cursor = POSICOES_INICIAIS[0]
	alinhado = false
	progresso_parafuso = 0.0
	erros_cometidos = 0
	acabou = false
	finalizado = false
	interagiu = false
	estado = Estado.INTRO
	tempo_estado = 0.7
	mensagem = "ANALISANDO ANTEPARA ESTRUTURAL..."


func _unhandled_input(event: InputEvent) -> void:
	if finalizado:
		return

	# Tecla ESC: Cancelar ou fechar
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancelar()
			get_viewport().set_input_as_handled()
			return

	# Movimentação e interação com mouse
	if event is InputEventMouseMotion:
		var mpos: Vector2 = event.position
		hover_x = GraficosBlindagem.BOTAO_X.grow(2.0).has_point(mpos)
		if arrastando_mouse and estado == Estado.POSICIONANDO and not demo:
			pos_cursor = mpos - offset_arrasto
			_limitar_posicao_cursor()
			interagiu = true
			if audio != null:
				audio.tocar_servo()

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var mpos: Vector2 = mb.position
			if mb.pressed:
				# Botão [X] no topo direito
				if GraficosBlindagem.BOTAO_X.grow(2.0).has_point(mpos):
					_cancelar()
					get_viewport().set_input_as_handled()
					return

				# Interação com a placa da vez
				if estado == Estado.POSICIONANDO and not demo:
					var rect_placa := Rect2(pos_cursor, Vector2(GraficosBlindagem.TAMANHO_PLACA, GraficosBlindagem.TAMANHO_PLACA))
					if rect_placa.grow(6.0).has_point(mpos):
						arrastando_mouse = true
						offset_arrasto = mpos - pos_cursor
						interagiu = true
						if alinhado:
							_tentar_fixar()
					else:
						# Clique no alvo ou chassi
						var baia_alvo: Rect2 = GraficosBlindagem.BAIAS[placa_atual]
						if baia_alvo.grow(8.0).has_point(mpos):
							_tentar_fixar()
						else:
							# Clique longe com a intenção errônea de montagem
							_cometer_erro("DESALINHADO: ENCAIXE A PLACA NA BAIA")
			else:
				# Soltou botão esquerdo do mouse
				if arrastando_mouse:
					arrastando_mouse = false
					if audio != null:
						audio.parar_servo()
					if alinhado:
						_tentar_fixar()


func _process(delta: float) -> void:
	if finalizado:
		return

	# Liberação da tecla de ação para evitar disparo residual ao abrir
	if not e_liberado:
		if not Input.is_action_pressed("usar"):
			e_liberado = true

	# Gestão de contagem regressiva em modo de emergência
	_processar_emergencia(delta)

	# Atualização do temporizador de mensagem de erro
	if tempo_mensagem_erro > 0.0:
		tempo_mensagem_erro = maxf(0.0, tempo_mensagem_erro - delta)

	# Atualização da máquina de estados
	match estado:
		Estado.INTRO:
			tempo_estado -= delta
			if tempo_estado <= 0.0:
				estado = Estado.POSICIONANDO
				mensagem = ""

		Estado.POSICIONANDO:
			if demo:
				_processar_demo(delta)
			else:
				_processar_controles_teclado(delta)
			_verificar_snap(delta)

		Estado.PARAFUSANDO:
			_processar_parafusamento(delta)

		Estado.FIXADA:
			tempo_estado -= delta
			if tempo_estado <= 0.0:
				if placa_atual < 2:
					placa_atual += 1
					pos_cursor = POSICOES_INICIAIS[placa_atual]
					progresso_parafuso = 0.0
					alinhado = false
					estado = Estado.POSICIONANDO
				else:
					_concluir_sucesso()

		Estado.CONCLUIDO, Estado.FALHA:
			pass

	# Atualiza simulação visual (faíscas, jitter de tela e LEDs)
	if graficos != null:
		graficos.atualizar(delta)
		painel.position = graficos.obter_jitter()

	painel.queue_redraw()


func _processar_controles_teclado(delta: float) -> void:
	var dir: Vector2 = Input.get_vector("esquerda", "direita", "cima", "baixo")
	if dir != Vector2.ZERO:
		pos_cursor += dir * VELOCIDADE * delta
		_limitar_posicao_cursor()
		interagiu = true
		if audio != null:
			audio.tocar_servo()
	else:
		if not arrastando_mouse and audio != null:
			audio.parar_servo()

	# Confirmação via teclado: E, Enter ou Espaço
	if Input.is_action_just_pressed("usar") and e_liberado:
		interagiu = true
		_tentar_fixar()


func _processar_demo(delta: float) -> void:
	var pos_alvo: Vector2 = GraficosBlindagem.BAIAS[placa_atual].position
	pos_cursor = pos_cursor.move_toward(pos_alvo, VELOCIDADE * 1.3 * delta)
	if audio != null:
		audio.tocar_servo()

	var centro_cursor: Vector2 = pos_cursor + Vector2(GraficosBlindagem.TAMANHO_PLACA / 2.0, GraficosBlindagem.TAMANHO_PLACA / 2.0)
	var centro_alvo: Vector2 = pos_alvo + Vector2(GraficosBlindagem.TAMANHO_PLACA / 2.0, GraficosBlindagem.TAMANHO_PLACA / 2.0)

	if centro_cursor.distance_to(centro_alvo) <= DISTANCIA_SNAP:
		alinhado = true
		if centro_cursor.distance_to(centro_alvo) <= 1.0:
			_tentar_fixar()


func _verificar_snap(delta: float) -> void:
	var centro_cursor: Vector2 = pos_cursor + Vector2(GraficosBlindagem.TAMANHO_PLACA / 2.0, GraficosBlindagem.TAMANHO_PLACA / 2.0)
	var baia_alvo: Rect2 = GraficosBlindagem.BAIAS[placa_atual]
	var centro_alvo: Vector2 = baia_alvo.position + Vector2(GraficosBlindagem.TAMANHO_PLACA / 2.0, GraficosBlindagem.TAMANHO_PLACA / 2.0)
	var dist: float = centro_cursor.distance_to(centro_alvo)

	if dist <= DISTANCIA_SNAP:
		if not alinhado:
			alinhado = true
			if audio != null:
				audio.tocar_snap()

		# Magnetismo suave (snap-to-target)
		var fator_snap: float = clampf(delta * 14.0, 0.0, 1.0)
		pos_cursor = pos_cursor.lerp(baia_alvo.position, fator_snap)
	else:
		alinhado = false


func _tentar_fixar() -> void:
	if estado != Estado.POSICIONANDO or finalizado:
		return

	if alinhado:
		_iniciar_parafusamento()
	else:
		_cometer_erro("ALINHAMENTO INCORRETO: APROXIME DA BAIA DESTACADA")


func _iniciar_parafusamento() -> void:
	estado = Estado.PARAFUSANDO
	progresso_parafuso = 0.0
	tempo_parafuso = 0.0
	ultimo_parafuso_audio = -1
	pos_cursor = GraficosBlindagem.BAIAS[placa_atual].position
	arrastando_mouse = false
	if audio != null:
		audio.parar_servo()


func _processar_parafusamento(delta: float) -> void:
	tempo_parafuso += delta
	progresso_parafuso = clampf(tempo_parafuso / DURACAO_PARAFUSO, 0.0, 1.0)

	# Screen jitter mecânico sincronizado com a rotação dos parafusos
	if graficos != null:
		graficos.disparar_jitter(0.08, 1.3)

	# Disparo sequencial do áudio de parafusadeira pneumática
	var idx_parafuso: int = int(progresso_parafuso / 0.25)
	if idx_parafuso != ultimo_parafuso_audio and idx_parafuso < 4:
		ultimo_parafuso_audio = idx_parafuso
		if audio != null:
			audio.tocar_parafusadeira()

	if progresso_parafuso >= 1.0:
		_finalizar_placa()


func _finalizar_placa() -> void:
	estado = Estado.FIXADA
	tempo_estado = 0.4
	placas_fixadas[placa_atual] = true
	if audio != null:
		audio.tocar_snap()


func _concluir_sucesso() -> void:
	if finalizado:
		return
	finalizado = true
	estado = Estado.CONCLUIDO
	acabou = true
	mensagem = "ABRIGO HERMETICO // BLINDAGEM 100% OPERACIONAL"
	if audio != null:
		audio.tocar_sucesso()
	painel.queue_redraw()
	await get_tree().create_timer(1.2).timeout
	terminou.emit()


func _cometer_erro(msg: String) -> void:
	erros_cometidos += 1
	mensagem_erro = msg
	tempo_mensagem_erro = 1.0
	if audio != null:
		audio.tocar_erro()
	if graficos != null:
		graficos.disparar_jitter(0.2, 2.5)

	if erros_cometidos >= MAX_ERROS:
		_falhar("LIMITE DE ERROS // FIXACAO COMPROMETIDA")


func _falhar(motivo: String) -> void:
	if finalizado:
		return
	finalizado = true
	estado = Estado.FALHA
	acabou = true
	mensagem = motivo
	if audio != null:
		audio.tocar_alarme()
	painel.queue_redraw()
	await get_tree().create_timer(1.2).timeout
	falhou.emit()


func _cancelar() -> void:
	if finalizado:
		return
	finalizado = true
	if audio != null:
		audio.parar_tudo()
	cancelou.emit()
	set_process(false)


func _limitar_posicao_cursor() -> void:
	# Limita as coordenadas da placa para dentro do chassi da antepara (40x40)
	pos_cursor.x = clampf(pos_cursor.x, 42.0, 238.0)
	pos_cursor.y = clampf(pos_cursor.y, 28.0, 120.0)


func _processar_emergencia(delta: float) -> void:
	if modo_emergencia.is_empty():
		return

	if tempo_restante_emergencia > 0.0:
		tempo_restante_emergencia = maxf(0.0, tempo_restante_emergencia - delta)
		if tempo_restante_emergencia <= 0.0:
			_falhar("TEMPO ESGOTADO // ALERTA DE RADIACAO")
			return

	tempo_alarme_emergencia -= delta
	if tempo_alarme_emergencia <= 0.0:
		tempo_alarme_emergencia = 3.5
		if audio != null and not acabou:
			audio.tocar_alarme_emergencia()


func _desenhar_conteudo() -> void:
	if graficos == null:
		return

	graficos.modo_emergencia = (modo_emergencia != "")

	var msg_exibida: String = mensagem
	if tempo_mensagem_erro > 0.0:
		msg_exibida = mensagem_erro
	elif estado == Estado.INTRO:
		msg_exibida = "ANALISANDO ANTEPARA ESTRUTURAL..."
	elif estado == Estado.PARAFUSANDO:
		msg_exibida = "PARAFUSANDO PLACA %d/3..." % (placa_atual + 1)
	elif modo_emergencia != "" and tempo_restante_emergencia > 0.0 and not acabou:
		msg_exibida = "TEMPO RESTANTE: %.1fS // FIXE AS PLACAS" % tempo_restante_emergencia

	graficos.desenhar_tudo(
		painel,
		pos_cursor,
		placa_atual,
		placas_fixadas,
		progresso_parafuso,
		alinhado,
		acabou,
		msg_exibida,
		hover_x
	)


func _criar_teclas() -> void:
	var teclas: Dictionary = {
		"esquerda": [KEY_A, KEY_LEFT],
		"direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	}
	for acao in teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
		for k in teclas[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			if not InputMap.action_has_event(acao, ev):
				InputMap.action_add_event(acao, ev)


# ==============================================================================
# CONTRATO COM O SISTEMA PRINCIPAL (mapa.gd)
# ==============================================================================

## Informa ao mapa se o jogador já começou a interagir com o minigame
func comecou() -> bool:
	return interagiu or erros_cometidos > 0 or placa_atual > 0 or estado != Estado.INTRO


## Retorna a taxa de penalidade por erros cometidos (de 0.0 a 1.0)
func taxa_erro() -> float:
	return clampf(float(erros_cometidos) * 0.25, 0.0, 1.0)
