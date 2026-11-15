extends Node2D
## O mapa principal: as 5 salas ligadas por túneis pressurizados, com portas que igualam a pressão antes de abrir.
## Dados em res://mapa/mapa.json e res://salas/<sala>.json.
##   -- --demo   o astronauta faz todas as tarefas sozinho, sala por sala (e o jogo fecha no fim, para gravar vídeo)

const Fonte = preload("res://scripts/fonte.gd")
const Porta = preload("res://scripts/porta.gd")
const MenuPausa = preload("res://scripts/menu_pausa.gd")
const CicloDias = preload("res://scripts/ciclo_dias.gd")
const Tempestade = preload("res://scripts/tempestade.gd")
const Tutorial = preload("res://scripts/tutorial_minigame.gd")
const CardSala = preload("res://scripts/card_sala.gd")
const AMARELO := Color("#e8c170")
const BRANCO := Color("#ebede9")
const CINZA := Color("#819796")
const VERDE := Color("#75a743")
const VERMELHO := Color("#cf573c")
const ESCURO := Color("#394a50")
const AZUL := Color("#73bed3")
const SEM_SOL := "NO SUN TODAY: NO EFFECT"
# minimapa (canto de baixo à direita): a planta da base (arte na paleta Apollo), que cobre o retângulo
# PLANTA_ORIGEM + PLANTA_TAM do mapa (salas e túneis); a escala sai do tamanho da imagem
const TEX_MINIMAPA := preload("res://assets/mapa/minimapa_canto.png")     # 64x78 (testados: 53x64 e 74x90)
const PLANTA_ORIGEM := Vector2(40, 40)
const PLANTA_TAM := Vector2(944, 1146)
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
const EmergenciaMeteorosScript = preload("res://scripts/emergencia_meteoros.gd")
var emergencia: EmergenciaMeteoros = null
var camera: Camera2D = null
var t_shake: float = 0.0
var forca_shake: float = 0.0
var marcas := {}
var pc_item := {}                  # a interação do computador de navegação (mesa do Suporte)
var marca_pc: Polygon2D            # setinha azul sobre ela enquanto a previsão do dia não foi lida
const MARCA_PC := Vector2(13, -3)  # logo acima dos monitores da mesa (o ponto da interação fica na frente dela)
const MESA_PC := Vector2(13, 50)   # pé da mesa, na borda de baixo da sala (no minimapa, longe do ícone do gás)
var pc_visto_dia := 0              # o dia em que o jogador abriu o computador pela última vez
var cama_item := {}                # a interação da cama (Habitat)
var marca_cama: Polygon2D          # setinha amarela sobre ela quando acabaram as ações do dia
const MARCA_CAMA := Vector2(-60, -38)  # em cima do beliche (o ponto da interação fica no pé dele, à direita)
# ícones 7x7 do minimapa para a cama e o computador (sem arquivo, um desenho simples no lugar)
var ic_cama: Texture2D
var ic_pc: Texture2D
var ic_pc_alerta: Texture2D
var jogador: CharacterBody2D
var hud: Control
var camada_ui: CanvasLayer
var ciclo: CicloDias               # ciclo_dias.gd: dias, ações, boletim, noite e fim da missão
var tempestade: Tempestade         # tempestade.gd: o alarme da erupção solar e a corrida até o Abrigo
var em_minigame := false
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
var card_checado := ""             # a sala em que o card de sala (card_sala.gd) já foi conferido nesta entrada
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
	ic_cama = _icone("habitat/cama")
	ic_pc = _icone("suporte/computador")
	ic_pc_alerta = _icone("suporte/computador_alerta")
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
	emergencia = EmergenciaMeteorosScript.new()
	add_child(emergencia)
	Recursos.iniciar()                             # começa com as condições do local de pouso
	Recursos.mudou.connect(_recursos_mudaram)
	ciclo.noite_fechou.connect(_amanhecer)
	ciclo.iniciar()                                # dia 1: boletim da manhã
	emergencia.iniciar(self)                       # depois do ciclo: o dia dos meteoros evita o da erupção já sorteado


func _entradas() -> void:
	var m := {"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT], "cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN], "correr": [KEY_SHIFT], "usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]}
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
		if item["acao"] == "dormir":
			cama_item = item
			marca_cama = _seta(AMARELO)
			marca_cama.position = item["pos"] + MARCA_CAMA
			add_child(marca_cama)
		if item["acao"] == "computador":
			pc_item = item
			marca_pc = Polygon2D.new()
			marca_pc.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(0, 4)])
			marca_pc.color = Color("#a4dddb")
			var borda := Polygon2D.new()             # contorno escuro: a seta azul some no piso cinza sem ele
			borda.polygon = PackedVector2Array([Vector2(-5, -1), Vector2(5, -1), Vector2(0, 6)])
			borda.color = CONTORNO
			borda.show_behind_parent = true
			marca_pc.add_child(borda)
			marca_pc.position = item["pos"] + MARCA_PC
			marca_pc.z_index = 5
			add_child(marca_pc)


## Setinha (6x4, com contorno escuro) que pula sobre um ponto do mapa.
func _seta(cor: Color) -> Polygon2D:
	var m := Polygon2D.new()
	m.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(0, 4)])
	m.color = cor
	var borda := Polygon2D.new()
	borda.polygon = PackedVector2Array([Vector2(-5, -1), Vector2(5, -1), Vector2(0, 6)])
	borda.color = CONTORNO
	borda.show_behind_parent = true
	m.add_child(borda)
	m.z_index = 5
	m.visible = false
	return m


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
	camera = cam


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
	tempestade = Tempestade.new()
	tempestade.mapa = self
	add_child(tempestade)
	var menu := MenuPausa.new()                   # Esc; fica por último na árvore para ver o Esc antes do minigame
	menu.mapa = self
	add_child(menu)


func pode_pausar() -> bool:
	return not em_minigame and not fim and Engine.get_process_frames() != quadro_fechou_minigame


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
	if not pc_item.is_empty() and id == pc_item["id"]:
		return "NEW SPACE WEATHER DATA" if pc_nao_lido() else ""
	var txt := _texto_efeito(Recursos.previa(id))
	if Recursos.protege(id):                      # blindagem: protege da erupção solar em vez de mudar um recurso
		return (txt + " " if txt != "" else "") + "+1 STORM SHIELD"
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


func tremer_tela(duracao: float = 0.5, forca: float = 3.5) -> void:
	t_shake = duracao
	forca_shake = forca


func _process(delta: float) -> void:
	t += delta
	if t_shake > 0.0:
		t_shake = maxf(0.0, t_shake - delta)
		if camera != null:
			if t_shake > 0.0:
				camera.offset = Vector2(0, -14) + Vector2(randf_range(-forca_shake, forca_shake), randf_range(-forca_shake, forca_shake))
			else:
				camera.offset = Vector2(0, -14)
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
	if marca_cama:
		marca_cama.visible = dia_sem_acoes()
		marca_cama.position.y = cama_item["pos"].y + MARCA_CAMA.y + round(sin(t * 5.0 + 0.7) * 1.5)
	if marca_pc:
		marca_pc.visible = pc_nao_lido() and not tempestade.ativo
		marca_pc.position.y = pc_item["pos"].y + MARCA_PC.y + round(sin(t * 5.0 + 1.5) * 1.5)
	var agora := _sala_de(jogador.global_position)
	if agora != sala_atual:
		sala_atual = agora
		card_checado = ""
		if agora != "" and t > 0.5:
			_avisar(str(salas[agora]["dados"].get("titulo", agora)))
	var tf := _perto(tarefas, feitas)
	var it := _perto(interacoes, usadas)
	var perto_em: bool = emergencia != null and emergencia.perto_estacao(jogador.global_position)
	if demo:
		_demo(delta)
	if dormindo or em_minigame or fim or ciclo.ocupado() or tempestade.ativo:
		pass
	elif perto_em and (Input.is_action_just_pressed("usar") or (demo and _bot_usa_emergencia())):
		emergencia.ativar_escudos()
	elif emergencia != null and emergencia.ativa:
		pass                                       # alarme dos meteoros: só a alavanca (nada de tarefa, computador ou cama)
	elif _card_pendente():
		_abrir_card_sala(sala_atual)
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
## Na primeira vez de cada minigame (fora do demo), antes aparece o tutorial dele (tutorial_minigame.gd).
func abrir_minigame(caminho: String, tf := {}) -> void:
	var id_tutorial := Tutorial.id_de(caminho)
	if not demo and Tutorial.tem(id_tutorial) and not Tutorial.ja_visto(id_tutorial):
		_abrir_tutorial(id_tutorial, caminho, tf)
		return
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


## Tutorial de primeira vez: E começa o minigame (e o tutorial não aparece mais); Esc ou X volta ao jogo sem gastar
## nada (e o tutorial aparece de novo na próxima vez).
func _abrir_tutorial(id_tutorial: String, caminho: String, tf: Dictionary) -> void:
	em_minigame = true
	hud.visible = false
	jogador.velocity = Vector2.ZERO
	jogador.set_physics_process(false)
	var tut: Control = Tutorial.new()
	tut.id = id_tutorial
	camada_ui.add_child(tut)
	tut.continuar.connect(func():
		Tutorial.marcar_visto(id_tutorial)
		tut.queue_free()
		abrir_minigame(caminho, tf)
	)
	tut.cancelou.connect(func(): _fechar_minigame(tut))


## Card de sala: na primeira vez em cada sala (fora do demo), assim que o jogo estiver livre (sem boletim, minigame,
## tempestade nem alarme de meteoros), aparece o fato real sobre para que ela serve. Se o jogador entrou num desses
## momentos, o card espera; se ele saiu da sala antes, aparece na próxima entrada.
func _card_pendente() -> bool:
	if demo or sala_atual == "" or card_checado == sala_atual or t < 0.5:
		return false
	card_checado = sala_atual
	return CardSala.tem_sala(sala_atual) and not CardSala.sala_vista(sala_atual)


## Abre o card de sala por cima do jogo, como o tutorial; fechar (E, Esc ou X) não gasta nada e o card não volta.
func _abrir_card_sala(nome: String) -> void:
	em_minigame = true
	hud.visible = false
	jogador.velocity = Vector2.ZERO
	jogador.set_physics_process(false)
	var card: Control = CardSala.new()
	card.id = nome
	card.sala = salas[nome]["dados"]
	camada_ui.add_child(card)
	var fechar := func():
		CardSala.marcar_sala(nome)
		_fechar_minigame(card)
	card.continuar.connect(fechar)
	card.cancelou.connect(fechar)


## Computador de navegação (mesa do Suporte): clima espacial, diário, previsão e situação da base. Consultar não
## gasta ação; abre por cima do jogo como um minigame (o jogador fica parado e o HUD some).
func abrir_computador() -> void:
	pc_visto_dia = Missao.dia
	em_minigame = true
	hud.visible = false
	jogador.velocity = Vector2.ZERO
	jogador.set_physics_process(false)
	var pc: Control = load("res://cenas/computador_navegacao.tscn").instantiate()
	pc.mapa = self
	pc.fechou.connect(func(): _fechar_minigame(pc))
	camada_ui.add_child(pc)


## As ações do dia acabaram e só falta dormir: a seta amarela vai para a cama e o minimapa mostra só a cama e o
## computador.
func dia_sem_acoes() -> bool:
	return ciclo.acoes_restantes() == 0 and not dormindo and not fim and not tempestade.ativo and not ciclo.ocupado()


## O computador tem previsão nova hoje (o jogador ainda não abriu): setinha no mapa e ícone piscando no minimapa.
func pc_nao_lido() -> bool:
	return not pc_item.is_empty() and pc_visto_dia != Missao.dia and not fim


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
	ciclo.registrar({"id": tf["id"], "texto": texto + " (FAILED)"} if perdeu else tf, perdeu, fator)  # gasta uma das ações do dia
	_atualizar_marcas()
	if perdeu:
		_avisar("FAILED: " + texto)
	else:
		Recursos.aplicar(tf["id"], fator)
		_avisar(("DONE: " if fator >= 1.0 else "DONE WITH ERRORS: ") + texto)
	if ciclo.erupcao_agora():                      # dia da erupção: o alarme toca depois da 1ª ou 2ª tarefa (sorteado)
		tempestade.iniciar()
		return
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
		if ciclo.erupcao_pendente():               # dia da erupção e o alarme ainda não tocou: toca agora, em vez de
			tempestade.iniciar()                   # a tempestade passar escondida na noite (e dormir cedo não foge dela)
			return
		usadas[it["id"]] = true
		encerrar_dia(it["id"])
	elif it["acao"] == "computador":
		abrir_computador()
	else:
		usadas[it["id"]] = true
		Recursos.aplicar(it["id"])


## Aba DEV: dispara o alarme da erupção agora (hoje vira o dia da erupção), para testar sem esperar o sorteio.
func erupcao_agora_dev() -> bool:
	if em_minigame or dormindo or fim or ciclo.ocupado() or tempestade.ativo:
		return false
	Missao.dia_erupcao = Missao.dia
	Missao.tempestade = {}
	tempestade.iniciar()
	return true


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


## A erupção acabou com o dia (chegou ao Abrigo ou foi pego fora): mostra o resultado, escurece e fecha o dia
## onde ele está (sem a cama); o dano da erupção entra no resumo da noite.
func fim_do_dia_tempestade(no_abrigo: bool) -> void:
	if dormindo or fim:
		return
	dormindo = true
	jogador.velocity = Vector2.ZERO
	jogador.t_usar = 2.0
	_avisar("SAFE IN THE SHELTER: THE STORM PASSES" if no_abrigo else "CAUGHT OUTSIDE THE SHELTER!")
	await get_tree().create_timer(1.6).timeout
	var tw := create_tween()
	tw.tween_property(self, "escuro", 1.0, 0.8)
	await tw.finished
	ciclo.fechar_dia("")


func _amanhecer() -> void:
	var tw := create_tween()
	tw.tween_property(self, "escuro", 0.0, 0.8)
	await tw.finished
	dormindo = false


# ---------------------------------------------------------------- modo demo
func _bot_usa(item: Dictionary) -> bool:
	return not alvo_demo.is_empty() and alvo_demo["id"] == item["id"] and jogador.bot_quer_usar(item)


func _bot_usa_emergencia() -> bool:
	return emergencia != null and emergencia.bot_quer_usar(jogador.global_position) and jogador.bot_espera > 0.2


## O robô escolhe, entre as tarefas do dia, a que deixa o indicador mais baixo o mais alto possível (empate: a
## ordem das salas em ordem_demo) e, sem ações, vai dormir.
func _proximo_alvo() -> Dictionary:
	if tempestade.ativo:                           # alarme da erupção: corre para o meio do Abrigo
		var ab: Dictionary = salas[Tempestade.SALA_ABRIGO]
		var tam: Array = ab["dados"]["tamanho"]
		return {"id": "erupcao/abrigo", "pos": ab["pos"] + Vector2(tam[0], tam[1]) / 2.0}
	if emergencia != null and emergencia.ativa:
		return {
			"id": "emergencia/escudos",
			"pos": emergencia.posicao_estacao,
			"sala": emergencia.setor_atual,
			"texto": "PULL EMERGENCY LEVER"
		}
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
	var olhar := 21.0 if jogador.bot_correr else 24.0  # correndo, mirar longe faz ele cortar a curva e enroscar; com menos de 20 ele acha que chegou ao parar numa porta
	while i_caminho < caminho.size() - 1 and jogador.global_position.distance_to(caminho[i_caminho]) < olhar:
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
	if emergencia != null:
		emergencia.desenhar_hud(hud, t)
	var tf := _perto(tarefas, feitas)
	if tf.is_empty():
		tf = _perto(interacoes, usadas)
	var perto_em: bool = emergencia != null and emergencia.perto_estacao(jogador.global_position)
	if tempestade.ativo:
		pass                                       # alarme da erupção: nada de "E:" (as tarefas ficam bloqueadas)
	elif perto_em and not dormindo:
		Fonte.centralizado(hud, "E: PULL EMERGENCY LEVER", 160, 154, AMARELO)
	elif emergencia != null and emergencia.ativa:
		pass                                       # alarme dos meteoros: nada de "E:" fora da alavanca
	elif not tf.is_empty() and not dormindo and tf.get("acao", "") == "dormir" and confirmar_dormir > 0.0:
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
	if t_aviso > 0.0 and escuro < 0.3 and not tempestade.ativo:
		var w := Fonte.largura(aviso) + 8
		hud.draw_rect(Rect2(160 - w / 2.0, 54, w, 11), Color(0.035, 0.04, 0.08, 0.8))
		Fonte.centralizado(hud, aviso, 160, 57, BRANCO)


## Minimapa no canto de baixo à direita: a planta pequena com o ícone de cada tarefa que dá para fazer agora (o mesmo
## da lista no canto de cima; as mesmas da seta amarela) e o astronauta em branco. Some com os minigames, os painéis do
## dia (boletim, noite, fim) e enquanto ele dorme.
func _desenha_minimapa() -> void:
	if em_minigame or fim or dormindo or escuro > 0.0 or ciclo.ocupado():
		return
	var canto := Vector2(320 - 5, 180 - 5) - TEX_MINIMAPA.get_size()
	hud.draw_rect(Rect2(canto - Vector2(2, 2), TEX_MINIMAPA.get_size() + Vector2(4, 4)), Color(0.035, 0.04, 0.08, 0.7))
	_desenha_planta(TEX_MINIMAPA, canto)


## A planta com o canto em canto: os ícones das tarefas que dá para fazer agora e o astronauta.
func _desenha_planta(tex: Texture2D, canto: Vector2) -> void:
	hud.draw_texture(tex, canto)
	var aceso := fmod(t, 0.8) < 0.55
	for id in ciclo.hoje:
		if feitas.has(id) or not ciclo.disponivel(id) or tempestade.ativo:   # no alarme só o Abrigo importa
			continue
		var tf := _tarefa(id)
		if tf.is_empty():
			continue
		var m := _na_planta(tf["pos"], tex, canto)
		var ic: Texture2D = tf.get("icone")
		if ic:                                     # o mesmo ícone da lista, sozinho (sem moldura nem fundo)
			_icone_na_planta(ic, m, tex, canto)
		elif aceso:
			hud.draw_rect(Rect2(m + Vector2(-1, -2), Vector2(3, 5)), CONTORNO)    # cruz amarela com contorno
			hud.draw_rect(Rect2(m + Vector2(-2, -1), Vector2(5, 3)), CONTORNO)
			hud.draw_rect(Rect2(m + Vector2(0, -1), Vector2(1, 3)), AMARELO)
			hud.draw_rect(Rect2(m + Vector2(-1, 0), Vector2(3, 1)), AMARELO)
	if emergencia != null and emergencia.ativa:
		var m_em := _na_planta(emergencia.posicao_estacao, tex, canto)
		var aceso_em := fmod(t, 0.4) < 0.25
		if aceso_em and emergencia.tex_icone:               # ícone do meteoro piscando na sala atingida
			hud.draw_texture(emergencia.tex_icone, m_em - Vector2(4, 4))
		elif aceso_em:
			hud.draw_rect(Rect2(m_em + Vector2(-2, -2), Vector2(5, 5)), CONTORNO)
			hud.draw_rect(Rect2(m_em + Vector2(-1, -1), Vector2(3, 3)), VERMELHO)
			hud.draw_rect(Rect2(m_em, Vector2(1, 1)), AMARELO)
	if not pc_item.is_empty() and not tempestade.ativo:   # computador: monitorzinho, piscando com previsão nova
		var pc := _na_planta(pc_item["pos"] + MESA_PC, tex, canto)
		var alerta := pc_nao_lido() and aceso
		var ic_tela: Texture2D = ic_pc_alerta if alerta and ic_pc_alerta else ic_pc
		if ic_tela:
			_icone_na_planta(ic_tela, pc, tex, canto, Color.WHITE if (alerta or not pc_nao_lido() or ic_pc_alerta) else Color(1, 1, 1, 0.5))
		else:
			hud.draw_rect(Rect2(pc + Vector2(-2, -2), Vector2(5, 4)), CONTORNO)
			var tela_pc := Color("#a4dddb") if (not pc_nao_lido() or aceso) else Color(AZUL, 0.3)
			hud.draw_rect(Rect2(pc + Vector2(-1, -1), Vector2(3, 2)), tela_pc)
	if not cama_item.is_empty() and dia_sem_acoes():   # acabaram as ações: a cama aparece (piscando de leve)
		var cm := _na_planta(cama_item["pos"], tex, canto)
		if ic_cama:
			_icone_na_planta(ic_cama, cm, tex, canto, Color.WHITE if aceso else Color(1, 1, 1, 0.6))
		elif aceso:
			hud.draw_rect(Rect2(cm + Vector2(-3, -2), Vector2(7, 5)), CONTORNO)
			hud.draw_rect(Rect2(cm + Vector2(-2, -1), Vector2(5, 2)), AMARELO)
			hud.draw_rect(Rect2(cm + Vector2(-2, -1), Vector2(1, 1)), BRANCO)
	if tempestade.ativo and fmod(t, 0.5) < 0.3:   # erupção: o Abrigo pisca em vermelho
		var ab: Dictionary = salas[Tempestade.SALA_ABRIGO]
		var tam_ab: Array = ab["dados"]["tamanho"]
		var a := _na_planta(ab["pos"], tex, canto)
		var b := _na_planta(ab["pos"] + Vector2(tam_ab[0], tam_ab[1]), tex, canto)
		var r := Rect2(a, b - a + Vector2.ONE)
		hud.draw_rect(r, Color(VERMELHO, 0.45))
		hud.draw_rect(r, VERMELHO, false)
	var j := _na_planta(jogador.global_position, tex, canto)
	hud.draw_rect(Rect2(j - Vector2(1, 1), Vector2(4, 4)), CONTORNO)
	hud.draw_rect(Rect2(j, Vector2(2, 2)), BRANCO)


## Ícone com o meio em m, preso dentro da planta.
func _icone_na_planta(ic: Texture2D, m: Vector2, tex: Texture2D, canto: Vector2, cor := Color.WHITE) -> void:
	var tam_ic := ic.get_size()
	var meio := (tam_ic / 2.0).floor()
	var c := m.clamp(canto + meio, canto + tex.get_size() - tam_ic + meio)
	hud.draw_texture(ic, c - meio, cor)


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
