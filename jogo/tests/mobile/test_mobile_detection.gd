extends SceneTree

func _init() -> void:
	print("--- TESTE INICIADO: test_mobile_detection.gd ---")
	
	# Aguarda inicialização do SceneTree
	for i in 3:
		await process_frame
		
	var mm = root.get_node_or_null("MobileManager")
	assert(mm != null, "Autoload MobileManager deve estar presente no root")
	
	# Verifica propriedades iniciais
	assert(mm.input_mode in ["keyboard", "touch"], "input_mode deve ser 'keyboard' ou 'touch'")
	print("OK: Detecção inicial de input_mode = ", mm.input_mode)
	
	# Testa sinal ao alternar controles usando array para captura em lambda
	var flag_toggle := [false]
	mm.touch_controls_toggled.connect(func(habilitado: bool):
		flag_toggle[0] = true
		print("OK: Sinal touch_controls_toggled recebido com valor: ", habilitado)
	)
	
	var estado_antes: bool = mm.touch_controls_enabled
	mm.alternar_controles()
	assert(flag_toggle[0], "Sinal touch_controls_toggled deveria ter sido emitido")
	assert(mm.touch_controls_enabled == not estado_antes, "touch_controls_enabled deveria ter invertido")
	
	# Testa minimizar controles
	var flag_min := [false]
	mm.controls_minimized_changed.connect(func(min: bool):
		flag_min[0] = true
		print("OK: Sinal controls_minimized_changed recebido com valor: ", min)
	)
	mm.alternar_minimizado()
	assert(flag_min[0], "Sinal controls_minimized_changed deveria ter sido emitido")
	assert(mm.controls_minimized == true, "controls_minimized deveria ser true")
	
	print("--- TESTE CONCLUÍDO COM SUCESSO: test_mobile_detection.gd ---")
	quit(0)
