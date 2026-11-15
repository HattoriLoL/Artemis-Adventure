class_name EmergenciaEletrica
extends Node2D
## Módulo Autônomo e Modular de Emergências Elétricas (Artemis Adventure - 320x180).
##
## Gerencia o ciclo de vida de crises na rede de energia da base lunar:
##   - EVENTO_SOLAR_SURGE: Sobrecarga por tempestade solar / CME da NASA (30s)
##   - EVENTO_PARTIAL_BLACKOUT: Blecaute parcial por falha de distribuição (35s)
##
## Integração com a base:
##   - Comunicação com Terminal de Energia (energia/terminal) e MinigameTerminal
##   - Renderização de alerta tático destacado no HUD (sem cobrir tarefas nem minimapa)
##   - Iluminação de emergência procedural (pulsos solares / flicker de blecaute)
##   - Síntese de áudio procedural sem assets externos (alarme master warning, bips e estabilização)
##   - Teclas manuais de debug: F9 (Surge), F10 (Blackout), F11 (Limpar)

# ------------------------------------------------------------------------------
# SINAIS DE COMUNICAÇÃO DE SISTEMA E ILUMINAÇÃO
# ------------------------------------------------------------------------------
signal emergencia_iniciada(tipo_evento: String, duracao: float)
signal emergencia_resolvida(tipo_evento: String)
signal emergencia_falhou(tipo_evento: String)
signal emergencia_atualizada(tempo_restante: float, duracao_total: float)

# ------------------------------------------------------------------------------
# CONSTANTES DE IDENTIFICAÇÃO E CONFIGURAÇÃO
# ------------------------------------------------------------------------------
const EVENTO_SOLAR_SURGE: String = "EVENTO_SOLAR_SURGE"
const EVENTO_PARTIAL_BLACKOUT: String = "EVENTO_PARTIAL_BLACKOUT"

const MODO_SURGE: String = "surge"
const MODO_BLACKOUT: String = "blackout"

const TEMPO_SOLAR_SURGE: float = 30.0
const TEMPO_PARTIAL_BLACKOUT: float = 35.0
const INTERVALO_SEGURANCA_MINIMO: float = 40.0
const PENALIDADE_ENERGIA: float = 15.0

# Cores da Paleta Apollo/Artemis
const PRETO := Color("#090a14")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const LARANJA := Color("#de9e41")
const VERMELHO := Color("#cf573c")
const VERMELHO_ESCURO := Color("#a53030")
const VERDE := Color("#a8ca58")
const CIANO := Color("#73bed3")
const ESCURO := Color("#151d28")
const FUNDO_ALERTA := Color(0.04, 0.05, 0.09, 0.90)

# Áudio Procedural
const TAXA_AMOSTRAGEM: int = 22050

# ------------------------------------------------------------------------------
# PROPRIEDADES E ESTADO DO MÓDULO
# ------------------------------------------------------------------------------
@export var agendamento_habilitado: bool = true
@export var duracao_surge: float = TEMPO_SOLAR_SURGE
@export var duracao_blackout: float = TEMPO_PARTIAL_BLACKOUT
@export var intervalo_seguranca: float = INTERVALO_SEGURANCA_MINIMO

var emergencia_ativa: bool = false
var tipo_ativo: String = ""
var modo_ativo: String = ""
var duracao_total: float = 0.0
var tempo_restante: float = 0.0

# Ciclo de Vida e Agendamento
var tempo_desde_ultima_emergencia: float = INTERVALO_SEGURANCA_MINIMO
var tempo_proximo_evento: float = 75.0
var tempo_total: float = 0.0
var t_sirene_alarme: float = 0.0

# Referências de Integração
var mapa: Node2D = null
var hud_alerta: Control = null
var camada_iluminacao: CanvasLayer = null
var overlay_iluminacao: Control = null
var iluminacao_externa: Node = null
var minigame_conectado: Control = null

# Backup do texto original da tarefa de energia
var texto_tarefa_backup: String = ""

# Cache de streams PCM sintetizados proceduralmente
static var _stream_alarme: AudioStreamWAV = null
static var _stream_estabilizacao: AudioStreamWAV = null
static var _stream_falha: AudioStreamWAV = null
static var _stream_tick: AudioStreamWAV = null


func _ready() -> void:
	_inicializar_audio()
	_inicializar_overlay_iluminacao()
	_localizar_e_conectar_mapa()
	_inicializar_hud_alerta()
	tempo_proximo_evento = randf_range(65.0, 115.0)


# ==============================================================================
# LOCALIZAÇÃO E CONEXÃO COM O MAPA E TERMINAL
# ==============================================================================

func _localizar_e_conectar_mapa() -> void:
	if mapa != null:
		return

	var p: Node = get_parent()
	if p != null and (p.name == "Mapa" or p.has_method("abrir_minigame")):
		mapa = p as Node2D
	elif get_tree() != null and get_tree().current_scene != null:
		var cena: Node = get_tree().current_scene
		if cena.name == "Mapa" or cena.has_method("abrir_minigame"):
			mapa = cena as Node2D
		else:
			var achou: Node = get_tree().root.find_child("Mapa", true, false)
			if achou != null and achou.has_method("abrir_minigame"):
				mapa = achou as Node2D

	if mapa != null and "camada_ui" in mapa and mapa.camada_ui != null:
		if not mapa.camada_ui.child_entered_tree.is_connected(_on_camada_ui_child_entered):
			mapa.camada_ui.child_entered_tree.connect(_on_camada_ui_child_entered)

	_localizar_iluminacao()


func _localizar_iluminacao() -> void:
	if is_instance_valid(iluminacao_externa):
		return
	if mapa != null:
		iluminacao_externa = mapa.find_child("IluminacaoEmergencia", true, false)
	if iluminacao_externa == null and get_tree() != null and get_tree().root != null:
		iluminacao_externa = get_tree().root.find_child("IluminacaoEmergencia", true, false)


# ==============================================================================
# PROCESSAMENTO DE CICLO DE VIDA E ATALHOS
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_F9:
					print("EmergenciaEletrica [DEBUG]: F9 -> SOLAR SURGE disparado!")
					disparar_solar_surge()
					get_viewport().set_input_as_handled()
				KEY_F10:
					print("EmergenciaEletrica [DEBUG]: F10 -> PARTIAL BLACKOUT disparado!")
					disparar_partial_blackout()
					get_viewport().set_input_as_handled()
				KEY_F11:
					print("EmergenciaEletrica [DEBUG]: F11 -> Emergencia limpa / Base restaurada!")
					limpar_emergencia()
					get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	tempo_total += delta

	if mapa == null:
		_localizar_e_conectar_mapa()

	if emergencia_ativa:
		_processar_emergencia_ativa(delta)
	else:
		_processar_agendamento(delta)

	if hud_alerta != null and hud_alerta.visible:
		hud_alerta.queue_redraw()

	if overlay_iluminacao != null and overlay_iluminacao.visible:
		overlay_iluminacao.queue_redraw()


func _processar_agendamento(delta: float) -> void:
	if not agendamento_habilitado:
		return

	# Não agenda nem dispara durante noites lunares ou descanso da tripulação
	if _esta_em_periodo_invalido():
		return

	tempo_desde_ultima_emergencia += delta
	if tempo_desde_ultima_emergencia < intervalo_seguranca:
		return

	tempo_proximo_evento -= delta
	if tempo_proximo_evento <= 0.0:
		tempo_proximo_evento = randf_range(65.0, 120.0)
		var sortear_surge: bool = randf() < 0.5
		if sortear_surge:
			iniciar_emergencia(EVENTO_SOLAR_SURGE)
		else:
			iniciar_emergencia(EVENTO_PARTIAL_BLACKOUT)


func _esta_em_periodo_invalido() -> bool:
	if Recursos != null and Recursos.noite:
		return true

	if mapa != null:
		if "dormindo" in mapa and bool(mapa.dormindo):
			return true
		if "escuro" in mapa and float(mapa.escuro) > 0.05:
			return true
		if "fim" in mapa and bool(mapa.fim):
			return true
		if "ciclo" in mapa and mapa.ciclo != null:
			if mapa.ciclo.has_method("ocupado") and bool(mapa.ciclo.ocupado()):
				return true

	return false


func _processar_emergencia_ativa(delta: float) -> void:
	# Se a missão encerrou ou o jogador foi dormir de forma forçada, cancela a emergência
	if mapa != null and "fim" in mapa and bool(mapa.fim):
		limpar_emergencia()
		return

	tempo_restante -= delta
	emergencia_atualizada.emit(tempo_restante, duracao_total)

	# Atualiza o minigame caso esteja aberto pelo jogador
	if is_instance_valid(minigame_conectado):
		if "tempo_restante_emergencia" in minigame_conectado:
			minigame_conectado.tempo_restante_emergencia = tempo_restante

	# Bip sonoro tático nos últimos 5 segundos (a cada segundo exato)
	if tempo_restante <= 5.0 and tempo_restante > 0.0:
		var seg_anterior: int = ceili(tempo_restante + delta)
		var seg_atual: int = ceili(tempo_restante)
		if seg_anterior != seg_atual:
			_tocar_tick()

	# Sirene intermitente da NASA
	t_sirene_alarme -= delta
	if t_sirene_alarme <= 0.0:
		var freq_alarme: float = 1.35 if tempo_restante > 10.0 else 0.70
		t_sirene_alarme = freq_alarme
		_tocar_alarme()

	# Mantém a marca visual do terminal pulsando intensamente
	_atualizar_destaque_terminal_mapa()

	# Interceptação de proximidade com o terminal de energia
	_verificar_interacao_emergencia()

	# Se o cronômetro zerou: FALHA CATASTRÓFICA
	if tempo_restante <= 0.0:
		tempo_restante = 0.0
		falhar_emergencia()


# ==============================================================================
# DISPARO, RESOLUÇÃO E FALHA DE EVENTOS
# ==============================================================================

func disparar_solar_surge() -> void:
	iniciar_emergencia(EVENTO_SOLAR_SURGE)


func disparar_partial_blackout() -> void:
	iniciar_emergencia(EVENTO_PARTIAL_BLACKOUT)


func iniciar_emergencia(tipo: String) -> void:
	if tipo == MODO_SURGE or tipo == EVENTO_SOLAR_SURGE:
		tipo_ativo = EVENTO_SOLAR_SURGE
		modo_ativo = MODO_SURGE
		duracao_total = duracao_surge
	else:
		tipo_ativo = EVENTO_PARTIAL_BLACKOUT
		modo_ativo = MODO_BLACKOUT
		duracao_total = duracao_blackout

	emergencia_ativa = true
	tempo_restante = duracao_total
	tempo_desde_ultima_emergencia = 0.0
	t_sirene_alarme = 0.1

	_ativar_terminal_emergencia()

	if hud_alerta != null:
		hud_alerta.visible = true
		hud_alerta.queue_redraw()

	_localizar_iluminacao()
	if is_instance_valid(iluminacao_externa):
		if tipo_ativo == EVENTO_SOLAR_SURGE and iluminacao_externa.has_method("ativar_surto_solar"):
			iluminacao_externa.ativar_surto_solar(1.0)
		elif tipo_ativo == EVENTO_PARTIAL_BLACKOUT and iluminacao_externa.has_method("ativar_blecaute_parcial"):
			iluminacao_externa.ativar_blecaute_parcial()
		if overlay_iluminacao != null:
			overlay_iluminacao.visible = false
	elif overlay_iluminacao != null:
		overlay_iluminacao.visible = true
		overlay_iluminacao.queue_redraw()

	if mapa != null and mapa.has_method("_avisar"):
		if tipo_ativo == EVENTO_SOLAR_SURGE:
			mapa._avisar("EMERGENCY: SOLAR SURGE DETECTED!")
		else:
			mapa._avisar("EMERGENCY: PARTIAL BLACKOUT!")

	emergencia_iniciada.emit(tipo_ativo, duracao_total)
	print("EmergenciaEletrica: Emergencia iniciada [%s] - Tempo: %0.1fs" % [tipo_ativo, duracao_total])


func resolver_emergencia() -> void:
	if not emergencia_ativa:
		return

	print("EmergenciaEletrica: Emergencia estabilizada com sucesso: ", tipo_ativo)
	var resolvido: String = tipo_ativo

	emergencia_ativa = false
	tempo_restante = 0.0
	tempo_desde_ultima_emergencia = 0.0
	t_sirene_alarme = 999.0

	_tocar_estabilizacao()
	_restaurar_terminal_mapa()

	minigame_conectado = null

	_localizar_iluminacao()
	if is_instance_valid(iluminacao_externa) and iluminacao_externa.has_method("iniciar_recuperacao"):
		iluminacao_externa.iniciar_recuperacao()

	if hud_alerta != null:
		hud_alerta.visible = false

	if overlay_iluminacao != null:
		overlay_iluminacao.visible = false

	if mapa != null and mapa.has_method("_avisar"):
		mapa._avisar("POWER GRID RESTORED & STABILIZED")

	emergencia_resolvida.emit(resolvido)


func falhar_emergencia() -> void:
	if not emergencia_ativa:
		return

	print("EmergenciaEletrica: Tempo esgotado! Falha critica no setor: ", tipo_ativo)
	var falhou_tipo: String = tipo_ativo

	emergencia_ativa = false
	tempo_restante = 0.0
	tempo_desde_ultima_emergencia = 0.0
	t_sirene_alarme = 999.0

	_tocar_falha()

	_localizar_iluminacao()
	if is_instance_valid(iluminacao_externa) and iluminacao_externa.has_method("iniciar_recuperacao"):
		iluminacao_externa.iniciar_recuperacao()

	# Aplica penalidade de -15 Energia
	if Recursos != null and "valores" in Recursos and Recursos.valores.has("energia"):
		var atual: float = float(Recursos.valores["energia"])
		var novo: float = maxf(0.0, atual - PENALIDADE_ENERGIA)
		var dif: float = novo - atual
		Recursos.valores["energia"] = novo
		Recursos.mudou.emit("energia/terminal", {"energia": dif})
		print("EmergenciaEletrica: Penalidade aplicada [-15 ENERGIA] -> Novo valor: ", novo)

	# Se o minigame estiver aberto, dispara a falha nele
	if is_instance_valid(minigame_conectado):
		if minigame_conectado.has_signal("falhou"):
			minigame_conectado.falhou.emit()
		minigame_conectado = null

	_restaurar_terminal_mapa()

	if hud_alerta != null:
		hud_alerta.visible = false

	if overlay_iluminacao != null:
		overlay_iluminacao.visible = false

	if mapa != null and mapa.has_method("_avisar"):
		mapa._avisar("GRID FAILURE: -15 POWER LOST!")

	emergencia_falhou.emit(falhou_tipo)


func limpar_emergencia() -> void:
	if not emergencia_ativa:
		return

	print("EmergenciaEletrica: Emergencia limpa via comando debug.")
	emergencia_ativa = false
	tempo_restante = 0.0
	tempo_desde_ultima_emergencia = 0.0
	t_sirene_alarme = 999.0

	_localizar_iluminacao()
	if is_instance_valid(iluminacao_externa) and iluminacao_externa.has_method("resetar_normal"):
		iluminacao_externa.resetar_normal()

	_restaurar_terminal_mapa()

	if is_instance_valid(minigame_conectado):
		if minigame_conectado.has_signal("cancelou"):
			minigame_conectado.cancelou.emit()
		minigame_conectado = null

	if hud_alerta != null:
		hud_alerta.visible = false

	if overlay_iluminacao != null:
		overlay_iluminacao.visible = false

	if mapa != null and mapa.has_method("_avisar"):
		mapa._avisar("BASE RESTORED // SYSTEM RESET")


# ==============================================================================
# CONEXÃO COM TERMINAL DE ENERGIA E INTERAÇÃO
# ==============================================================================

func _ativar_terminal_emergencia() -> void:
	if mapa == null:
		return

	if "feitas" in mapa and mapa.feitas is Dictionary:
		mapa.feitas.erase("energia/terminal")

	if "ciclo" in mapa and mapa.ciclo != null and "hoje" in mapa.ciclo:
		if not ("energia/terminal" in mapa.ciclo.hoje):
			mapa.ciclo.hoje.append("energia/terminal")

	if "tarefas" in mapa and mapa.tarefas is Array:
		for item: Variant in mapa.tarefas:
			if item is Dictionary and item.get("id") == "energia/terminal":
				if texto_tarefa_backup == "":
					texto_tarefa_backup = str(item.get("texto", "RESTART THE TERMINAL"))
				if tipo_ativo == EVENTO_SOLAR_SURGE:
					item["texto"] = "OVERLOAD RESTART (SOLAR SURGE)"
				else:
					item["texto"] = "RESTORE GRID (BLACKOUT)"
				break

	if mapa.has_method("_atualizar_marcas"):
		mapa._atualizar_marcas()


func _restaurar_terminal_mapa() -> void:
	if mapa == null:
		return

	if "tarefas" in mapa and mapa.tarefas is Array and texto_tarefa_backup != "":
		for item: Variant in mapa.tarefas:
			if item is Dictionary and item.get("id") == "energia/terminal":
				item["texto"] = texto_tarefa_backup
				break
		texto_tarefa_backup = ""

	if "marcas" in mapa and mapa.marcas is Dictionary and mapa.marcas.has("energia/terminal"):
		var m: Node = mapa.marcas["energia/terminal"]
		if m is CanvasItem:
			m.modulate = Color.WHITE

	if mapa.has_method("_atualizar_marcas"):
		mapa._atualizar_marcas()


func _atualizar_destaque_terminal_mapa() -> void:
	if mapa == null:
		return
	if "marcas" in mapa and mapa.marcas is Dictionary and mapa.marcas.has("energia/terminal"):
		var m: Node = mapa.marcas["energia/terminal"]
		if m is CanvasItem:
			m.visible = true
			var pisca: bool = fmod(tempo_total, 0.3) < 0.15
			m.modulate = VERMELHO if pisca else AMARELO


func _verificar_interacao_emergencia() -> void:
	if mapa == null or not emergencia_ativa:
		return

	# Se já está em minigame, dormindo ou painel aberto, ignora
	if ("em_minigame" in mapa and bool(mapa.em_minigame)) or ("dormindo" in mapa and bool(mapa.dormindo)):
		return

	# Se o ciclo do mapa zerou as ações normais do dia, garante que a emergência ainda possa ser acessada com E
	if Input.is_action_just_pressed("usar"):
		var tf_terminal: Dictionary = _obter_tarefa_terminal()
		if not tf_terminal.is_empty() and "jogador" in mapa and mapa.jogador != null:
			var pos_terminal: Vector2 = tf_terminal.get("pos", Vector2.ZERO)
			var dist: float = mapa.jogador.global_position.distance_to(pos_terminal)
			if dist <= 24.0:
				mapa.abrir_minigame("res://cenas/minigame_terminal.tscn", tf_terminal)


func _obter_tarefa_terminal() -> Dictionary:
	if mapa == null or not ("tarefas" in mapa) or not (mapa.tarefas is Array):
		return {}
	for item: Variant in mapa.tarefas:
		if item is Dictionary and item.get("id") == "energia/terminal":
			return item as Dictionary
	return {}


func _on_camada_ui_child_entered(node: Node) -> void:
	if not emergencia_ativa:
		return

	# Identifica o nó MinigameTerminal sendo adicionado à camada de UI
	if node is MinigameTerminal or node.name.begins_with("MinigameTerminal") or node.has_method("taxa_erro"):
		_configurar_minigame(node as Control)


func _configurar_minigame(mg: Control) -> void:
	minigame_conectado = mg
	print("EmergenciaEletrica: Configurando MinigameTerminal para modo de crise: ", modo_ativo)

	if "modo_emergencia" in mg:
		mg.modo_emergencia = modo_ativo
	if "tempo_restante_emergencia" in mg:
		mg.tempo_restante_emergencia = tempo_restante
	if mg.has_method("configurar_emergencia"):
		mg.configurar_emergencia(modo_ativo, tempo_restante)

	if mg.has_signal("terminou"):
		if not mg.terminou.is_connected(_on_minigame_terminou):
			mg.terminou.connect(_on_minigame_terminou, CONNECT_ONE_SHOT)
	if mg.has_signal("falhou"):
		if not mg.falhou.is_connected(_on_minigame_falhou):
			mg.falhou.connect(_on_minigame_falhou, CONNECT_ONE_SHOT)


func _on_minigame_terminou() -> void:
	if emergencia_ativa:
		resolver_emergencia()


func _on_minigame_falhou() -> void:
	if emergencia_ativa:
		falhar_emergencia()


# ==============================================================================
# HUD E NOTIFICAÇÕES (ALERTA TÁCTICO COMPACTO)
# ==============================================================================

func _inicializar_hud_alerta() -> void:
	hud_alerta = Control.new()
	hud_alerta.name = "HUDAlertaEmergencia"
	hud_alerta.size = Vector2(320, 180)
	hud_alerta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_alerta.visible = false
	hud_alerta.draw.connect(_desenhar_hud_alerta)

	if mapa != null and "camada_ui" in mapa and mapa.camada_ui != null:
		mapa.camada_ui.add_child(hud_alerta)
	else:
		var layer := CanvasLayer.new()
		layer.layer = 5
		layer.add_child(hud_alerta)
		add_child(layer)


func _desenhar_hud_alerta() -> void:
	if not emergencia_ativa:
		return

	var Fonte = preload("res://scripts/fonte.gd")
	var segs: int = ceili(tempo_restante)
	var txt_alerta: String = ""
	var cor_borda: Color = LARANJA

	if tipo_ativo == EVENTO_SOLAR_SURGE:
		txt_alerta = "[!] SOLAR SURGE DETECTED // MAIN BUS OVERLOAD [%ds]" % segs
		cor_borda = VERMELHO if fmod(tempo_total, 0.4) < 0.2 else AMARELO
	else:
		txt_alerta = "[!] PARTIAL BLACKOUT // GRID FAILURE [%ds]" % segs
		cor_borda = VERMELHO if fmod(tempo_total, 0.4) < 0.2 else CIANO

	if tempo_restante <= 10.0:
		cor_borda = VERMELHO if fmod(tempo_total, 0.2) < 0.1 else BRANCO

	var largura_txt: int = Fonte.largura(txt_alerta)
	var w: float = float(largura_txt + 8)
	var h: float = 11.0

	var em_mg: bool = false
	if mapa != null and "em_minigame" in mapa:
		em_mg = bool(mapa.em_minigame)

	# Posição limpa:
	# Em minigame: y = 2 (dentro dos 14px livres acima do chassi)
	# No mapa: y = 44 (centro livre entre a lista de tarefas e o aviso de sala, sem cobrir minimapa)
	var y_pos: float = 2.0 if em_mg else 44.0
	var x_pos: float = roundf(160.0 - w / 2.0)
	var r_box := Rect2(x_pos, y_pos, w, h)

	# Fundo industrial escuro com transparência de visor HUD
	hud_alerta.draw_rect(r_box, FUNDO_ALERTA)

	# Borda de alerta tático
	hud_alerta.draw_rect(r_box, cor_borda, false, 1.0)

	# Marcadores táticos de cantos
	hud_alerta.draw_rect(Rect2(x_pos - 1, y_pos - 1, 2, 1), cor_borda)
	hud_alerta.draw_rect(Rect2(x_pos - 1, y_pos - 1, 1, 2), cor_borda)
	hud_alerta.draw_rect(Rect2(x_pos + w - 1, y_pos - 1, 2, 1), cor_borda)
	hud_alerta.draw_rect(Rect2(x_pos + w, y_pos - 1, 1, 2), cor_borda)
	hud_alerta.draw_rect(Rect2(x_pos - 1, y_pos + h, 2, 1), cor_borda)
	hud_alerta.draw_rect(Rect2(x_pos - 1, y_pos + h - 1, 1, 2), cor_borda)
	hud_alerta.draw_rect(Rect2(x_pos + w - 1, y_pos + h, 2, 1), cor_borda)
	hud_alerta.draw_rect(Rect2(x_pos + w, y_pos + h - 1, 1, 2), cor_borda)

	var cor_texto: Color = BRANCO
	if tempo_restante <= 5.0 and fmod(tempo_total, 0.2) < 0.1:
		cor_texto = VERMELHO

	Fonte.centralizado(hud_alerta, txt_alerta, 160.0, y_pos + 3.0, cor_texto)


# ==============================================================================
# ILUMINAÇÃO DE EMERGÊNCIA PROCEDURAL
# ==============================================================================

func _inicializar_overlay_iluminacao() -> void:
	camada_iluminacao = CanvasLayer.new()
	camada_iluminacao.layer = 2 # Acima do mapa, abaixo dos elementos de HUD
	camada_iluminacao.name = "CamadaIluminacaoEmergencia"
	add_child(camada_iluminacao)

	overlay_iluminacao = Control.new()
	overlay_iluminacao.size = Vector2(320, 180)
	overlay_iluminacao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_iluminacao.visible = false
	overlay_iluminacao.draw.connect(_desenhar_iluminacao_ambiente)
	camada_iluminacao.add_child(overlay_iluminacao)


func _desenhar_iluminacao_ambiente() -> void:
	if not emergencia_ativa:
		return

	# Se estiver dentro de minigame em tela cheia, minimiza a modulação do mapa
	var em_mg: bool = false
	if mapa != null and "em_minigame" in mapa:
		em_mg = bool(mapa.em_minigame)

	if tipo_ativo == EVENTO_SOLAR_SURGE:
		# Brilho de tempestade solar (CME): radiação pulsante âmbar e vermelha
		var pulso: float = 0.08 + 0.06 * sin(tempo_total * 7.0)
		if em_mg:
			pulso *= 0.4
		overlay_iluminacao.draw_rect(Rect2(0, 0, 320, 180), Color(1.0, 0.42, 0.12, pulso))

	elif tipo_ativo == EVENTO_PARTIAL_BLACKOUT:
		# Blecaute parcial: queda de iluminação com micro-flickers aleatórios
		var escurecimento: float = 0.28
		if randf() < 0.06:
			escurecimento = randf_range(0.40, 0.60) # Oscilação de tensão na rede
		if em_mg:
			escurecimento *= 0.35
		overlay_iluminacao.draw_rect(Rect2(0, 0, 320, 180), Color(0.02, 0.03, 0.08, escurecimento))


# ==============================================================================
# SÍNTESE DE ÁUDIO PROCEDURAL (NATIVO GODOT 4 / ZERO EXTERNAL DEPENDENCY)
# ==============================================================================

func _inicializar_audio() -> void:
	if _stream_alarme == null:
		_stream_alarme = _sintetizar_pulso_alarme()
	if _stream_estabilizacao == null:
		_stream_estabilizacao = _sintetizar_som_estabilizacao()
	if _stream_falha == null:
		_stream_falha = _sintetizar_som_falha()
	if _stream_tick == null:
		_stream_tick = _sintetizar_som_tick()


func _tocar_alarme() -> void:
	if _stream_alarme != null:
		_tocar_stream(_stream_alarme, -4.0 if tempo_restante > 10.0 else -1.5)


func _tocar_estabilizacao() -> void:
	if _stream_estabilizacao != null:
		_tocar_stream(_stream_estabilizacao, 0.0)


func _tocar_falha() -> void:
	if _stream_falha != null:
		_tocar_stream(_stream_falha, 1.0)


func _tocar_tick() -> void:
	if _stream_tick != null:
		_tocar_stream(_stream_tick, -2.0)


func _tocar_stream(stream: AudioStreamWAV, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## 1. Alarme Apollo/Artemis Master Warning (Dual-Tone 880Hz / 700Hz com envelope mecânico)
static func _sintetizar_pulso_alarme() -> AudioStreamWAV:
	var duracao: float = 0.32
	var total: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total * 2)

	for i: int in range(total):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var freq: float = 880.0 if fmod(t, 0.16) < 0.08 else 700.0
		var env: float = clampf((duracao - t) / 0.02, 0.0, 1.0) * (0.85 if t > 0.01 else t / 0.01)
		var onda: float = sin(TAU * freq * t) * 0.70 + (1.0 if sin(TAU * freq * 0.5 * t) >= 0.0 else -1.0) * 0.15
		var val: int = int(clampf(onda * env, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val)

	return _construir_stream_wav(bytes)


## 2. Acorde de estabilização triunfal (Tríade harmônica limpa de restabelecimento C5 -> E5 -> G5)
static func _sintetizar_som_estabilizacao() -> AudioStreamWAV:
	var duracao: float = 0.65
	var total: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total * 2)

	for i: int in range(total):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var c5: float = sin(TAU * 523.25 * t) * exp(-t / 0.35) * 0.35
		var e5: float = sin(TAU * 659.25 * t) * exp(-t / 0.30) * 0.30
		var g5: float = sin(TAU * 783.99 * t) * exp(-t / 0.25) * 0.25
		var c6: float = sin(TAU * 1046.50 * t) * exp(-t / 0.15) * 0.15
		var env_geral: float = clampf((duracao - t) / 0.02, 0.0, 1.0)
		var sinal: float = clampf((c5 + e5 + g5 + c6) * env_geral, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sinal * 32767.0))

	return _construir_stream_wav(bytes)


## 3. Som de falha elétrica / Desarme violento de barramento e ruído de arco
static func _sintetizar_som_falha() -> AudioStreamWAV:
	var duracao: float = 0.55
	var total: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total * 2)

	var fase: float = 0.0
	for i: int in range(total):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var freq: float = lerpf(130.0, 40.0, t / duracao)
		fase += TAU * freq / float(TAXA_AMOSTRAGEM)
		var sq: float = 1.0 if sin(fase) >= 0.0 else -1.0
		var spark: float = (randf() * 2.0 - 1.0) * exp(-t / 0.08) * 0.35
		var env: float = exp(-t / 0.22) * clampf((duracao - t) / 0.03, 0.0, 1.0)
		var sinal: float = clampf((sq * 0.50 + spark) * env, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sinal * 32767.0))

	return _construir_stream_wav(bytes)


## 4. Bip curto de urgência (Pip de cronômetro crítico 1200Hz)
static func _sintetizar_som_tick() -> AudioStreamWAV:
	var duracao: float = 0.04
	var total: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total * 2)

	for i: int in range(total):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var env: float = exp(-t / 0.009) * clampf((duracao - t) / 0.004, 0.0, 1.0)
		var sinal: float = sin(TAU * 1200.0 * t) * env * 0.65
		bytes.encode_s16(i * 2, int(sinal * 32767.0))

	return _construir_stream_wav(bytes)


static func _construir_stream_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TAXA_AMOSTRAGEM
	stream.stereo = false
	stream.data = bytes
	return stream
