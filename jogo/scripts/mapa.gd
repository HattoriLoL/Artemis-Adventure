extends Node2D
## O mapa principal: as 5 salas ligadas por túneis pressurizados, com portas que igualam a pressão antes de abrir.
## Dados em res://mapa/mapa.json e res://salas/<sala>.json.
##   -- --demo   o astronauta faz todas as tarefas sozinho, sala por sala (e o jogo fecha no fim, para gravar vídeo)

const Fonte = preload("res://scripts/fonte.gd")
const Porta = preload("res://scripts/porta.gd")
const AMARELO := Color("#e8c170")
const BRANCO := Color("#ebede9")
const CINZA := Color("#819796")
const VERDE := Color("#75a743")

var mapa: Dictionary
var salas := {}                    # nome -> {"dados": ..., "pos": Vector2}
var tarefas := []                  # {"sala", "id", "texto", "pos"}
var interacoes := []               # {"sala", "id", "texto", "acao", "pos"}
var feitas := {}
var usadas := {}
var portas := []
var marcas := {}
var jogador: CharacterBody2D
var hud: Control
var aviso := ""
var t_aviso := 0.0
var demo := false
var t := 0.0
var escuro := 0.0
var dormindo := false
var sala_atual := ""
var fim := false
var minigame: Control = null       # minigame aberto agora (veja README_MINIGAMES.md)

# robô do modo demo: anda pelo caminho da grade de navegação
var astar: AStarGrid2D
var celula := 4
var caminho := PackedVector2Array()
var i_caminho := 0
var alvo_demo := {}
var t_recalcular := 0.0


func _ready() -> void:
	_entradas()
	demo = "--demo" in OS.get_cmdline_user_args()
	mapa = JSON.parse_string(FileAccess.open("res://mapa/mapa.json", FileAccess.READ).get_as_text())
	# o regolito no fundo e, por cima, os túneis em tiles (editáveis no editor do Godot)
	var fundo := Sprite2D.new()
	fundo.centered = false
	fundo.z_index = -21
	fundo.texture = load("res://assets/mapa/regolito.png")
	add_child(fundo)
	var tun: Node2D = load("res://mapa/tuneis_tiles.tscn").instantiate()
	tun.z_index = -20
	add_child(tun)
	var corpo := StaticBody2D.new()
	add_child(corpo)
	for r in mapa["solidos"]:
		_ret(corpo, r, Vector2.ZERO)
	for s in mapa["salas"]:
		_sala(s["nome"], Vector2(s["pos"][0], s["pos"][1]), corpo)
	_jogador()
	for p in mapa["portas"]:
		var porta := Porta.new()
		porta.dados = p
		var tex: String = p.get("textura", str(salas[p["sala"]]["dados"]["png"]) if salas.has(p["sala"]) else "")
		porta.textura = load(tex)
		porta.alvo = jogador
		add_child(porta)
		portas.append(porta)
	_navegacao()
	_interface()
	_avisar("BASE LUNAR")


func _entradas() -> void:
	var m := {"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT], "cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN], "andar": [KEY_SHIFT], "usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]}
	for acao in m:
		if InputMap.has_action(acao):
			continue
		InputMap.add_action(acao)
		for k in m[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(acao, ev)


func _ret(corpo: StaticBody2D, r: Array, off: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(r[2], r[3])
	cs.shape = sh
	cs.position = off + Vector2(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0)
	corpo.add_child(cs)


func _sala(nome: String, pos: Vector2, corpo: StaticBody2D) -> void:
	var dados: Dictionary = JSON.parse_string(FileAccess.open("res://salas/%s.json" % nome, FileAccess.READ).get_as_text())
	salas[nome] = {"dados": dados, "pos": pos}
	var tiles := "res://salas/%s_tiles.tscn" % nome
	var fundo: Node2D
	if ResourceLoader.exists(tiles):
		fundo = load(tiles).instantiate()
	else:
		fundo = Sprite2D.new()
		fundo.texture = load(dados["png"])
		fundo.centered = false
	fundo.position = pos
	fundo.z_index = -10
	add_child(fundo)
	for r in dados["solidos"]:
		_ret(corpo, r, pos)
	for tf in dados["tarefas"]:
		var item := {"sala": nome, "id": nome + "/" + str(tf["id"]), "texto": tf["texto"],
			"pos": pos + Vector2(tf["x"], tf["y"]), "minigame": str(tf.get("minigame", ""))}
		tarefas.append(item)
		var m := Polygon2D.new()                     # seta amarela pulando sobre a tarefa (como no Among Us)
		m.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(0, 4)])
		m.color = AMARELO
		m.position = item["pos"] + Vector2(0, -44)
		m.z_index = 5
		add_child(m)
		marcas[item["id"]] = m
	for it in dados.get("interacoes", []):
		interacoes.append({"sala": nome, "id": nome + "/" + str(it["id"]), "texto": it["texto"],
			"acao": it.get("acao", ""), "pos": pos + Vector2(it["x"], it["y"])})


func _jogador() -> void:
	jogador = preload("res://scripts/jogador_topo.gd").new()
	jogador.frames_res = "res://assets/astronauta/astronauta_topo_frames.tres"
	jogador.poeira_cores = ["#819796", "#a8b5b2"]
	jogador.position = Vector2(mapa["inicio"][0], mapa["inicio"][1])
	jogador.demo = demo
	jogador.sem_desvio = true                  # o caminho já desvia; parado numa porta, ele só espera ela abrir
	add_child(jogador)
	var cam := Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(mapa["tamanho"][0])
	cam.limit_bottom = int(mapa["tamanho"][1])
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	cam.offset = Vector2(0, -14)
	jogador.add_child(cam)
	cam.make_current()


func _navegacao() -> void:
	var img: Image = load(mapa["navegacao"]).get_image()
	celula = int(mapa["celula"])
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, img.get_width(), img.get_height())
	astar.cell_size = Vector2(celula, celula)
	astar.offset = Vector2(celula / 2.0, celula / 2.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).r < 0.5:
				astar.set_point_solid(Vector2i(x, y))


func _interface() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Control.new()
	hud.size = Vector2(320, 180)
	hud.draw.connect(_desenha_hud)
	cl.add_child(hud)


func _avisar(txt: String) -> void:
	aviso = txt
	t_aviso = 2.2


func _sala_de(pos: Vector2) -> String:
	for nome in salas:
		var tam: Array = salas[nome]["dados"]["tamanho"]
		if Rect2(salas[nome]["pos"], Vector2(tam[0], tam[1])).has_point(pos):
			return nome
	return ""


func _perto(lista: Array, feito: Dictionary) -> Dictionary:
	var melhor := {}
	var dist := 20.0
	for item in lista:
		if feito.has(item["id"]) and lista == tarefas:
			continue
		var d := jogador.global_position.distance_to(item["pos"])
		if d < dist:
			dist = d
			melhor = item
	return melhor


func _process(delta: float) -> void:
	t += delta
	t_aviso = max(0.0, t_aviso - delta)
	for id in marcas:
		var item := _tarefa(id)
		marcas[id].position.y = item["pos"].y - 44 + round(sin(t * 5.0) * 1.5)
	var agora := _sala_de(jogador.global_position)
	if agora != sala_atual:
		sala_atual = agora
		if agora != "" and t > 0.5:
			_avisar(str(salas[agora]["dados"].get("titulo", agora)))
	var tf := _perto(tarefas, feitas)
	var it := _perto(interacoes, usadas)
	if demo:
		_demo(delta)
	if minigame != null:
		jogador.t_usar = 0.1                   # astronauta parado enquanto o minigame está aberto
	elif dormindo:
		pass
	elif not tf.is_empty() and (Input.is_action_just_pressed("usar") or (demo and _bot_usa(tf))):
		_usar(tf)
	elif not it.is_empty() and (Input.is_action_just_pressed("usar") or (demo and _bot_usa(it))):
		_interagir(it)
	elif Input.is_action_just_pressed("usar"):
		for p in portas:
			if p.trancada() and p.perto(jogador.global_position):
				p.negar()
				_avisar(str(p.dados.get("aviso", "PORTA TRANCADA")))
	hud.queue_redraw()


func _tarefa(id: String) -> Dictionary:
	for item in tarefas:
		if item["id"] == id:
			return item
	return {}


func _usar(tf: Dictionary) -> void:
	if tf["minigame"] == "":
		_concluir(tf)
		return
	if not ResourceLoader.exists(tf["minigame"]):
		push_error("Minigame nao encontrado: " + tf["minigame"])
		_concluir(tf)
		return
	# a tarefa tem minigame: abre a cena por cima do jogo e só conclui quando ela avisar que terminou
	minigame = load(tf["minigame"]).instantiate()
	minigame.demo = demo
	minigame.terminou.connect(func():
		minigame.queue_free()
		minigame = null
		_concluir(tf))
	hud.get_parent().add_child(minigame)


func _concluir(tf: Dictionary) -> void:
	jogador.usar()
	feitas[tf["id"]] = true
	marcas[tf["id"]].visible = false
	_avisar("FEITO: " + str(tf["texto"]))
	var sala: String = tf["sala"]
	var faltam := tarefas.filter(func(x): return x["sala"] == sala and not feitas.has(x["id"]))
	if faltam.is_empty():
		await get_tree().create_timer(1.2).timeout
		_avisar(str(salas[sala]["dados"].get("concluida", "SALA EM DIA")))
	if feitas.size() == tarefas.size():
		await get_tree().create_timer(2.4).timeout
		_avisar("BASE EM ORDEM")
		t_aviso = 999.0
		_demo_fim()


func _interagir(it: Dictionary) -> void:
	usadas[it["id"]] = true
	if it["acao"] == "dormir":
		dormindo = true
		jogador.t_usar = 3.6
		jogador.spr.play("idle_down")
		var tw := create_tween()
		tw.tween_property(self, "escuro", 1.0, 0.8)
		tw.tween_interval(1.8)
		tw.tween_property(self, "escuro", 0.0, 0.8)
		await tw.finished
		dormindo = false
		_avisar("DESCANSADO")
		_demo_fim()


# ---------------------------------------------------------------- modo demo
func _bot_usa(item: Dictionary) -> bool:
	return not alvo_demo.is_empty() and alvo_demo["id"] == item["id"] and jogador.bot_quer_usar(item)


func _proximo_alvo() -> Dictionary:
	for sala in mapa["ordem_demo"]:
		for item in tarefas:
			if item["sala"] == sala and not feitas.has(item["id"]):
				return item
		for item in interacoes:
			if item["sala"] == sala and not usadas.has(item["id"]):
				return item
	return {}


func _demo(delta: float) -> void:
	if fim:
		return
	var alvo := _proximo_alvo()
	if alvo.is_empty():
		jogador.bot_alvo = Vector2.INF
		return
	t_recalcular -= delta
	if alvo_demo.is_empty() or alvo["id"] != alvo_demo["id"] or t_recalcular <= 0.0:
		alvo_demo = alvo
		t_recalcular = 3.0
		var de := Vector2i(jogador.global_position / celula)
		var para := Vector2i(alvo["pos"] / celula)
		para = _livre_perto(para)
		de = _livre_perto(de)
		caminho = astar.get_point_path(de, para)
		i_caminho = 0
	# segue o caminho olhando um pouco à frente; a última parada é a própria tarefa
	while i_caminho < caminho.size() - 1 and jogador.global_position.distance_to(caminho[i_caminho]) < 24.0:
		i_caminho += 1
	if caminho.is_empty() or i_caminho >= caminho.size() - 1:
		jogador.bot_alvo = alvo["pos"]
	else:
		jogador.bot_alvo = caminho[i_caminho]


func _livre_perto(c: Vector2i) -> Vector2i:
	if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
		return c
	for r in range(1, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(n) and not astar.is_point_solid(n):
					return n
	return c


func _demo_fim() -> void:
	if not demo or feitas.size() < tarefas.size() or usadas.size() < interacoes.size():
		return
	fim = true
	await get_tree().create_timer(2.5).timeout
	get_tree().quit()


# ---------------------------------------------------------------- interface
func _desenha_hud() -> void:
	var lista := []
	var titulo := "TUNEL"
	if sala_atual != "":
		titulo = str(salas[sala_atual]["dados"].get("titulo", sala_atual))
		lista = tarefas.filter(func(x): return x["sala"] == sala_atual)
	var largura := 104.0
	largura = max(largura, Fonte.largura(titulo) + 14)
	for tf in lista:
		largura = max(largura, Fonte.largura(str(tf["texto"])) + 14)
	var linhas := lista.size() + 2
	hud.draw_rect(Rect2(4, 3, largura, 2 + 8 * linhas), Color(0.035, 0.04, 0.08, 0.7))
	var y := 6
	Fonte.desenhar(hud, titulo, Vector2(8, y), AMARELO)
	for tf in lista:
		y += 8
		var feito := feitas.has(tf["id"])
		hud.draw_rect(Rect2(8, y + 1, 3, 3), VERDE if feito else CINZA)
		Fonte.desenhar(hud, str(tf["texto"]), Vector2(14, y), CINZA if feito else BRANCO)
	y += 8
	Fonte.desenhar(hud, "BASE %d/%d" % [feitas.size(), tarefas.size()], Vector2(8, y), CINZA)
	var tf := _perto(tarefas, feitas)
	if tf.is_empty():
		tf = _perto(interacoes, usadas)
	if not tf.is_empty() and not dormindo and minigame == null:
		Fonte.centralizado(hud, "E: " + str(tf["texto"]), 160, 160, AMARELO)
	if escuro > 0.0:
		hud.draw_rect(Rect2(0, 0, 320, 180), Color(0.02, 0.02, 0.05, escuro))
		var zs := "Z" + " Z".repeat(int(t * 2.0) % 3)
		Fonte.centralizado(hud, zs, 160, 86, Color(BRANCO, escuro))
	if t_aviso > 0.0 and escuro < 0.3:
		var w := Fonte.largura(aviso) + 8
		hud.draw_rect(Rect2(160 - w / 2.0, 54, w, 11), Color(0.035, 0.04, 0.08, 0.8))
		Fonte.centralizado(hud, aviso, 160, 57, BRANCO)
