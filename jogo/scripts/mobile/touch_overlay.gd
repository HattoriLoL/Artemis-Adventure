extends CanvasLayer
## TouchOverlay: Camada de controles touch na tela para dispositivos móveis e navegadores web.
## Permite alternar entre Modo Celular (D-Pad + Ação na tela) e Modo Computador (tela limpa, sem setas).
## O D-Pad e o botão [E] ficam disponíveis em TODOS os minigames e no mapa para controle total por toque.

const Fonte = preload("res://scripts/fonte.gd")
const VirtualDPad = preload("res://scripts/mobile/virtual_dpad.gd")
const VirtualActionButton = preload("res://scripts/mobile/virtual_action_button.gd")

const COR_FUNDO_BOTAO := Color("#151d28", 0.85)
const COR_BORDA_BOTAO := Color("#394a50", 0.95)
const COR_ICONE := Color("#819796")
const COR_ATIVO := Color("#f2b134")

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
	visible = true
	_construir_ui()
	_conectar_mobile_manager()
	_atualizar_visibilidade_controles()


func _conectar_mobile_manager() -> void:
	var mm = get_node_or_null("/root/MobileManager")
	if mm:
		mm.touch_controls_toggled.connect(func(_habilitado: bool): _atualizar_visibilidade_controles())
		mm.controls_minimized_changed.connect(func(_minimizado: bool): _atualizar_visibilidade_controles())


func _atualizar_visibilidade_controles() -> void:
	var mm = get_node_or_null("/root/MobileManager")
	var touch_ativo: bool = mm.touch_controls_enabled if mm else false
	var minimizado: bool = mm.controls_minimized if mm else false
	
	# O D-Pad e o botão de ação ficam SEMPRE disponíveis no modo celular (no mapa e em todos os minigames)
	if dpad:
		dpad.visible = touch_ativo and not minimizado
		dpad.position = Vector2(6, 118) if em_minigame else Vector2(10, 118)
	if btn_correr:
		btn_correr.visible = touch_ativo and not em_minigame and not minimizado
	if btn_acao:
		btn_acao.visible = touch_ativo and not minimizado
		btn_acao.position = Vector2(272, 118) if em_minigame else Vector2(276, 62)
	if btn_pausa:
		btn_pausa.visible = touch_ativo
		
	if btn_toggle:
		btn_toggle.queue_redraw()


## Notificação chamada pelo mapa.gd quando entra ou sai de minigame
func definir_modo_minigame(ativo: bool, _precisa_usar := true) -> void:
	em_minigame = ativo
	_atualizar_visibilidade_controles()


func _unhandled_input(ev: InputEvent) -> void:
	# Atalho rápido de teclado [M] para alternar modo Mobile/Desktop
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.physical_keycode == KEY_M or ev.physical_keycode == KEY_F1):
		var mm = get_node_or_null("/root/MobileManager")
		if mm:
			mm.alternar_controles()
			get_viewport().set_input_as_handled()


func _construir_ui() -> void:
	raiz_ui = Control.new()
	raiz_ui.name = "ControlesTouch"
	raiz_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(raiz_ui)
	
	# 1. D-Pad Virtual (Inferior Esquerdo - visível no mapa e em todos os minigames)
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
	
	# 3. Botão de Interação [E] (Lado Direito)
	btn_acao = VirtualActionButton.new()
	btn_acao.name = "BtnInteragir"
	btn_acao.raio = 17.0
	btn_acao.rotulo = "E"
	btn_acao.acao = "usar"
	btn_acao.position = Vector2(276, 62)
	raiz_ui.add_child(btn_acao)
	
	# 4. Botão de Pausa (Topo Central)
	btn_pausa = _criar_botao_topo(Vector2(134, 4), Vector2(14, 12), "pausa")
	raiz_ui.add_child(btn_pausa)
	
	# 5. Botão de Alternar Celular ↔ Computador (Topo Central, SEMPRE visível)
	btn_toggle = _criar_botao_topo(Vector2(152, 4), Vector2(16, 12), "toggle")
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
				get_tree().create_timer(0.05).timeout.connect(func(): Input.action_release("ui_cancel"))
			elif tipo == "toggle":
				var mm = get_node_or_null("/root/MobileManager")
				if mm:
					mm.alternar_controles()
	)
	
	btn.draw.connect(func():
		var mm = get_node_or_null("/root/MobileManager")
		var touch_ativo: bool = mm.touch_controls_enabled if mm else false
		var r := Rect2(Vector2.ZERO, tam)
		
		var cor_borda := COR_ATIVO if (tipo == "toggle" and touch_ativo) else COR_BORDA_BOTAO
		btn.draw_rect(r, COR_FUNDO_BOTAO)
		btn.draw_rect(r, cor_borda, false, 1.0)
		
		if tipo == "pausa":
			btn.draw_rect(Rect2(4, 3, 2, 6), COR_ICONE)
			btn.draw_rect(Rect2(8, 3, 2, 6), COR_ICONE)
		elif tipo == "toggle":
			if touch_ativo:
				btn.draw_rect(Rect2(5, 2, 6, 8), COR_ATIVO)
				btn.draw_rect(Rect2(6, 3, 4, 6), Color("#090a14"))
				btn.draw_rect(Rect2(7, 8, 2, 1), COR_ATIVO)
			else:
				btn.draw_rect(Rect2(4, 2, 8, 6), COR_ICONE)
				btn.draw_rect(Rect2(5, 3, 6, 4), Color("#090a14"))
				btn.draw_rect(Rect2(6, 8, 4, 1), COR_ICONE)
				btn.draw_rect(Rect2(5, 9, 6, 1), COR_ICONE)
	)
	
	return btn
