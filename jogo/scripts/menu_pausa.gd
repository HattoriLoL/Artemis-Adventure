extends CanvasLayer
## Menu de pausa (Esc): continuar, opções (tela cheia) e sair. Em build de debug (rodando pelo editor) aparece também
## a aba DEV, com atalhos para testar o jogo: ir para uma sala, concluir/refazer as tarefas do dia, encerrar o dia,
## abrir um minigame direto, atravessar paredes, correr mais, destravar as portas e desenhar FPS, posição, colisões
## e a grade de navegação.
## O jogo fica pausado (get_tree().paused) enquanto o menu está aberto; este nó roda sempre.
## Teclado: W/S ou setas escolhem, A/D trocam o valor, E/Enter confirma, Esc volta. O mouse também funciona.
## Desenhado em código, como o HUD e o minigame da estufa: moldura de metal, fonte 3x5 e cores da paleta.

const Fonte = preload("res://scripts/fonte.gd")

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const AZUL := Color("#73bed3")

const LARGURA := 164
const ALT_LINHA := 10
const VELOCIDADES := [1.0, 2.0, 4.0]
const TITULOS := {"inicio": "PAUSED", "opcoes": "OPTIONS", "dev": "DEV TOOLS"}

var mapa: Node2D                   # o mapa.gd (quem cria o menu preenche)
var aberto := false
var pagina := "inicio"
var sel := 0
var confirmar_sair := false
var recado := ""                   # resposta curta da última ação (aparece embaixo do painel)
var t_recado := 0.0

# aba DEV
var i_sala := 0
var i_minigame := 0
var minigames: Array[String] = []
var noclip := false
var i_vel := 0
var destravar := false
var ver_info := false
var ver_colisao := false
var ver_grade := false

var tela: Control                  # o menu
var info: Control                  # FPS e posição, no canto (fica visível com o menu fechado)
var mundo: Node2D                  # colisões e raios das tarefas, desenhados no mapa
var grade: Sprite2D                # grade de navegação (células bloqueadas em vermelho)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	info = Control.new()
	info.size = Vector2(320, 180)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.visible = false
	info.draw.connect(_desenha_info)
	add_child(info)
	tela = Control.new()
	tela.size = Vector2(320, 180)
	tela.visible = false
	tela.draw.connect(_desenha_menu)
	add_child(tela)
	mundo = Node2D.new()
	mundo.z_index = 50
	mundo.visible = false
	mundo.draw.connect(_desenha_mundo)
	mapa.add_child.call_deferred(mundo)
	_achar_minigames()
	Prints.salvo.connect(_print_salvo)


func _print_salvo(_caminho: String) -> void:
	mapa._avisar("SCREENSHOT SAVED")
	_avisar("SCREENSHOT SAVED")                      # se o F12 foi com o menu aberto


func _achar_minigames() -> void:
	var dir := DirAccess.open("res://cenas")
	if dir == null:
		return
	for f in dir.get_files():
		f = f.trim_suffix(".remap")                  # no jogo exportado as cenas aparecem como .tscn.remap
		if f.begins_with("minigame_") and f.ends_with(".tscn"):
			minigames.append("res://cenas/" + f)
	minigames.sort()


func _process(delta: float) -> void:
	t_recado = maxf(0.0, t_recado - delta)
	if ver_info:
		info.queue_redraw()
	if ver_colisao:
		mundo.queue_redraw()
	if aberto:
		tela.queue_redraw()


# ---------------------------------------------------------------- abrir e fechar
func _abrir() -> void:
	aberto = true
	pagina = "inicio"
	sel = 0
	confirmar_sair = false
	t_recado = 0.0
	tela.visible = true
	get_tree().paused = true


func _fechar() -> void:
	aberto = false
	tela.visible = false
	# despausa no fim do quadro: o E/Enter que fechou o menu não chega ao mapa como "usar" uma tarefa
	get_tree().set_deferred("paused", false)


func _voltar() -> void:
	if pagina == "inicio":
		_fechar()
		return
	var de := pagina
	pagina = "inicio"
	sel = 2 if de == "dev" else 1
	confirmar_sair = false


func _avisar(txt: String) -> void:
	recado = txt
	t_recado = 2.0


# ---------------------------------------------------------------- itens de cada aba
func _itens() -> Array:
	match pagina:
		"opcoes":
			var tela_cheia := {"id": "tela_cheia", "texto": "FULLSCREEN", "liga": Opcoes.tela_cheia}
			if not Opcoes.pode_tela_cheia():           # dentro da aba Game do editor a janela não é do jogo
				tela_cheia = {"id": "tela_cheia", "texto": "FULLSCREEN", "fixo": "EDITOR"}
			return [tela_cheia, {"id": "tutoriais", "texto": "SHOW TUTORIALS AGAIN"}, {"id": "voltar", "texto": "BACK"}]
		"dev":
			var sala: String = _salas()[i_sala]
			var mg := "NONE" if minigames.is_empty() else _nome_minigame(minigames[i_minigame])
			return [
				{"id": "ir", "texto": "GO TO", "valor": str(mapa.salas[sala]["dados"].get("titulo", sala))},
				{"id": "sala_feita", "texto": "FINISH ROOM TASKS"},
				{"id": "tudo_feito", "texto": "FINISH ALL TASKS"},
				{"id": "zerar", "texto": "RESET TODAY"},
				{"id": "fim_dia", "texto": "END THE DAY"},
				{"id": "erupcao", "texto": "SOLAR STORM NOW"},
				{"id": "minigame", "texto": "MINIGAME", "valor": mg},
				{"id": "noclip", "texto": "NOCLIP", "liga": noclip},
				{"id": "vel", "texto": "SPEED", "valor": "%dX" % int(VELOCIDADES[i_vel])},
				{"id": "portas", "texto": "UNLOCK DOORS", "liga": destravar},
				{"id": "info", "texto": "FPS AND POSITION", "liga": ver_info},
				{"id": "colisao", "texto": "HITBOXES", "liga": ver_colisao},
				{"id": "grade", "texto": "NAV GRID", "liga": ver_grade},
				{"id": "print", "texto": "SCREENSHOT (F12)"},
				{"id": "pasta_prints", "texto": "OPEN PRINTS FOLDER"},
				{"id": "voltar", "texto": "BACK"},
			]
	var lista := [{"id": "continuar", "texto": "RESUME"}, {"id": "opcoes", "texto": "OPTIONS"}]
	if OS.is_debug_build():
		lista.append({"id": "dev", "texto": "DEV"})
	lista.append({"id": "sair", "texto": "PRESS AGAIN TO QUIT" if confirmar_sair else "QUIT GAME"})
	return lista


func _salas() -> Array:
	return mapa.mapa["salas"].map(func(s): return str(s["nome"]))


func _nome_minigame(caminho: String) -> String:
	return caminho.get_file().get_basename().trim_prefix("minigame_").replace("_", " ")


# ---------------------------------------------------------------- entrada
func _input(ev: InputEvent) -> void:
	if not aberto:
		if ev.is_action_pressed("ui_cancel") and mapa.pode_pausar():
			_abrir()
			get_viewport().set_input_as_handled()
		return
	var itens := _itens()
	if ev is InputEventMouseMotion:
		var i := _linha_no_mouse(itens.size())
		if i >= 0:
			sel = i
		return
	if ev is InputEventMouseButton and ev.pressed:
		var i := _linha_no_mouse(itens.size())
		if i < 0:
			return
		sel = i
		var it: Dictionary = itens[i]
		if it.has("valor"):                          # clique na metade esquerda volta, na direita avança
			_mudar(it["id"], -1 if tela.get_local_mouse_position().x < _painel(itens.size()).get_center().x else 1)
		else:
			_ativar(it["id"])
		get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("ui_cancel"):
		_voltar()
	elif ev.is_action_pressed("cima", true) or ev.is_action_pressed("ui_up", true):
		sel = posmod(sel - 1, itens.size())
	elif ev.is_action_pressed("baixo", true) or ev.is_action_pressed("ui_down", true):
		sel = posmod(sel + 1, itens.size())
	elif ev.is_action_pressed("esquerda", true) or ev.is_action_pressed("ui_left", true):
		_mudar(itens[sel]["id"], -1)
	elif ev.is_action_pressed("direita", true) or ev.is_action_pressed("ui_right", true):
		_mudar(itens[sel]["id"], 1)
	elif ev.is_action_pressed("usar") or ev.is_action_pressed("ui_accept"):
		_ativar(itens[sel]["id"])
	else:
		return
	get_viewport().set_input_as_handled()


func _linha_no_mouse(n: int) -> int:
	var m := tela.get_local_mouse_position()
	var r := _painel(n)
	for i in n:
		if _linha(i, r).has_point(m):
			return i
	return -1


## A/D ou setas: troca o valor dos itens com opções; nos de liga/desliga, alterna.
func _mudar(id: String, d: int) -> void:
	match id:
		"ir":
			i_sala = posmod(i_sala + d, _salas().size())
		"minigame":
			if not minigames.is_empty():
				i_minigame = posmod(i_minigame + d, minigames.size())
		"vel":
			i_vel = posmod(i_vel + d, VELOCIDADES.size())
			mapa.jogador.mult_vel = VELOCIDADES[i_vel]
		"tela_cheia", "noclip", "portas", "info", "colisao", "grade":
			_ativar(id)


## E/Enter ou clique.
func _ativar(id: String) -> void:
	if id != "sair":
		confirmar_sair = false
	match id:
		"continuar":
			_fechar()
		"opcoes", "dev":
			pagina = id
			sel = 0
		"voltar":
			_voltar()
		"sair":
			if confirmar_sair:
				get_tree().quit()
			confirmar_sair = true
		"tutoriais":
			preload("res://scripts/tutorial_minigame.gd").zerar()
			_avisar("TUTORIALS WILL SHOW AGAIN")
		"tela_cheia":
			if Opcoes.pode_tela_cheia():
				Opcoes.definir_tela_cheia(not Opcoes.tela_cheia)
			else:
				_avisar("NO FULLSCREEN IN THE EDITOR GAME TAB")
		"ir":
			_ir_para(_salas()[i_sala])
		"sala_feita":
			if mapa.sala_atual == "":
				_avisar("NOT IN A ROOM")
			else:
				_concluir(mapa.tarefas.filter(func(x): return x["sala"] == mapa.sala_atual))
		"tudo_feito":
			_concluir(mapa.tarefas)
		"zerar":
			mapa.zerar_dia()
			_avisar("TODAY'S TASKS AND ACTIONS RESET")
		"erupcao":
			_fechar()
			if not mapa.erupcao_agora_dev():
				mapa._avisar("CAN'T START THE STORM NOW")
		"fim_dia":
			_fechar()
			mapa.encerrar_dia()
		"minigame":
			if minigames.is_empty():
				_avisar("NO MINIGAMES")
			else:
				_fechar()
				mapa.abrir_minigame(minigames[i_minigame])
		"vel":
			_mudar("vel", 1)
		"noclip":
			noclip = not noclip
			mapa.jogador.collision_mask = 0 if noclip else 1
		"portas":
			destravar = not destravar
			for p in mapa.portas:
				if destravar and p.dados.get("trancada", false):
					p.dados["trancada"] = false
					p.dados["trancada_dev"] = true          # para trancar de novo ao desligar
				elif not destravar and p.dados.get("trancada_dev", false):
					p.dados["trancada"] = true
					p.dados.erase("trancada_dev")
		"info":
			ver_info = not ver_info
			info.visible = ver_info
		"colisao":
			ver_colisao = not ver_colisao
			mundo.visible = ver_colisao
			mundo.queue_redraw()
		"print":
			_fechar()                                    # o menu não aparece no print
			await get_tree().process_frame
			await get_tree().process_frame
			Prints.tirar()
		"pasta_prints":
			Prints.abrir_pasta()
		"grade":
			ver_grade = not ver_grade
			if ver_grade and grade == null:
				_criar_grade()
			if grade:
				grade.visible = ver_grade


# ---------------------------------------------------------------- ações da aba DEV
func _ir_para(nome: String) -> void:
	var s: Dictionary = mapa.salas[nome]
	var tam: Array = s["dados"]["tamanho"]
	var centro: Vector2 = s["pos"] + Vector2(tam[0], tam[1]) / 2.0
	var c: Vector2i = mapa._livre_perto(Vector2i(centro / mapa.celula))   # célula livre mais perto do meio da sala
	mapa.jogador.global_position = Vector2(c) * mapa.celula + Vector2.ONE * mapa.celula / 2.0
	mapa.jogador.velocity = Vector2.ZERO
	mapa.jogador.reset_physics_interpolation()     # sem isso a interpolação "arrasta" o astronauta até lá
	_fechar()


func _concluir(lista: Array) -> void:
	var n := 0
	for tf in lista:
		if not mapa.feitas.has(tf["id"]):
			mapa.feitas[tf["id"]] = true
			mapa.marcas[tf["id"]].visible = false
			n += 1
	_avisar("%d TASKS DONE" % n)


## A própria imagem da grade, ampliada; um shader pinta de vermelho só as células bloqueadas
## (mesma regra do mapa.gd: escuro = bloqueado). Montar a imagem pixel a pixel travava o jogo por ~1 s.
func _criar_grade() -> void:
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec4 cor : source_color;
void fragment() {
	COLOR = vec4(cor.rgb, cor.a * (1.0 - step(0.5, texture(TEXTURE, UV).r)));
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("cor", Color(VERMELHO, 0.35))
	grade = Sprite2D.new()
	grade.texture = load(mapa.mapa["navegacao"])
	grade.material = mat
	grade.centered = false
	grade.scale = Vector2(mapa.celula, mapa.celula)
	grade.z_index = 49
	mapa.add_child(grade)


# ---------------------------------------------------------------- desenho do menu
func _painel(n: int) -> Rect2:
	var h := 18 + n * ALT_LINHA + 6
	return Rect2(round((320 - LARGURA) / 2.0), round((180 - h) / 2.0) - 4, LARGURA, h)


func _linha(i: int, r: Rect2) -> Rect2:
	return Rect2(r.position.x + 5, r.position.y + 17 + i * ALT_LINHA, r.size.x - 10, ALT_LINHA - 1)


func _desenha_menu() -> void:
	tela.draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	var itens := _itens()
	var r := _painel(itens.size())
	_moldura(r)
	Fonte.centralizado(tela, TITULOS[pagina], r.get_center().x, r.position.y + 5, AMARELO)
	for i in itens.size():
		var it: Dictionary = itens[i]
		var l := _linha(i, r)
		var escolhido := i == sel
		var y := l.position.y + 2
		if escolhido:
			tela.draw_rect(l, FUNDO)
			Fonte.desenhar(tela, ">", Vector2(l.position.x + 2, y), AMARELO)
		var cor := AMARELO if escolhido else BRANCO
		if it["id"] == "sair" and confirmar_sair:
			cor = VERMELHO
		Fonte.desenhar(tela, it["texto"], Vector2(l.position.x + 8, y), cor)
		if it.has("fixo"):
			Fonte.desenhar(tela, it["fixo"], Vector2(l.end.x - 3 - Fonte.largura(it["fixo"]), y), CINZA)
		elif it.has("liga"):
			var v := "ON" if it["liga"] else "OFF"
			Fonte.desenhar(tela, v, Vector2(l.end.x - 3 - Fonte.largura(v), y), VERDE if it["liga"] else CINZA)
		elif it.has("valor"):
			var v: String = it["valor"]
			var x_fim := l.end.x - 3
			_seta(tela, Vector2(x_fim - 3, y), 1, cor)
			var x := x_fim - 6 - Fonte.largura(v)
			Fonte.desenhar(tela, v, Vector2(x, y), AZUL)
			_seta(tela, Vector2(x - 6, y), -1, cor)
	var y_baixo := r.end.y + 4
	if t_recado > 0.0:
		Fonte.centralizado(tela, recado, 160, y_baixo, VERDE)
	else:
		Fonte.centralizado(tela, "W/S: MOVE  A/D: CHANGE  E: OK  ESC: BACK", 160, y_baixo, METAL)


## Mesma moldura de metal do minigame da estufa: borda preta, chanfro claro em cima/esquerda, rebites nos cantos.
func _moldura(p: Rect2) -> void:
	tela.draw_rect(p, PRETO)
	tela.draw_rect(p.grow(-1), CINZA)
	tela.draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(p.size.x - 2, 1)), METAL_CLARO)
	tela.draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(1, p.size.y - 2)), METAL)
	tela.draw_rect(Rect2(p.position + Vector2(2, p.size.y - 2), Vector2(p.size.x - 3, 1)), CINZA_ESC)
	tela.draw_rect(Rect2(p.position + Vector2(p.size.x - 2, 2), Vector2(1, p.size.y - 3)), CINZA_ESC)
	for c in [Vector2(3, 3), Vector2(p.size.x - 6, 3), Vector2(3, p.size.y - 6), Vector2(p.size.x - 6, p.size.y - 6)]:
		tela.draw_rect(Rect2(p.position + c, Vector2(3, 3)), METAL)
		tela.draw_rect(Rect2(p.position + c + Vector2.ONE, Vector2.ONE), CINZA_ESC)
	tela.draw_rect(Rect2(p.position + Vector2(8, 3), Vector2(p.size.x - 16, 10)), FUNDO)
	tela.draw_rect(Rect2(p.position + Vector2(4, 15), Vector2(p.size.x - 8, p.size.y - 19)), Color(PRETO, 0.35))


## Setinha de 3x5 (a fonte não tem "<"): dir = 1 aponta para a direita, -1 para a esquerda.
func _seta(ci: CanvasItem, pos: Vector2, d: int, cor: Color) -> void:
	for i in 3:
		var x := pos.x + (i if d > 0 else 2 - i)
		ci.draw_rect(Rect2(x, pos.y + i, 1, 5 - 2 * i), cor)


# ---------------------------------------------------------------- desenhos de debug
func _desenha_info() -> void:
	var p: Vector2 = mapa.jogador.global_position
	var linhas := ["FPS %d" % Engine.get_frames_per_second(), "X %d Y %d" % [p.x, p.y]]
	var sala: String = mapa.sala_atual
	if sala != "":                                   # posição dentro da sala: é a que vai no JSON das tarefas
		var local: Vector2 = p - mapa.salas[sala]["pos"]
		linhas.append("%s %d,%d" % [sala, local.x, local.y])
	else:
		linhas.append("TUNNEL")
	var w := 0
	for l in linhas:
		w = maxi(w, Fonte.largura(l))
	var x := 320 - w - 6                             # canto de baixo à direita: em cima fica o X dos minigames
	var h := 2 + 8 * linhas.size()
	var y := 180 - 3 - h
	info.draw_rect(Rect2(x - 3, y, w + 6, h), Color(0.035, 0.04, 0.08, 0.7))
	for i in linhas.size():
		Fonte.desenhar(info, linhas[i], Vector2(x, y + 3 + 8 * i), VERDE if i == 0 else BRANCO)


func _desenha_mundo() -> void:
	var vermelho := Color(VERMELHO, 0.8)
	for r in mapa.mapa["solidos"]:
		mundo.draw_rect(Rect2(r[0], r[1], r[2], r[3]), vermelho, false, 1.0)
	for nome in mapa.salas:
		var off: Vector2 = mapa.salas[nome]["pos"]
		for r in mapa.salas[nome]["dados"]["solidos"]:
			mundo.draw_rect(Rect2(off.x + r[0], off.y + r[1], r[2], r[3]), vermelho, false, 1.0)
	for p in mapa.portas:
		var b: Array = p.dados["bloqueio"]
		var fechada: bool = not p.forma.disabled
		mundo.draw_rect(Rect2(b[0], b[1], b[2], b[3]), AMARELO if fechada else Color(CINZA, 0.6), false, 1.0)
		var g: Array = p.dados["gatilho"]
		mundo.draw_rect(Rect2(g[0], g[1], g[2], g[3]), Color(VERDE, 0.4), false, 1.0)
	for tf in mapa.tarefas:                          # raio em que o E funciona (20 px, ver _perto no mapa.gd)
		var cor := Color(CINZA, 0.6) if mapa.feitas.has(tf["id"]) else AMARELO
		mundo.draw_arc(tf["pos"], 20.0, 0.0, TAU, 32, cor, 1.0)
		mundo.draw_rect(Rect2(tf["pos"] - Vector2.ONE, Vector2(2, 2)), cor)
	for it in mapa.interacoes:
		mundo.draw_arc(it["pos"], 20.0, 0.0, TAU, 32, AZUL, 1.0)
		mundo.draw_rect(Rect2(it["pos"] - Vector2.ONE, Vector2(2, 2)), AZUL)
	var j: Vector2 = mapa.jogador.global_position      # caixa de colisão do astronauta (12x6, nos pés)
	mundo.draw_rect(Rect2(j + Vector2(-6, -6), Vector2(12, 6)), AZUL, false, 1.0)
