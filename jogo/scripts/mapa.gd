extends Node2D
## O mapa principal: as 5 salas ligadas por túneis pressurizados, com portas que igualam a pressão antes de abrir.
## Dados em res://mapa/mapa.json e res://salas/<sala>.json.
##   -- --demo   o astronauta faz todas as tarefas sozinho, sala por sala (e o jogo fecha no fim, para gravar vídeo)

const Fonte = preload("res://scripts/fonte.gd")
const Porta = preload("res://scripts/porta.gd")
const MenuPausa = preload("res://scripts/menu_pausa.gd")
const CicloDias = preload("res://scripts/ciclo_dias.gd")
const AMARELO := Color("#e8c170")
const BRANCO := Color("#ebede9")
const CINZA := Color("#819796")
const VERDE := Color("#75a743")
const VERMELHO := Color("#cf573c")
const ESCURO := Color("#394a50")
const AZUL := Color("#73bed3")
const SEM_SOL := "NO SUN TODAY: NO EFFECT"
# planta da base (arte do PixelAi, ver arte/minimapa.py) em dois tamanhos: o minimapa do canto de baixo à direita e o
# mapa da tecla M. A imagem cobre o retângulo PLANTA_ORIGEM + PLANTA_TAM do mapa (salas e túneis), em qualquer tamanho
const TEX_MINIMAPA := preload("res://assets/mapa/minimapa_grande.png")    # 74x90 (o de 53x64 é minimapa.png)
const TEX_MAPA_TELA := preload("res://assets/mapa/mapa_tela.png")        # 132x160
const PLANTA_ORIGEM := Vector2(40, 40)
const PLANTA_TAM := Vector2(944, 1146)
const TELA_POS := Vector2(10, 13)                                       # canto do mapa da tecla M
const CONTORNO := Color("#090a14")
# a parede de baixo de cada sala e a verga da porta de cima ficam fora do fundo da sala: entram no Y-sort do mapa
# junto com o astronauta, então ele passa atrás delas (antes ele ficava em cima da parede na porta de baixo)
const TEX_PAREDE := preload("res://assets/mapa/parede.png")
const TEX_VERGA := preload("res://assets/mapa/verga.png")
const PAREDE_POS := Vector2(5, 181)        # canto da parede de baixo na sala; a base dela é a borda de baixo da sala
const VERGA_POS := Vector2(176, 0)         # a verga em cima do vão da porta de cima
const VERGA_BASE := 48.0                   # pé do astronauta acima disto (dentro do vão): a verga passa na frente
const TEMPO_CONFIRMAR := 3.0       # quanto tempo o "E AGAIN: END THE DAY NOW" espera o segundo E
const TEMPO_DESISTIR := 2.5        # quanto tempo o "ESC OR X AGAIN: GIVE UP" espera a segunda vez

var mapa: Dictionary
var salas := {}                    # nome -> {"dados": ..., "pos": Vector2}
var tarefas := []                  # {"sala", "id", "texto", "pos"}
var interacoes := []               # {"sala", "id", "texto", "acao", "pos"}
var feitas := {}
var usadas := {}
var portas := []
var obstaculos: Array[Rect2] = []  # colisão dos objetos soltos das salas (o robô do demo desvia deles)
var marcas := {}
var jogador: CharacterBody2D
var hud: Control
var camada_ui: CanvasLayer
var ciclo: CicloDias               # ciclo_dias.gd: dias, ações, boletim, noite e fim da missão
var em_minigame := false
var mapa_aberto := false           # o mapa grande da tecla M
var desistir := 0.0                # > 0: o jogador tentou fechar um minigame já começado; de novo = desiste (falha)
var quadro_desistir := -1          # quadro do primeiro pedido (Esc e clique no X no mesmo quadro não confirmam)
var aviso_desistir: Control        # o aviso por cima do minigame
var quadro_fechou_minigame := -1   # o Esc que fecha o minigame não pode abrir o menu de pausa no mesmo quadro
var aviso := ""
var t_aviso := 0.0
var demo := false
var t := 0.0
var escuro := 0.0
var dormindo := false
var confirmar_dormir := 0.0        # > 0: o jogador apertou E na cama com ações sobrando; outro E encerra o dia
var sala_atual := ""
var fim := false
var variacoes := {}                # indicador -> [quanto mudou, tempo na tela]: o "+15" ao lado da barra

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
	y_sort_enabled = true                          # astronauta x paredes da frente: quem tem o pé mais embaixo fica na frente
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
	Recursos.iniciar()                             # começa com as condições do local de pouso
	Recursos.mudou.connect(_recursos_mudaram)
	ciclo.noite_fechou.connect(_amanhecer)
	ciclo.iniciar()                                # dia 1: boletim da manhã


func _entradas() -> void:
	var m := {"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT], "cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN], "correr": [KEY_SHIFT], "usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER], "mapa": [KEY_M]}
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
	var tam := Vector2(dados["tamanho"][0], dados["tamanho"][1])
	_na_frente(TEX_PAREDE, pos + PAREDE_POS, pos.y + tam.y)
	_na_frente(TEX_VERGA, pos + VERGA_POS, pos.y + VERGA_BASE)
	for r in dados["solidos"]:
		_ret(corpo, r, pos)
	for ob in dados.get("objetos", []):
		_objeto(ob, pos, corpo)
	for tf in dados["tarefas"]:
		var item := {"sala": nome, "id": nome + "/" + str(tf["id"]), "texto": tf["texto"],
			"pos": pos + Vector2(tf["x"], tf["y"]), "minigame": str(tf.get("minigame", "")),
			"icone": _icone(nome + "/" + str(tf["id"]))}
		tarefas.append(item)
		var m := Polygon2D.new()                     # seta amarela pulando sobre a tarefa (como no Among Us)
		m.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(0, 4)])
		m.color = AMARELO
		m.position = item["pos"] + Vector2(0, -44)
		m.z_index = 5
		add_child(m)
		marcas[item["id"]] = m
	for it in dados.get("interacoes", []):
		var item := {"sala": nome, "id": nome + "/" + str(it["id"]), "texto": it["texto"],
			"acao": it.get("acao", ""), "pos": pos + Vector2(it["x"], it["y"])}
		if it.has("acordar"):                        # cama: onde o astronauta aparece de manhã (fora do alcance do E)
			item["acordar"] = pos + Vector2(it["acordar"][0], it["acordar"][1])
		interacoes.append(item)


## Ícone 7x7 da tarefa (lista do HUD e minimapa): res://assets/icones/<sala>_<tarefa>.png. Sem arquivo, null (a
## lista volta ao quadradinho e o minimapa à cruz amarela). Desenhados em arte/icones_tarefas.py.
func _icone(id: String) -> Texture2D:
	var c := "res://assets/icones/%s.png" % id.replace("/", "_")
	return load(c) if ResourceLoader.exists(c) else null


## Sprite que entra no Y-sort pela linha `base` (onde ele toca o chão), desenhado com o canto em `canto`.
func _na_frente(tex: Texture2D, canto: Vector2, base: float) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = Vector2(canto.x, base)
	s.offset = Vector2(0, canto.y - base)
	add_child(s)


## Objeto solto na sala (ex.: o chuveiro do Habitat), fora do desenho do fundo: entra no Y-sort pela linha em que
## toca o chão, então o astronauta passa atrás e na frente dele. No JSON da sala, em "objetos":
##   "png"     a imagem (fundo transparente, na escala do jogo)
##   "x", "y"  canto de cima à esquerda da imagem na sala
##   "base"    linha da imagem onde ele toca o chão (padrão: a última)
##   "solido"  colisão [x, y, w, h] relativa ao canto (padrão: os 8 px de baixo da imagem)
func _objeto(ob: Dictionary, pos: Vector2, corpo: StaticBody2D) -> void:
	var tex: Texture2D = load(str(ob["png"]))
	var canto := pos + Vector2(ob["x"], ob["y"])
	var base := float(ob.get("base", tex.get_height()))
	_na_frente(tex, canto, canto.y + base)
	var r: Array = ob.get("solido", [0, base - 8, tex.get_width(), 8])
	_ret(corpo, r, canto)
	obstaculos.append(Rect2(canto.x + r[0], canto.y + r[1], r[2], r[3]))


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
	# câmera presa no astronauta, sem suavização: com a suavização, câmera e astronauta caíam em frações de pixel
	# diferentes e o arredondamento fazia o astronauta tremer 1 px na tela (ver physics_interpolation no projeto)
	cam.position_smoothing_enabled = false
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
	# os objetos soltos não estão na imagem da grade: fecha as células em que os pés (12x6, com folga) bateriam neles
	for r in obstaculos:
		for cy in range(floori(r.position.y / celula) - 1, floori((r.end.y + 8) / celula) + 1):
			for cx in range(floori((r.position.x - 8) / celula), floori((r.end.x + 8) / celula) + 1):
				var pe := Vector2(cx * celula + celula / 2.0, cy * celula + celula / 2.0)
				if astar.is_in_boundsv(Vector2i(cx, cy)) and Rect2(pe.x - 8, pe.y - 8, 16, 10).intersects(r):
					astar.set_point_solid(Vector2i(cx, cy))


func _interface() -> void:
	camada_ui = CanvasLayer.new()
	add_child(camada_ui)
	hud = Control.new()
	hud.size = Vector2(320, 180)
	hud.draw.connect(_desenha_hud)
	camada_ui.add_child(hud)
	aviso_desistir = Control.new()
	aviso_desistir.size = Vector2(320, 180)
	aviso_desistir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aviso_desistir.visible = false
	aviso_desistir.draw.connect(_desenha_aviso_desistir)
	camada_ui.add_child(aviso_desistir)
	ciclo = CicloDias.new()
	ciclo.mapa = self
	add_child(ciclo)
	var menu := MenuPausa.new()                   # Esc; fica por último na árvore para ver o Esc antes do minigame
	menu.mapa = self
	add_child(menu)


func pode_pausar() -> bool:
	return not em_minigame and not fim and not mapa_aberto and Engine.get_process_frames() != quadro_fechou_minigame


func _avisar(txt: String) -> void:
	aviso = txt
	t_aviso = 2.2


## Painel do ciclo aberto (boletim, noite, fim): o astronauta para e o E fica com o painel.
func travar(v: bool) -> void:
	jogador.velocity = Vector2.ZERO
	jogador.set_physics_process(not v)


## Começo de cada dia (chamado pelo ciclo): as tarefas de ontem voltam a poder ser feitas, se forem oferecidas.
func novo_dia() -> void:
	feitas.clear()
	usadas.clear()
	_atualizar_marcas()


## Aba DEV: refaz o dia (tarefas e ações).
func zerar_dia() -> void:
	ciclo.zerar_dia()
	novo_dia()


## A seta amarela só aparece nas tarefas que dá para fazer agora.
func _atualizar_marcas() -> void:
	for id in marcas:
		marcas[id].visible = ciclo.disponivel(id) and not feitas.has(id)


func _recursos_mudaram(_id: String, mudancas: Dictionary) -> void:
	for nome in mudancas:
		variacoes[nome] = [mudancas[nome], 2.0]


## O que a tarefa rende, em texto para o HUD e o boletim. Uma tarefa de energia solar à noite não rende nada.
func texto_previa(id: String) -> String:
	var txt := _texto_efeito(Recursos.previa(id))
	if txt == "" and Recursos.noite and not Recursos.regras["efeitos"].get(id, {}).is_empty():
		return SEM_SOL
	return txt


## {"comida": -5, "condicao": 10} -> "-5 FOOD +10 HEALTH"
func _texto_efeito(efeito: Dictionary) -> String:
	var partes := PackedStringArray()
	for nome in Recursos.NOMES:
		if efeito.has(nome) and roundi(efeito[nome]) != 0:
			partes.append("%+d %s" % [roundi(efeito[nome]), Recursos.ROTULOS[nome]])
	return " ".join(partes)


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
		if lista == tarefas and (feito.has(item["id"]) or not ciclo.disponivel(item["id"])):
			continue
		var d := jogador.global_position.distance_to(item["pos"])
		if d < dist:
			dist = d
			melhor = item
	return melhor


func _process(delta: float) -> void:
	t += delta
	t_aviso = max(0.0, t_aviso - delta)
	confirmar_dormir = max(0.0, confirmar_dormir - delta)
	desistir = max(0.0, desistir - delta)
	aviso_desistir.visible = em_minigame and desistir > 0.0
	if aviso_desistir.visible:
		aviso_desistir.queue_redraw()
	for nome in variacoes.keys():
		variacoes[nome][1] -= delta
		if variacoes[nome][1] <= 0.0:
			variacoes.erase(nome)
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
	if mapa_aberto:
		if Input.is_action_just_pressed("mapa") or Input.is_action_just_pressed("ui_cancel"):
			mapa_aberto = false
			travar(false)
	elif dormindo or em_minigame or fim or ciclo.ocupado() or escuro > 0.0:
		pass
	elif Input.is_action_just_pressed("mapa") and not demo:
		mapa_aberto = true
		travar(true)
	elif not tf.is_empty() and (Input.is_action_just_pressed("usar") or (demo and _bot_usa(tf))):
		_usar(tf)
	elif not it.is_empty() and (Input.is_action_just_pressed("usar") or (demo and _bot_usa(it))):
		_interagir(it)
	elif Input.is_action_just_pressed("usar"):
		for p in portas:
			if p.trancada() and p.perto(jogador.global_position):
				p.negar()
				_avisar(str(p.dados.get("aviso", "DOOR LOCKED")))
	hud.queue_redraw()


func _tarefa(id: String) -> Dictionary:
	for item in tarefas:
		if item["id"] == id:
			return item
	return {}


func _usar(tf: Dictionary) -> void:
	if tf.get("minigame", "") != "":
		abrir_minigame(tf["minigame"], tf)
		return
	if tf["id"] == "estufa/regar":
		abrir_minigame("res://cenas/minigame_estufa.tscn", tf)
		return
	if tf["id"] == "suporte/gas":
		abrir_minigame("res://cenas/minigame_swap_co2.tscn", tf)
		return
	_concluir_tarefa(tf)


## Abre um minigame por cima do jogo. Com `tf` vazio (aba DEV do menu de pausa), terminar não conclui tarefa nenhuma.
func abrir_minigame(caminho: String, tf := {}) -> void:
	em_minigame = true
	hud.visible = false
	jogador.velocity = Vector2.ZERO
	jogador.set_physics_process(false)
	var cena_mg: PackedScene = load(caminho)
	var mg: Control = cena_mg.instantiate()
	mg.demo = demo
	camada_ui.add_child(mg)
	camada_ui.move_child(aviso_desistir, -1)       # o aviso de desistir fica por cima do minigame
	desistir = 0.0
	# terminou: a tarefa rende conforme os erros (o minigame diz a taxa em taxa_erro(), de 0 a 1; sem ela, 0)
	mg.terminou.connect(func():
		var taxa := clampf(float(mg.taxa_erro()), 0.0, 1.0) if mg.has_method("taxa_erro") else 0.0
		_fechar_minigame(mg)
		if not tf.is_empty():
			_concluir_tarefa(tf, Recursos.fator_erro(taxa))
	)
	# falhou (errou demais, ou desistiu depois de começar): a tarefa é perdida, gasta a ação do dia e não rende nada
	var falhar := func():
		_fechar_minigame(mg)
		if not tf.is_empty():
			_concluir_tarefa(tf, 0.0, true)
	if mg.has_signal("falhou"):
		mg.falhou.connect(falhar)
	# fechou no X ou no Esc: antes de começar, volta ao jogo de graça. Depois de começar (comecou() no minigame),
	# o primeiro pedido só avisa e o segundo, em até TEMPO_DESISTIR, é desistir: conta como falha. Sem isso, o
	# jogador fugiria de qualquer derrota (e dos erros) fechando e abrindo o minigame de novo.
	if mg.has_signal("cancelou"):
		mg.cancelou.connect(func():
			var pode_falhar: bool = not tf.is_empty() and mg.has_signal("falhou") and mg.has_method("comecou")
			if not pode_falhar or not mg.comecou():
				_fechar_minigame(mg)
			elif desistir <= 0.0:
				desistir = TEMPO_DESISTIR
				quadro_desistir = Engine.get_process_frames()
			elif Engine.get_process_frames() != quadro_desistir:
				falhar.call()
		)


func _fechar_minigame(mg: Control) -> void:
	mg.queue_free()
	em_minigame = false
	desistir = 0.0
	aviso_desistir.visible = false
	quadro_fechou_minigame = Engine.get_process_frames()
	hud.visible = true
	jogador.set_physics_process(true)


## `fator`: quanto do ganho a tarefa rende (1 = tudo; menos quando o minigame teve erros). `perdeu`: o minigame
## falhou; a tarefa gasta a ação do dia do mesmo jeito, mas não rende nada.
func _concluir_tarefa(tf: Dictionary, fator := 1.0, perdeu := false) -> void:
	jogador.usar()
	feitas[tf["id"]] = true
	var texto := str(tf["texto"])
	ciclo.registrar({"texto": texto + " (FAILED)"} if perdeu else tf)   # gasta uma das ações do dia
	_atualizar_marcas()
	if perdeu:
		_avisar("FAILED: " + texto)
	else:
		Recursos.aplicar(tf["id"], fator)
		_avisar(("DONE: " if fator >= 1.0 else "DONE WITH ERRORS: ") + texto)
	if ciclo.acoes_restantes() == 0:
		await get_tree().create_timer(2.0).timeout
		if not dormindo and not fim:
			_avisar("NO TIME LEFT TODAY: GO TO BED")


func _interagir(it: Dictionary) -> void:
	if it["acao"] == "dormir":
		# com ações sobrando, o primeiro E só pergunta: dormir encerra o dia e as ações que sobraram se perdem
		if ciclo.acoes_restantes() > 0 and confirmar_dormir <= 0.0:
			confirmar_dormir = TEMPO_CONFIRMAR
			return
		confirmar_dormir = 0.0
		usadas[it["id"]] = true
		encerrar_dia(it["id"])
	else:
		usadas[it["id"]] = true
		Recursos.aplicar(it["id"])


## Dormir: a tela escurece e o ciclo fecha o dia (resumo da noite). Com `id_cama` vazio (aba DEV), sem o efeito
## da cama. A tela clareia quando o jogador sai do resumo (_amanhecer); se a missão acabou, fica escura.
func encerrar_dia(id_cama := "") -> void:
	if dormindo or fim:
		return
	dormindo = true
	jogador.velocity = Vector2.ZERO
	jogador.t_usar = 0.9
	jogador.spr.play("idle_down")
	var tw := create_tween()
	tw.tween_property(self, "escuro", 1.0, 0.8)
	await tw.finished
	_levantar(id_cama)
	ciclo.fechar_dia(id_cama)


## Com a tela escura, o astronauta sai da cama para o ponto "acordar": de manhã ele não fica em cima dela, onde um
## E a mais (o mesmo que fecha o boletim) faria dormir de novo e perder o dia.
func _levantar(id_cama: String) -> void:
	for it in interacoes:
		if it["id"] == id_cama and it.has("acordar"):
			jogador.global_position = it["acordar"]
			jogador.reset_physics_interpolation()


func _amanhecer() -> void:
	var tw := create_tween()
	tw.tween_property(self, "escuro", 0.0, 0.8)
	await tw.finished
	dormindo = false


# ---------------------------------------------------------------- modo demo
func _bot_usa(item: Dictionary) -> bool:
	return not alvo_demo.is_empty() and alvo_demo["id"] == item["id"] and jogador.bot_quer_usar(item)


## O robô escolhe, entre as tarefas do dia, a que deixa o indicador mais baixo o mais alto possível (empate: a
## ordem das salas em ordem_demo) e, sem ações, vai dormir.
func _proximo_alvo() -> Dictionary:
	var melhor := {}
	var nota := -INF
	for sala in mapa["ordem_demo"]:
		for item in tarefas:
			if item["sala"] != sala or feitas.has(item["id"]) or not ciclo.disponivel(item["id"]):
				continue
			var depois: Dictionary = Recursos.valores.duplicate()
			var efeito := Recursos.previa(item["id"])
			for nome in efeito:
				depois[nome] = clampf(depois[nome] + efeito[nome], 0.0, 100.0)
			var n: float = depois.values().min()
			if n > nota + 0.01:
				nota = n
				melhor = item
	if not melhor.is_empty():
		return melhor
	for item in interacoes:
		if item["acao"] == "dormir":
			return item
	return {}


func _demo(delta: float) -> void:
	if fim or em_minigame or dormindo or ciclo.ocupado():
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


# ---------------------------------------------------------------- interface
## Canto de cima à esquerda: a sala, as tarefas oferecidas hoje (as de outras salas com o nome da sala em cinza),
## o dia e quantas ações faltam. Tarefa feita fica com o quadradinho verde; sem ações, as que sobraram apagam.
func _desenha_hud() -> void:
	var titulo := "TUNNEL"
	if sala_atual != "":
		titulo = str(salas[sala_atual]["dados"].get("titulo", sala_atual))
	var lista := ciclo.hoje.map(func(id): return _tarefa(id)).filter(func(x): return not x.is_empty())
	var rodape := "DAY %d/%d" % [Missao.dia, ciclo.total_dias()]
	var acoes := "%d ACTIONS LEFT" % ciclo.acoes_restantes() if ciclo.acoes_restantes() != 1 else "1 ACTION LEFT"
	if ciclo.acoes_restantes() == 0:
		acoes = "SLEEP TO END THE DAY"
	var largura := 104.0
	largura = max(largura, Fonte.largura(titulo) + 14)
	largura = max(largura, Fonte.largura(rodape + " - " + acoes) + 10)
	for tf in lista:
		var extra: float = 0.0 if tf["sala"] == sala_atual else Fonte.largura(_titulo_sala(tf["sala"])) + 8
		largura = max(largura, Fonte.largura(str(tf["texto"])) + 17 + extra)
	var linhas := lista.size() + 2
	hud.draw_rect(Rect2(4, 3, largura, 2 + 8 * linhas), Color(0.035, 0.04, 0.08, 0.7))
	var y := 6
	Fonte.desenhar(hud, titulo, Vector2(8, y), AMARELO)
	for tf in lista:
		y += 8
		var feito := feitas.has(tf["id"])
		var pode := ciclo.disponivel(tf["id"]) and not feito
		var ic: Texture2D = tf.get("icone")
		if ic:                                     # o mesmo ícone do minimapa; feita = apagado com um visto verde
			hud.draw_texture(ic, Vector2(7, y - 1), Color.WHITE if pode else Color(1, 1, 1, 0.35))
			if feito:
				_visto(Vector2(9, y + 1))
		else:
			hud.draw_rect(Rect2(8, y + 1, 3, 3), VERDE if feito else (AMARELO if pode else ESCURO))
		Fonte.desenhar(hud, str(tf["texto"]), Vector2(17, y), BRANCO if pode else CINZA)
		if tf["sala"] != sala_atual:
			var s := _titulo_sala(tf["sala"])
			Fonte.desenhar(hud, s, Vector2(4 + largura - 4 - Fonte.largura(s), y), ESCURO if not pode else CINZA)
	y += 8
	Fonte.desenhar(hud, rodape, Vector2(8, y), AZUL if Recursos.noite else CINZA)
	var cor_acoes := AMARELO if ciclo.acoes_restantes() == 0 and fmod(t, 1.0) < 0.6 else CINZA
	Fonte.desenhar(hud, "- " + acoes, Vector2(8 + Fonte.largura(rodape) + 4, y), cor_acoes)
	_desenha_recursos()
	_desenha_minimapa()
	if mapa_aberto:
		_desenha_mapa_tela()
		return
	var tf := _perto(tarefas, feitas)
	if tf.is_empty():
		tf = _perto(interacoes, usadas)
	if not tf.is_empty() and not dormindo and tf.get("acao", "") == "dormir" and confirmar_dormir > 0.0:
		var n := ciclo.acoes_restantes()
		Fonte.centralizado(hud, "E AGAIN: END THE DAY NOW", 160, 154, AMARELO)
		Fonte.centralizado(hud, "%d %s LEFT WILL BE LOST" % [n, "ACTION" if n == 1 else "ACTIONS"], 160, 162,
			VERMELHO)
	elif not tf.is_empty() and not dormindo:
		var efeito := texto_previa(tf["id"])
		var y_e := 160 if efeito == "" else 154
		Fonte.centralizado(hud, "E: " + str(tf["texto"]), 160, y_e, AMARELO)
		if efeito != "":                           # custo e benefício antes de fazer
			Fonte.centralizado(hud, efeito, 160, y_e + 8, BRANCO)
	if escuro > 0.0:
		hud.draw_rect(Rect2(0, 0, 320, 180), Color(0.02, 0.02, 0.05, escuro))
		var zs := "Z" + " Z".repeat(int(t * 2.0) % 3)
		Fonte.centralizado(hud, zs, 160, 86, Color(BRANCO, escuro))
	if t_aviso > 0.0 and escuro < 0.3:
		var w := Fonte.largura(aviso) + 8
		hud.draw_rect(Rect2(160 - w / 2.0, 54, w, 11), Color(0.035, 0.04, 0.08, 0.8))
		Fonte.centralizado(hud, aviso, 160, 57, BRANCO)


## Minimapa no canto de baixo à direita: a planta pequena com o ícone de cada tarefa que dá para fazer agora (o mesmo
## da lista no canto de cima; as mesmas da seta amarela) e o astronauta em branco. Some com os minigames, os painéis do
## dia (boletim, noite, fim), o mapa da tecla M e enquanto ele dorme.
func _desenha_minimapa() -> void:
	if em_minigame or fim or dormindo or escuro > 0.0 or ciclo.ocupado() or mapa_aberto:
		return
	var canto := Vector2(320 - 5, 180 - 5) - TEX_MINIMAPA.get_size()
	hud.draw_rect(Rect2(canto - Vector2(2, 2), TEX_MINIMAPA.get_size() + Vector2(4, 4)), Color(0.035, 0.04, 0.08, 0.7))
	_desenha_planta(TEX_MINIMAPA, canto, false)


## Mapa da tecla M: a planta grande com o nome das salas, todas as tarefas do dia (feitas apagadas com visto) e, ao
## lado, a lista do dia com os mesmos ícones. O astronauta fica parado enquanto ele está aberto (M ou Esc fecha).
func _desenha_mapa_tela() -> void:
	hud.draw_rect(Rect2(0, 0, 320, 180), Color(0.035, 0.04, 0.08, 0.98))
	Fonte.desenhar(hud, "BASE MAP", Vector2(TELA_POS.x, 4), AMARELO)
	var tam := TEX_MAPA_TELA.get_size()
	hud.draw_rect(Rect2(TELA_POS - Vector2(1, 1), tam + Vector2(2, 2)), ESCURO)
	_desenha_planta(TEX_MAPA_TELA, TELA_POS, true)
	for nome in salas:                         # nome da sala embaixo, dentro dela
		var s: Dictionary = salas[nome]
		var tam_sala := Vector2(s["dados"]["tamanho"][0], s["dados"]["tamanho"][1])
		var p := _na_planta(s["pos"] + Vector2(tam_sala.x / 2.0, tam_sala.y), TEX_MAPA_TELA, TELA_POS)
		var cor := CINZA if nome != sala_atual else BRANCO
		var titulo := _titulo_sala(nome)
		var largura_sala := tam_sala.x * TEX_MAPA_TELA.get_size().x / PLANTA_TAM.x
		if Fonte.largura(titulo) > largura_sala - 6 and " " in titulo:     # nome comprido: duas linhas
			var partes := titulo.split(" ", false, 1)
			Fonte.centralizado(hud, partes[0], p.x, p.y - 15, cor)
			Fonte.centralizado(hud, partes[1], p.x, p.y - 9, cor)
		else:
			Fonte.centralizado(hud, titulo, p.x, p.y - 9, cor)
	# a lista do dia
	var x := TELA_POS.x + tam.x + 10
	var y := 16.0
	Fonte.desenhar(hud, "TODAY - DAY %d/%d" % [Missao.dia, ciclo.total_dias()], Vector2(x, y), AMARELO)
	for id in ciclo.hoje:
		var tf := _tarefa(id)
		if tf.is_empty():
			continue
		y += 14
		var feito := feitas.has(id)
		var pode := ciclo.disponivel(id) and not feito
		var ic: Texture2D = tf.get("icone")
		if ic:
			hud.draw_texture(ic, Vector2(x, y - 1), Color.WHITE if pode else Color(1, 1, 1, 0.35))
			if feito:
				_visto(Vector2(x + 2, y + 1))
		Fonte.desenhar(hud, str(tf["texto"]), Vector2(x + 10, y), BRANCO if pode else CINZA)
		Fonte.desenhar(hud, _titulo_sala(tf["sala"]), Vector2(x + 10, y + 6), ESCURO if not pode else CINZA)
	Fonte.desenhar(hud, "YOU", Vector2(x + 10, 150), BRANCO)
	hud.draw_rect(Rect2(x + 2, 150, 4, 4), CONTORNO)
	hud.draw_rect(Rect2(x + 3, 151, 2, 2), BRANCO)
	var fechar := "M OR ESC: CLOSE"
	Fonte.desenhar(hud, fechar, Vector2(320 - 6 - Fonte.largura(fechar), 168), CINZA)


## A planta (minimapa ou mapa da tecla M) com o canto em canto: ícones das tarefas e o astronauta. Com todas, mostra
## também as tarefas do dia já feitas ou sem ação sobrando (apagadas; feita com visto), senão só as que dá para fazer.
func _desenha_planta(tex: Texture2D, canto: Vector2, todas: bool) -> void:
	hud.draw_texture(tex, canto)
	var aceso := fmod(t, 0.8) < 0.55
	for id in ciclo.hoje:
		var feito := feitas.has(id)
		var pode := ciclo.disponivel(id) and not feito
		if not pode and not todas:
			continue
		var tf := _tarefa(id)
		if tf.is_empty():
			continue
		var m := _na_planta(tf["pos"], tex, canto)
		var ic: Texture2D = tf.get("icone")
		if ic:                                     # o mesmo ícone da lista, sozinho (sem moldura nem fundo)
			var tam_ic := ic.get_size()
			var meio := (tam_ic / 2.0).floor()
			var c := m.clamp(canto + meio, canto + tex.get_size() - tam_ic + meio)
			hud.draw_texture(ic, c - meio, Color.WHITE if pode else Color(1, 1, 1, 0.35))
			if feito:
				_visto(c - meio + Vector2(2, 2))
		elif aceso and pode:
			hud.draw_rect(Rect2(m + Vector2(-1, -2), Vector2(3, 5)), CONTORNO)    # cruz amarela com contorno
			hud.draw_rect(Rect2(m + Vector2(-2, -1), Vector2(5, 3)), CONTORNO)
			hud.draw_rect(Rect2(m + Vector2(0, -1), Vector2(1, 3)), AMARELO)
			hud.draw_rect(Rect2(m + Vector2(-1, 0), Vector2(3, 1)), AMARELO)
	if todas and not aceso:                    # no mapa grande o astronauta pisca, para achar rápido
		return
	var j := _na_planta(jogador.global_position, tex, canto)
	hud.draw_rect(Rect2(j - Vector2(1, 1), Vector2(4, 4)), CONTORNO)
	hud.draw_rect(Rect2(j, Vector2(2, 2)), BRANCO)


## Visto verde (5x4) com contorno escuro, por cima do ícone de uma tarefa feita.
func _visto(p: Vector2) -> void:
	for d in [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]:
		for q in [Vector2(0, 2), Vector2(1, 3), Vector2(2, 2), Vector2(3, 1), Vector2(4, 0)]:
			hud.draw_rect(Rect2(p + q + d, Vector2.ONE), CONTORNO)
	for q in [Vector2(0, 2), Vector2(1, 3), Vector2(2, 2), Vector2(3, 1), Vector2(4, 0)]:
		hud.draw_rect(Rect2(p + q, Vector2.ONE), VERDE)


## Posição no mapa -> pixel da planta tex desenhada com o canto em canto (preso dentro dela).
func _na_planta(pos: Vector2, tex: Texture2D, canto: Vector2) -> Vector2:
	var p := ((pos - PLANTA_ORIGEM) * tex.get_size() / PLANTA_TAM).floor()
	return canto + p.clamp(Vector2.ZERO, tex.get_size() - Vector2.ONE)


## Faixa embaixo da tela, por cima do minigame: fechar agora é desistir, e a tarefa conta como falha.
func _desenha_aviso_desistir() -> void:
	aviso_desistir.draw_rect(Rect2(0, 168, 320, 12), Color(0.035, 0.04, 0.08, 0.92))
	aviso_desistir.draw_rect(Rect2(0, 168, 320, 1), VERMELHO)
	var cor := AMARELO if fmod(desistir, 0.5) > 0.25 else BRANCO
	Fonte.centralizado(aviso_desistir, "ESC OR X AGAIN: GIVE UP - THE TASK FAILS", 160, 172, cor)


func _titulo_sala(sala: String) -> String:
	return str(salas[sala]["dados"].get("titulo", sala))


## Os 4 indicadores no canto de cima à direita: nome, barra e valor. Abaixo do limite, a barra pisca em vermelho.
## Quando uma tarefa muda um indicador, aparece "+15" (ou "-5") à esquerda dele por 2 s.
func _desenha_recursos() -> void:
	var largura := 82
	var x0 := 320 - 4 - largura
	hud.draw_rect(Rect2(x0, 3, largura, 2 + 8 * Recursos.NOMES.size()), Color(0.035, 0.04, 0.08, 0.7))
	for i in Recursos.NOMES.size():
		var nome: String = Recursos.NOMES[i]
		var v: float = Recursos.valores[nome]
		var y := 6 + 8 * i
		var cor: Color = Recursos.CORES[nome]
		Fonte.desenhar(hud, Recursos.ROTULOS[nome], Vector2(x0 + 4, y), cor)
		var barra := Rect2(x0 + 30, y, 32, 5)
		hud.draw_rect(barra, ESCURO)
		var cor_barra := cor
		if Recursos.baixo(nome):
			cor_barra = VERMELHO if fmod(t, 0.6) < 0.3 else cor
		hud.draw_rect(Rect2(barra.position, Vector2(round(barra.size.x * v / 100.0), barra.size.y)), cor_barra)
		var txt := str(ceili(v))
		Fonte.desenhar(hud, txt, Vector2(x0 + largura - 4 - Fonte.largura(txt), y), BRANCO)
		if variacoes.has(nome):
			var d: float = variacoes[nome][0]
			var s := "%+d" % roundi(d)
			var xs := x0 - 4 - Fonte.largura(s)
			hud.draw_rect(Rect2(xs - 3, y - 2, Fonte.largura(s) + 5, 9), Color(0.035, 0.04, 0.08, 0.85))
			Fonte.desenhar(hud, s, Vector2(xs, y), Color("#a8ca58") if d > 0 else VERMELHO)
