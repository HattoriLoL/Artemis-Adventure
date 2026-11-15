extends CanvasLayer
## TouchOverlay: Camada de controles touch na tela para dispositivos móveis e navegadores web.
## Gerencia o D-Pad, o Botão de Ação [E], o Botão de Corrida e atalhos de topo (Pausa e Minimizar).

const Fonte = preload("res://scripts/fonte.gd")
const VirtualDPad = preload("res://scripts/mobile/virtual_dpad.gd")
const VirtualActionButton = preload("res://scripts/mobile/virtual_action_button.gd")

const COR_FUNDO_BOTAO := Color("#151d28", 0.75)
const COR_BORDA_BOTAO := Color("#394a50", 0.90)
const COR_ICONE := Color("#819796")
const COR_ICONE_ATIVO := Color("#f2b134")

var raiz_ui: Control
var dpad: Control
var btn_acao: Control
var btn_correr: Control
var btn_pausa: Control
var btn_toggle: Control

var em_minigame := false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir_ui()
	_conectar_mobile_manager()
	_atualizar_visibilidade()


func _conectar_mobile_manager() -> void:
	var mm = get_node_or_null("/root/MobileManager")
	if mm:
		mm.touch_controls_toggled.connect(_ao_alternar_controles)
		mm.controls_minimized_changed.connect(_ao_alternar_minimizado)


func _atualizar_visibilidade() -> void:
	var mm = get_node_or_null("/root/MobileManager")
	if mm:
		visible = mm.touch_controls_enabled
	else:
		visible = false


func _ao_alternar_controles(habilitado: bool) -> void:
	visible = habilitado


func _ao_alternar_minimizado(minimizado: bool) -> void:
	if dpad:
		dpad.visible = not minimizado and not em_minigame
	if btn_acao:
		btn_acao.visible = not minimizado
	if btn_correr:
		btn_correr.visible = not minimizado and not em_minigame


## Notificação chamada pelo mapa.gd quando entra ou sai de minigame
func definir_modo_minigame(ativo: bool, precisa_usar := true) -> void:
	em_minigame = ativo
	var mm = get_node_or_null("/root/MobileManager")
	var minimizado: bool = mm.controls_minimized if mm else false
	
	if dpad:
		dpad.visible = not ativo and not minimizado
	if btn_correr:
		btn_correr.visible = not ativo and not minimizado
	if btn_acao:
		btn_acao.visible = (precisa_usar or not ativo) and not minimizado


func _construir_ui() -> void:
	raiz_ui = Control.new()
	raiz_ui.name = "ControlesTouch"
	raiz_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(raiz_ui)
	
	# 1. D-Pad Virtual (Inferior Esquerdo)
	dpad = VirtualDPad.new()
	dpad.name = "DPad"
	dpad.raio = 24.0
	dpad.position = Vector2(10, 118)
	raiz_ui.add_child(dpad)
	
	# 2. Botão de Corrida Virtual (Pequeno, acima do D-Pad)
	btn_correr = VirtualActionButton.new()
	btn_correr.name = "BtnCorrer"
	btn_correr.raio = 10.0
	btn_correr.rotulo = "RUN"
	btn_correr.acao = "correr"
	btn_correr.position = Vector2(12, 94)
	raiz_ui.add_child(btn_correr)
	
	# 3. Botão de Interação [E] (Lado Direito, posicionado ergonomicamente entre as barras e o minimapa)
	btn_acao = VirtualActionButton.new()
	btn_acao.name = "BtnInteragir"
	btn_acao.raio = 17.0
	btn_acao.rotulo = "E"
	btn_acao.acao = "usar"
	btn_acao.position = Vector2(276, 62)
	raiz_ui.add_child(btn_acao)
	
	# 4. Botão de Pausa (Topo Central, livre de sobreposição com tarefas e recursos)
	btn_pausa = _criar_botao_topo(Vector2(134, 4), Vector2(14, 12), "pausa")
	raiz_ui.add_child(btn_pausa)
	
	# 5. Botão de Ocultar/Minimizar Controles (Ao lado da pausa)
	btn_toggle = _criar_botao_topo(Vector2(152, 4), Vector2(14, 12), "toggle")
	raiz_ui.add_child(btn_toggle)


func _criar_botao_topo(pos: Vector2, tam: Vector2, tipo: String) -> Control:
	var btn := Control.new()
	btn.position = pos
	btn.custom_minimum_size = tam
	btn.size = tam
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	btn.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			if tipo == "pausa":
				if not InputMap.has_action("ui_cancel"):
					InputMap.add_action("ui_cancel")
				Input.action_press("ui_cancel")
				# Libera no quadro seguinte para registrar o pulso de clique
				get_tree().create_timer(0.05).timeout.connect(func(): Input.action_release("ui_cancel"))
			elif tipo == "toggle":
				var mm = get_node_or_null("/root/MobileManager")
				if mm:
					mm.alternar_minimizado()
	)
	
	btn.draw.connect(func():
		var r := Rect2(Vector2.ZERO, tam)
		btn.draw_rect(r, COR_FUNDO_BOTAO)
		btn.draw_rect(r, COR_BORDA_BOTAO, false, 1.0)
		
		if tipo == "pausa":
			# Desenha símbolo de pausa [||]
			btn.draw_rect(Rect2(4, 3, 2, 6), COR_ICONE)
			btn.draw_rect(Rect2(8, 3, 2, 6), COR_ICONE)
		elif tipo == "toggle":
			# Desenha ícone de controle / tela touch [📱]
			btn.draw_rect(Rect2(4, 2, 6, 8), COR_ICONE)
			btn.draw_rect(Rect2(5, 3, 4, 6), Color("#090a14"))
	)
	
	return btn
