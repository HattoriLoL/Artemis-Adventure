extends SceneTree

func _init() -> void:
	print("--- TESTE INICIADO: test_minigame_touch.gd ---")
	
	var overlay = load("res://cenas/mobile/touch_overlay.tscn").instantiate()
	root.add_child(overlay)
	
	for i in 5:
		await process_frame
		
	assert(overlay.dpad != null, "D-Pad deve estar instanciado")
	assert(overlay.btn_acao != null, "Botão Ação deve estar instanciado")
	assert(overlay.btn_pausa != null, "Botão Pausa deve estar instanciado")
	print("OK: Componentes do TouchOverlay instanciados corretamente")
	
	# Simula entrada em minigame
	overlay.definir_modo_minigame(true)
	assert(overlay.dpad.visible == false, "D-Pad deve ser recolhido durante minigames para desobstruir a tela")
	assert(overlay.btn_acao.visible == true, "Botão [E] deve continuar visível para minigames que precisam de interação")
	print("OK: Modo minigame ativo validado (D-Pad oculto, Ação visível)")
	
	# Simula saída de minigame
	overlay.definir_modo_minigame(false)
	assert(overlay.dpad.visible == true, "D-Pad deve reaparecer ao sair do minigame")
	print("OK: Retorno do minigame validado")
	
	overlay.queue_free()
	print("--- TESTE CONCLUÍDO COM SUCESSO: test_minigame_touch.gd ---")
	quit(0)
