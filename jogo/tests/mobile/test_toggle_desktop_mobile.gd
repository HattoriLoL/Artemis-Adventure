extends SceneTree

func _init() -> void:
	print("--- TESTE INICIADO: test_toggle_desktop_mobile.gd ---")
	
	for i in 3:
		await process_frame
		
	var mm = root.get_node_or_null("MobileManager")
	var overlay = root.get_node_or_null("TouchOverlay")
	
	assert(mm != null, "MobileManager deve estar carregado")
	assert(overlay != null, "TouchOverlay deve estar carregado")
	
	# Estado 1: Modo Desktop (padrão em PC)
	mm.touch_controls_enabled = false
	overlay._atualizar_visibilidade_controles()
	
	assert(overlay.dpad.visible == false, "No modo desktop, o D-Pad DEVE estar invisível (sem setas)")
	assert(overlay.btn_acao.visible == false, "No modo desktop, o botão [E] DEVE estar invisível")
	assert(overlay.btn_toggle.visible == true, "O botão de alternar DEVE estar visível para cliques de mouse")
	print("OK: Modo Desktop verificado (setas sumiram, botão de alternância visível)")
	
	# Estado 2: Alterna para Modo Celular (via clique do mouse ou touch)
	mm.alternar_controles()
	assert(mm.touch_controls_enabled == true, "Deveria ter mudado para touch_controls_enabled = true")
	overlay._atualizar_visibilidade_controles()
	
	assert(overlay.dpad.visible == true, "No modo celular, o D-Pad DEVE estar visível")
	assert(overlay.btn_acao.visible == true, "No modo celular, o botão [E] DEVE estar visível")
	print("OK: Modo Celular verificado (setas e botões apareceram)")
	
	# Estado 3: Alterna de volta para Modo Desktop
	mm.alternar_controles()
	assert(mm.touch_controls_enabled == false, "Deveria ter voltado para touch_controls_enabled = false")
	overlay._atualizar_visibilidade_controles()
	
	assert(overlay.dpad.visible == false, "As setas devem sumir novamente")
	assert(overlay.btn_acao.visible == false, "O botão [E] deve sumir novamente")
	print("OK: Retorno ao Modo Desktop verificado com sucesso")
	
	print("--- TESTE CONCLUÍDO COM SUCESSO: test_toggle_desktop_mobile.gd ---")
	quit(0)
