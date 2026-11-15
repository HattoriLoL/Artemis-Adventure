extends Control
## VirtualActionButton: Botão virtual de ação e interação ("usar" / [E]) em pixel art.
## Alimenta a Input Action nativa "usar" com suporte a toque simples, toque contínuo e háptico.

const Fonte = preload("res://scripts/fonte.gd")

const COR_FUNDO := Color("#151d28", 0.75)
const COR_FUNDO_PRESS := Color("#cf573c", 0.90)
const COR_BORDA := Color("#cf573c", 1.0) # Borda vermelha característica de tecla de ação
const COR_BORDA_PRESS := Color("#f2b134", 1.0)
const COR_TEXTO := Color("#ebede9")
const COR_TEXTO_PRESS := Color("#090a14")

@export var raio: float = 16.0
@export var rotulo: String = "E"
@export var acao: String = "usar"

var touch_id := -1
var pressionado := false


func _ready() -> void:
	custom_minimum_size = Vector2(raio * 2 + 4, raio * 2 + 4)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _exit_tree() -> void:
	_liberar()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			_liberar()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed and touch_id == -1:
			touch_id = ev.index
			_pressionar()
			accept_event()
		elif not ev.pressed and ev.index == touch_id:
			_liberar()
			accept_event()
	elif ev is InputEventScreenDrag and ev.index == touch_id:
		# Se arrastar o dedo para fora do raio do botão, libera a ação
		var centro := size / 2.0
		if (ev.position - centro).length() > (raio * 1.6):
			_liberar()
			accept_event()
	# Suporte a mouse para testes no PC
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed and touch_id == -1:
				touch_id = 999
				_pressionar()
				accept_event()
			elif not ev.pressed and touch_id == 999:
				_liberar()
				accept_event()


func _pressionar() -> void:
	if not pressionado:
		pressionado = true
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
		Input.action_press(acao)
		
		# Feedback tátil sutil em mobile
		if Engine.has_singleton("MobileManager") or get_node_or_null("/root/MobileManager"):
			var mm = get_node_or_null("/root/MobileManager")
			if mm and mm.has_method("vibrar"):
				mm.vibrar(20)
				
		queue_redraw()


func _liberar() -> void:
	if pressionado:
		pressionado = false
		touch_id = -1
		if InputMap.has_action(acao):
			Input.action_release(acao)
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := raio
	var rect_botao := Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0)
	
	# Fundo do botão circular/octogonal em pixel art
	var fundo := COR_FUNDO_PRESS if pressionado else COR_FUNDO
	var borda := COR_BORDA_PRESS if pressionado else COR_BORDA
	
	# Desenho com cantos cortados (estilo sci-fi retrô)
	draw_rect(rect_botao.grow(-2), fundo)
	draw_rect(rect_botao, borda, false, 1.0)
	
	# Borda interna de relevo
	draw_rect(rect_botao.grow(-1), borda.darkened(0.2) if not pressionado else borda.lightened(0.2), false, 1.0)
	
	# Letra da tecla [E] centralizada
	var y_off := 1.0 if pressionado else 0.0
	var cor_txt := COR_TEXTO_PRESS if pressionado else COR_TEXTO
	var x_pos := c.x
	var y_pos := c.y - 2.5 + y_off
	Fonte.centralizado(self, rotulo, x_pos, y_pos, cor_txt)
