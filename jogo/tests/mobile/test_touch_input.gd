extends SceneTree

func _init() -> void:
	print("--- TESTE INICIADO: test_touch_input.gd ---")
	
	# Garante que as ações existem
	for acao in ["cima", "baixo", "esquerda", "direita", "correr", "usar"]:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			
	var dpad = load("res://scripts/mobile/virtual_dpad.gd").new()
	dpad.size = Vector2(56, 56)
	root.add_child(dpad)
	
	var btn = load("res://scripts/mobile/virtual_action_button.gd").new()
	btn.size = Vector2(40, 40)
	btn.acao = "usar"
	root.add_child(btn)
	
	for i in 5:
		await process_frame
		
	# 1. Simula toque para cima no D-Pad (centro x=28, y=10)
	var ev_up := InputEventScreenTouch.new()
	ev_up.index = 0
	ev_up.pressed = true
	ev_up.position = Vector2(28, 10)
	dpad._gui_input(ev_up)
	
	assert(Input.is_action_pressed("cima"), "Ação 'cima' deveria estar pressionada")
	assert(not Input.is_action_pressed("baixo"), "Ação 'baixo' NÃO deveria estar pressionada")
	print("OK: D-Pad toque CIMA validado com sucesso")
	
	# 2. Simula liberação do toque no D-Pad
	var ev_release := InputEventScreenTouch.new()
	ev_release.index = 0
	ev_release.pressed = false
	ev_release.position = Vector2(28, 10)
	dpad._gui_input(ev_release)
	
	assert(not Input.is_action_pressed("cima"), "Ação 'cima' deve ser liberada imediatamente (sem movimento fantasma)")
	print("OK: D-Pad liberação limpa (zero ghost movement)")
	
	# 3. Simula diagonal (Cima + Direita, x=45, y=10)
	var ev_diag := InputEventScreenTouch.new()
	ev_diag.index = 0
	ev_diag.pressed = true
	ev_diag.position = Vector2(45, 10)
	dpad._gui_input(ev_diag)
	
	assert(Input.is_action_pressed("cima") and Input.is_action_pressed("direita"), "Ambas ações 'cima' e 'direita' devem estar ativas")
	print("OK: D-Pad movimentação diagonal (Cima + Direita) validada")
	
	ev_diag.pressed = false
	dpad._gui_input(ev_diag)
	assert(not Input.is_action_pressed("cima") and not Input.is_action_pressed("direita"), "Diagonal liberada perfeitamente")
	
	# 4. Simula toque no Botão de Ação [E]
	var ev_btn := InputEventScreenTouch.new()
	ev_btn.index = 1
	ev_btn.pressed = true
	ev_btn.position = Vector2(20, 20)
	btn._gui_input(ev_btn)
	
	assert(Input.is_action_pressed("usar"), "Ação 'usar' deve estar pressionada ao tocar no botão")
	print("OK: Botão [E] toque pressionado validado")
	
	ev_btn.pressed = false
	btn._gui_input(ev_btn)
	assert(not Input.is_action_pressed("usar"), "Ação 'usar' deve ser liberada ao soltar o dedo")
	print("OK: Botão [E] liberação validada com sucesso")
	
	dpad.queue_free()
	btn.queue_free()
	print("--- TESTE CONCLUÍDO COM SUCESSO: test_touch_input.gd ---")
	quit(0)
