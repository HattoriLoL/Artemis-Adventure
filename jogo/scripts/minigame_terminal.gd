class_name MinigameTerminal
extends Control
## Minigame "Reiniciar Terminal de Energia // Painel de Disjuntores" (Apollo/Artemis Circuit Breakers).
## Painel industrial em pixel art procedural 16-bit com 4 disjuntores de alavanca 3D,
## LEDs de glow dinâmico, síntese sonora mecânica e sequência de rearme de barramento 28V DC.
##
## Contrato de integração com mapa.gd:
##   - Sinais: `terminou`, `falhou`, `cancelou`
##   - Métodos: `comecou() -> bool`, `taxa_erro() -> float`
##   - Propriedade: `demo: bool`

signal terminou
signal falhou
signal cancelou

const Graficos = preload("res://scripts/minigame_terminal_graficos.gd")
const Audio = preload("res://scripts/minigame_terminal_audio.gd")

enum Estado { MOSTRANDO, JOGADOR, ERRO, CONCLUIDO }

# Paleta auxiliar rápida
const APAGADO := Color("#10141f")
const AMARELO := Color("#e8c170")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO_CLARO := Color("#cf573c")

# Limite máximo de erros antes da perda definitiva da tarefa
const MAX_ERROS: int = 4

# Configuração e sequência dos 4 disjuntores
var sequencia: Array[int] = [0, 1, 2, 3]
var passo_demo: int = 0
var passo_jogador: int = 0
var selecionado: int = 0
var estado: Estado = Estado.MOSTRANDO

# Temporizadores de máquina de estados
var timer: float = 0.0
var chave_acesa: int = -1
var tempo_total: float = 0.0

# Dinâmica de Alavancas (Animação mecânica com física de recoil)
var posicoes_alavancas: Array[float] = [0.0, 0.0, 0.0, 0.0] # 0.0 = OFF (baixo), 1.0 = ON (cima)
var alvos_alavancas: Array[float] = [0.0, 0.0, 0.0, 0.0]

# Dinâmica de LEDs
var leds_cores: Array[Color] = [APAGADO, APAGADO, APAGADO, APAGADO]
var leds_acesos: Array[bool] = [false, false, false, false]

# Feedback tátil / Jitter mecânico de clique no chassi
var t_jitter: float = 0.0

# Modo Demo e Automação
var demo: bool = false
var t_demo_click: float = 0.0
var e_liberado: bool = false

# Métricas para contrato de gameplay com mapa.gd
var interagiu: bool = false
var erros_cometidos: int = 0
var mensagem_display: String = ""

# Modo de emergência (integrado com EmergenciaEletrica)
var modo_emergencia: String = "" # "" (normal), "surge" ou "blackout"
var tempo_restante_emergencia: float = 0.0

# Componentes internos
var audio: AudioTerminal = null
@onready var painel: Control = $Painel


func _ready() -> void:
	_criar_teclas()
	_inicializar_audio()
	painel.draw.connect(_desenhar_conteudo)
	_gerar_sequencia()
	_iniciar_demonstracao()


func _inicializar_audio() -> void:
	audio = AudioTerminal.new()
	audio.name = "AudioTerminal"
	add_child(audio)


func _gerar_sequencia() -> void:
	var seq: Array[int] = [0, 1, 2, 3]
	seq.shuffle()
	sequencia = seq
	print("MinigameTerminal: Sequencia gerada: ", sequencia)


func _iniciar_demonstracao() -> void:
	estado = Estado.MOSTRANDO
	passo_demo = 0
	passo_jogador = 0
	timer = 0.6
	chave_acesa = -1
	t_demo_click = 0.0
	mensagem_display = "OBSERVE A SEQUENCIA DE REINICIALIZACAO..."

	# Disjuntores iniciam desarmados (0.0) e LEDs apagados
	for i in range(4):
		alvos_alavancas[i] = 0.0
		leds_cores[i] = APAGADO
		leds_acesos[i] = false

	if modo_emergencia == "surge":
		mensagem_display = "SOBRECARGA DETECTADA! OBSERVE A SEQUENCIA..."
	elif modo_emergencia == "blackout":
		mensagem_display = "BLECAUTE! OBSERVE A SEQUENCIA DE REARME..."


## Chamado por EmergenciaEletrica para configurar o minigame no modo de crise
func configurar_emergencia(modo: String, tempo: float) -> void:
	modo_emergencia = modo
	tempo_restante_emergencia = tempo
	if modo == "surge":
		mensagem_display = "SOBRECARGA DETECTADA! OBSERVE A SEQUENCIA..."
	elif modo == "blackout":
		mensagem_display = "BLECAUTE! OBSERVE A SEQUENCIA DE REARME..."


func comecou() -> bool:
	return interagiu or (estado == Estado.JOGADOR and passo_jogador > 0) or erros_cometidos > 0


func taxa_erro() -> float:
	# Penalidade moderada proporcional aos erros de sequência (0 erros = 0.0, máx 1.0)
	return clampf(float(erros_cometidos) * 0.25, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	# Se concluído ou em falha definitiva, ignora novos comandos do jogador
	if estado == Estado.CONCLUIDO or (estado == Estado.ERRO and erros_cometidos >= MAX_ERROS):
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE or key_event.is_action_pressed("ui_cancel"):
				if audio != null:
					audio.parar_tudo()
				cancelou.emit()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var mpos: Vector2 = mouse_event.position
			# Botão Fechar [X]
			if Graficos.RECT_BOTAO_X.has_point(Vector2i(int(mpos.x), int(mpos.y))):
				if audio != null:
					audio.parar_tudo()
				cancelou.emit()
				get_viewport().set_input_as_handled()
				return

			# Clique em uma das 4 baias de disjuntores durante o turno do jogador
			if not demo and estado == Estado.JOGADOR:
				for i: int in range(4):
					var bx: int = Graficos.CENTROS_X[i] - (Graficos.BAIAS_LARGURA / 2)
					var r_baia := Rect2i(bx, Graficos.BAIAS_Y, Graficos.BAIAS_LARGURA, Graficos.BAIAS_ALTURA)
					if r_baia.has_point(Vector2i(int(mpos.x), int(mpos.y))):
						var anterior: int = selecionado
						selecionado = i
						if audio != null and anterior != selecionado:
							audio.tocar_clique(-6.0)
						if e_liberado:
							_acionar_disjuntor(i)
						get_viewport().set_input_as_handled()
						break

	elif event is InputEventMouseMotion:
		# Hover do mouse sobre as baias para feedback tátil de foco
		if not demo and estado == Estado.JOGADOR:
			var mpos_motion: Vector2 = event.position
			for i: int in range(4):
				var bx: int = Graficos.CENTROS_X[i] - (Graficos.BAIAS_LARGURA / 2)
				var r_baia := Rect2i(bx, Graficos.BAIAS_Y, Graficos.BAIAS_LARGURA, Graficos.BAIAS_ALTURA)
				if r_baia.has_point(Vector2i(int(mpos_motion.x), int(mpos_motion.y))):
					if selecionado != i:
						selecionado = i
						if audio != null:
							audio.tocar_clique(-6.0)
					break


func _process(delta: float) -> void:
	tempo_total += delta

	# Evita que a tecla E que abriu o minigame dispare um disjuntor de imediato
	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true

	# Atualização física de animação das alavancas mecânicas (Interpolação suave)
	_atualizar_animacoes_alavancas(delta)

	# Atualização do tremor mecânico (Jitter) do chassi
	if t_jitter > 0.0:
		t_jitter = maxf(0.0, t_jitter - delta)
		if t_jitter > 0.0:
			painel.position = Vector2(randi_range(-1, 1), randi_range(-1, 1))
		else:
			painel.position = Vector2.ZERO

	# Máquina de Estados do Minigame
	match estado:
		Estado.MOSTRANDO:
			_processar_modo_demonstracao(delta)

		Estado.JOGADOR:
			if demo:
				_jogar_sozinho(delta)
			else:
				_controles_jogador()

		Estado.ERRO:
			timer -= delta
			# Efeito de piscar vermelho durante o erro
			var pisca: bool = fmod(timer, 0.24) < 0.12
			for i: int in range(4):
				leds_cores[i] = VERMELHO_CLARO if pisca else APAGADO
				leds_acesos[i] = pisca

			if timer <= 0.0:
				if erros_cometidos >= MAX_ERROS:
					falhou.emit()
					set_process(false)
				else:
					_iniciar_demonstracao()

		Estado.CONCLUIDO:
			timer -= delta
			for i: int in range(4):
				leds_cores[i] = VERDE_LIMA
				leds_acesos[i] = true
				alvos_alavancas[i] = 1.0

			if timer <= 0.0:
				terminou.emit()
				set_process(false)

	painel.queue_redraw()


func _atualizar_animacoes_alavancas(delta: float) -> void:
	for i in range(4):
		var pos_atual: float = posicoes_alavancas[i]
		var pos_alvo: float = alvos_alavancas[i]
		if not is_equal_approx(pos_atual, pos_alvo):
			posicoes_alavancas[i] = move_toward(pos_atual, pos_alvo, delta * 14.0)


func _processar_modo_demonstracao(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		if chave_acesa != -1:
			# Apaga o LED que estava em destaque e dá um intervalo curto de silêncio
			leds_cores[chave_acesa] = APAGADO
			leds_acesos[chave_acesa] = false
			chave_acesa = -1
			timer = 0.18
		else:
			if passo_demo < sequencia.size():
				chave_acesa = sequencia[passo_demo]
				leds_cores[chave_acesa] = AMARELO
				leds_acesos[chave_acesa] = true

				# Toca bip aeroespacial harmônico da NASA sintonizado ao índice
				if audio != null:
					audio.tocar_bip(chave_acesa, -2.0)

				passo_demo += 1
				timer = 0.50
			else:
				# Demonstração concluída: transição para controle do jogador
				estado = Estado.JOGADOR
				passo_jogador = 0
				chave_acesa = -1
				mensagem_display = "PASSO 1/4: ARME OS DISJUNTORES NA ORDEM"
				for i in range(4):
					leds_cores[i] = APAGADO
					leds_acesos[i] = false
					alvos_alavancas[i] = 0.0


func _controles_jogador() -> void:
	if Input.is_action_just_pressed("esquerda"):
		var anterior: int = selecionado
		selecionado = (selecionado - 1 + 4) % 4
		if audio != null and anterior != selecionado:
			audio.tocar_clique(-6.0)

	elif Input.is_action_just_pressed("direita"):
		var anterior: int = selecionado
		selecionado = (selecionado + 1) % 4
		if audio != null and anterior != selecionado:
			audio.tocar_clique(-6.0)

	if Input.is_action_just_pressed("usar") and e_liberado:
		_acionar_disjuntor(selecionado)


func _acionar_disjuntor(idx: int) -> void:
	if estado != Estado.JOGADOR or passo_jogador >= sequencia.size():
		return
	if idx < 0 or idx >= 4:
		return

	interagiu = true

	# Alavanca é armada para cima fisicamente com impacto
	alvos_alavancas[idx] = 1.0
	t_jitter = 0.07

	var esperado: int = sequencia[passo_jogador]

	if idx == esperado:
		# Acerto do disjuntor da vez!
		leds_cores[idx] = VERDE_LIMA
		leds_acesos[idx] = true
		passo_jogador += 1

		if audio != null:
			# Som de relé industrial de alta voltagem atracando
			audio.tocar_encaixe(-1.0)

		if passo_jogador >= sequencia.size():
			# Sequência completa: rearme geral do barramento!
			estado = Estado.CONCLUIDO
			timer = 1.4
			if modo_emergencia == "surge":
				mensagem_display = "SURGE SOLAR DISSIPADO // BARRAMENTO ESTABILIZADO!"
			elif modo_emergencia == "blackout":
				mensagem_display = "BLECAUTE SUPERADO // BARRAMENTO 28V ONLINE!"
			else:
				mensagem_display = "SISTEMA RESTAURADO // BARRAMENTO 28V ONLINE!"
			if audio != null:
				audio.tocar_rearme(0.0)
		else:
			mensagem_display = "PASSO %d/4: ARME OS DISJUNTORES NA ORDEM" % [passo_jogador + 1]

	else:
		# Erro de sequência!
		erros_cometidos += 1
		estado = Estado.ERRO
		timer = 1.0
		if erros_cometidos >= MAX_ERROS:
			mensagem_display = "SOBRECARGA CRITICA! TAREFA FALHOU (%d/%d)" % [erros_cometidos, MAX_ERROS]
		else:
			mensagem_display = "FALHA DE SEQUENCIA! REINICIANDO (%d/%d)" % [erros_cometidos, MAX_ERROS]

		# Som de desarme elétrico violento por sobrecarga
		if audio != null:
			audio.tocar_erro(0.0)

		# Desarma todas as alavancas imediatamente
		for i in range(4):
			alvos_alavancas[i] = 0.0


func _jogar_sozinho(delta: float) -> void:
	if passo_jogador >= sequencia.size():
		return
	t_demo_click += delta
	if t_demo_click >= 0.45:
		t_demo_click = 0.0
		var alvo: int = sequencia[passo_jogador]
		if selecionado != alvo:
			selecionado = alvo
			if audio != null:
				audio.tocar_clique(-6.0)
		_acionar_disjuntor(alvo)


func _desenhar_conteudo() -> void:
	Graficos.desenhar_painel(
		painel,
		int(estado),
		selecionado,
		passo_jogador,
		posicoes_alavancas,
		leds_cores,
		leds_acesos,
		tempo_total,
		mensagem_display,
		modo_emergencia,
		tempo_restante_emergencia
	)


func _criar_teclas() -> void:
	var teclas: Dictionary = {
		"esquerda": [KEY_A, KEY_LEFT],
		"direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]
	}
	for acao: String in teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			var keys: Array = teclas[acao]
			for k: Key in keys:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(acao, ev)
