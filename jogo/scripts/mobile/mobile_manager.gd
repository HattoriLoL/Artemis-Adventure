extends Node
## MobileManager: Gerenciador inteligente de detecção de dispositivo e suporte a toque.
## Autoload que identifica celulares, tablets, ambientes Web e telas de toque.
## Permite alternância dinâmica entre modo Teclado/Mouse e Touch Controls sem quebrar o PC.

signal touch_controls_toggled(enabled: bool)
signal input_mode_changed(mode: String)
signal controls_minimized_changed(minimized: bool)

## Propriedades de detecção de plataforma
var is_mobile := false
var has_touch := false
var is_web := false
var is_hybrid_device := false

## Estado dos controles virtuais
var touch_controls_enabled := false:
	set(valor):
		if touch_controls_enabled != valor:
			touch_controls_enabled = valor
			touch_controls_toggled.emit(touch_controls_enabled)

var controls_minimized := false:
	set(valor):
		if controls_minimized != valor:
			controls_minimized = valor
			controls_minimized_changed.emit(controls_minimized)

## Modo atual: "keyboard" ou "touch"
var input_mode := "keyboard":
	set(valor):
		if input_mode != valor:
			input_mode = valor
			input_mode_changed.emit(input_mode)

## Flag para forçar o overlay de toque mesmo em PC (útil para testes de desenvolvimento e depuração)
var force_touch_for_testing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detectar_plataforma()


func _detectar_plataforma() -> void:
	is_web = OS.has_feature("web")
	
	# Detecção explícita de sistemas móveis (nativos e Web)
	var eh_android: bool = OS.has_feature("android") or OS.has_feature("web_android")
	var eh_ios: bool = OS.has_feature("ios") or OS.has_feature("web_ios")
	is_mobile = eh_android or eh_ios
	
	# Detecção de capacidade touchscreen
	has_touch = DisplayServer.is_touchscreen_available()
	
	# Dispositivo híbrido (ex: notebook touch, tablet com teclado conectado)
	if has_touch and not is_mobile:
		is_hybrid_device = true
	
	# Ativação inicial dos controles
	if is_mobile or (has_touch and not is_hybrid_device) or force_touch_for_testing:
		touch_controls_enabled = true
		input_mode = "touch"
	else:
		touch_controls_enabled = false
		input_mode = "keyboard"
	
	print("[MobileManager] Inicializado: is_mobile=%s, has_touch=%s, is_web=%s, controls_enabled=%s" % [
		is_mobile, has_touch, is_web, touch_controls_enabled
	])


func _unhandled_input(ev: InputEvent) -> void:
	# Observador dinâmico: se houver toque na tela pela primeira vez, ativa modo touch
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		has_touch = true
		if input_mode != "touch":
			input_mode = "touch"
		if not touch_controls_enabled:
			touch_controls_enabled = true
	elif ev is InputEventKey:
		# Se tecla física for usada em dispositivo híbrido, registra modo teclado
		if input_mode != "keyboard":
			input_mode = "keyboard"


## Alterna manualmente a exibição dos controles virtuais
func alternar_controles() -> void:
	touch_controls_enabled = not touch_controls_enabled


## Alterna o estado minimizado/compacto dos controles
func alternar_minimizado() -> void:
	controls_minimized = not controls_minimized


## Vibração háptica de resposta a botões de toque (se suportada)
func vibrar(ms: int = 25) -> void:
	if is_mobile and Input.has_method("vibrate_handheld"):
		Input.vibrate_handheld(ms)
