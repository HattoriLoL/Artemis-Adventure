
extends RefCounted
## Relatório final da missão, em 4 páginas: 01 OVERVIEW, 02 LOG, 03 SCIENCE, 04 DONKI.
## Só apresentação e análise do que aconteceu: quem controla a página, as teclas e o mouse é o ciclo_dias.gd.
##   - preparar(): chamado uma vez quando a missão termina. Registra o evento final, escolhe a decisão de maior impacto,
##     monta a história causal, a linha do tempo (3 a 5 acontecimentos) e a curiosidade, e guarda tudo em _cache;
##   - fundo() e desenhar(): desenham a tela (o ciclo_dias.gd desenha a moldura de metal entre os dois).
## Os dados vêm da Missao (eventos, decisao_impacto, ciencia, donki), do Recursos e de dados/curiosidades.json.
## Textos em inglês e só com os caracteres que a fonte 3x5 tem (Fonte.GLIFOS).
 
const Fonte = preload("res://scripts/fonte.gd")
 
const ARQUIVO_CURIOSIDADES := "res://dados/curiosidades.json"
const TEX_LUA := preload("res://assets/pouso/fundo.png")
const ICONE_SOL := preload("res://assets/pouso/icone_sol.png")      # 7x7
const ICONE_GELO := preload("res://assets/pouso/icone_gelo.png")    # 7x7
 
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
 
# ---- layout (tudo dentro dos 320 x 180 do jogo)
const PAGINAS := ["01 OVERVIEW", "02 LOG", "03 SCIENCE", "04 DONKI"]
const COR_ABA := [AMARELO, AMARELO, AZUL, AZUL]
const MOLDURA := Rect2(8, 6, 304, 160)
const X0 := 18                     # começo do conteúdo
const LARG := 284                  # largura do conteúdo
const Y0 := 40                     # topo do conteúdo (abaixo das abas)
const BOTAO_VOLTAR := Rect2(8, 169, 44, 10)
const BOTAO_PROXIMO := Rect2(268, 169, 44, 10)
const BOTAO_NOVA := Rect2(232, 169, 80, 10)
 
# ---- textos
const RES_TITULO := {"concluida": "MISSION COMPLETE", "dificuldades": "MISSION COMPLETE WITH DIFFICULTIES",
	"abortada": "MISSION ABORTED"}
const RES_BADGE := {"concluida": "SUCCESS", "dificuldades": "WITH DIFFICULTIES", "abortada": "ABORTED"}
const RES_COR := {"concluida": VERDE, "dificuldades": AMARELO, "abortada": VERMELHO}
const CAUSAS := {"energia": "The base lost all power", "oxigenio": "The oxygen ran out",
	"comida": "The food ran out", "condicao": "The crew became too sick to work"}
const ROTULO_BAIXO := {"energia": "power", "oxigenio": "oxygen", "comida": "food", "condicao": "health"}
 
## O indicador em que o risco de cada local aparece (planície: sem ponto fraco, qualquer indicador conta).
const PONTO_FRACO := {"polo": "energia", "borda": "oxigenio", "planicie": ""}
## [por que escolheu, o que aconteceu se o risco do local pesou, o que aconteceu se a equipe segurou o risco]
const ESCOLHA := {
	"polo": ["You chose the south pole to be close to the ice.",
		"The long nights cut solar power and the batteries ran low.",
		"The crew handled the long nights and kept the batteries charged."],
	"borda": ["You chose the crater rim for its strong sunlight.",
		"With little ice nearby, water and air supplies ran low.",
		"The crew found enough water despite the lack of ice nearby."],
	"planicie": ["You chose the middle plain for its balance of light and access.",
		"Nothing came easy there and some supplies ran low.",
		"Balanced choices every day kept the base steady."],
}
const DECISOES_POUSO := {
	"polo": {"titulo": "Choosing the south pole", "texto": "More ice for water, but less sunlight for power.",
		"tradeoff": "WATER ACCESS / ENERGY GENERATION"},
	"borda": {"titulo": "Choosing the crater rim", "texto": "More sunlight for power, but little ice nearby for water.",
		"tradeoff": "ENERGY GENERATION / WATER ACCESS"},
	"planicie": {"titulo": "Choosing the middle plain", "texto": "A balanced site: no big gain and no big risk.",
		"tradeoff": "BALANCE / NO STRONG POINT"},
}
const CLAUSULA_DESCUIDO := {
	"energia": "Power was not a priority, so the reserves kept falling.",
	"oxigenio": "The air system was not a priority, so oxygen kept falling.",
	"comida": "Food was not a priority, so the supplies ran low.",
	"condicao": "Crew care was not a priority, so the crew wore down.",
}
const OBJETIVOS_PADRAO := ["LUNAR ICE INVESTIGATION", "REGOLITH ANALYSIS", "BIOLOGICAL EXPERIMENTS"]
 
## Montado em preparar() e só lido em desenhar() (o ciclo redesenha a tela todo quadro).
static var _cache: Dictionary = {}
 
 
# ================================================================ análise (chamada uma vez, no fim da missão)
## `dias` = regras["dias"] do dias.json (as tarefas oferecidas em cada dia).
static func preparar(dias: Array) -> void:
	_registrar_fim()
	_analisar_decisoes(dias)
	var vista: Texture2D = load("res://assets/pouso/local_%s.png" % Missao.local_pouso)
	_cache = {"total": dias.size(), "vista": vista, "historia": historia(), "linha": linha_do_tempo(),
		"curiosidade": curiosidade()}
 
 
static func _registrar_fim() -> void:
	var d := Missao.dia
	match Missao.resultado:
		"concluida":
			Missao.registrar_evento(d, "fim", "MISSION COMPLETE", "The crew finished the expedition with healthy reserves.", "", 10)
		"dificuldades":
			Missao.registrar_evento(d, "fim", "MISSION COMPLETE", "The crew finished the expedition with limited reserves.", "", 10)
		_:
			Missao.registrar_evento(d, "fim", "MISSION ABORTED", CAUSAS.get(Missao.causa, "A system failed") + ".",
				Missao.causa, 10)
 
 
## O risco do local pesou? (o indicador fraco do local ficou crítico em algum momento; na planície, qualquer um)
static func _risco_bateu() -> bool:
	var fraco: String = PONTO_FRACO.get(Missao.local_pouso, "")
	for e in Missao.eventos:
		if e["tipo"] == "critico" and (fraco == "" or e["impacto"] == fraco):
			return true
	return fraco != "" and Recursos.baixo(fraco)
 
 
## Escolhe a decisão de maior impacto entre: o local de pouso (sempre candidato) e os "descuidos", isto é, um
## indicador que ficou crítico (ou terminou baixo) enquanto havia dias com tarefa oferecida para recuperá-lo e o
## jogador escolheu outras. Em empate, o descuido ganha (é a consequência mais direta de uma escolha do jogador).
static func _analisar_decisoes(dias: Array) -> void:
	var candidatas: Array = []
	var efeitos: Dictionary = Recursos.regras["efeitos"]
	var mult: Dictionary = Recursos.regras["multiplicadores"]
	for nome in Recursos.NOMES:
		var foi_critico := Missao.eventos.any(func(e): return e["tipo"] == "critico" and e["impacto"] == nome)
		var terminou_baixo := Recursos.baixo(nome)
		if not foi_critico and not terminou_baixo:
			continue
		var perdidos := 0                      # dias em que dava para recuperar e o jogador fez outra coisa
		for d in Missao.historico:
			var feitas: Array = d.get("ids", [])
			var ajudava := false
			var fez := false
			for id in dias[int(d["dia"]) - 1]["tarefas"]:
				var ef: Dictionary = efeitos.get(id, {})
				if float(ef.get(nome, 0.0)) <= 0.0:
					continue
				if d["noite"] and mult.get(id, "") == "geracao_solar":
					continue                   # painel à noite não rende: não conta como tarefa que ajudava
				ajudava = true
				if id in feitas:
					fez = true
			if ajudava and not fez:
				perdidos += 1
		if perdidos == 0:
			continue
		var peso := 4 + perdidos * 2 + (3 if terminou_baixo else 0) + (4 if Missao.causa == nome else 0)
		var rot: String = ROTULO_BAIXO[nome]
		candidatas.append({"tipo": "descuido", "indicador": nome, "peso": peso,
			"titulo": "%s was not prioritized" % rot.capitalize(),
			"texto": "On %d %s the crew could restore %s but chose other tasks." % [
				perdidos, "day" if perdidos == 1 else "days", rot],
			"tradeoff": "%s / OTHER TASKS" % rot.to_upper(), "curiosidade": nome + "_baixa"})
	var noites := int(Missao.condicoes.get("dias_de_noite", 0))
	var pouso: Dictionary = DECISOES_POUSO.get(Missao.local_pouso, {"titulo": "Choosing the site", "texto": "", "tradeoff": ""})
	candidatas.append({"tipo": "pouso", "indicador": PONTO_FRACO.get(Missao.local_pouso, ""),
		"peso": 2 + noites + (5 if _risco_bateu() else 0), "titulo": pouso["titulo"], "texto": pouso["texto"],
		"tradeoff": pouso["tradeoff"], "curiosidade": Missao.local_pouso})
	var melhor: Dictionary = candidatas[0]
	for c in candidatas:
		if c["peso"] > melhor["peso"]:
			melhor = c
	Missao.decisao_impacto = melhor
 
 
## A história causal do fim: resultado + por que escolheu o local + o que aconteceu + o que pesou mais + desfecho.
static func historia() -> String:
	var res := Missao.resultado
	var linhas: Array[String] = []
	linhas.append({"concluida": "The mission was a success.", "dificuldades": "The mission was completed, but with difficulties.",
		"abortada": "The mission was aborted."}[res])
	var esc: Array = ESCOLHA.get(Missao.local_pouso, [])
	if not esc.is_empty():
		linhas.append(esc[0])
		linhas.append(esc[1] if _risco_bateu() else esc[2])
	var dec: Dictionary = Missao.decisao_impacto
	if dec.get("tipo", "") == "descuido":
		linhas.append(CLAUSULA_DESCUIDO[dec["indicador"]])
	match res:
		"concluida":
			linhas.append("The crew finished all %d days and left the base ready for the next crew." % Missao.dia)
		"dificuldades":
			var baixos := Recursos.NOMES.filter(func(n): return Recursos.baixo(n))
			var nomes := PackedStringArray(baixos.map(func(n): return ROTULO_BAIXO[n]))
			linhas.append("The crew finished all %d days, but %s ended low." % [Missao.dia, ", ".join(nomes)])
		_:
			linhas.append("%s on day %d, so the crew returned to Orion." % [CAUSAS.get(Missao.causa, "A system failed"), Missao.dia])
	return " ".join(linhas)
 
 
## 3 a 5 acontecimentos em ordem de dia: o pouso e o fim sempre entram; o resto é o de maior peso.
## Se a partida teve poucos acontecimentos, completa com a tarefa principal de algum dia.
static func linha_do_tempo() -> Array:
	var fixos := Missao.eventos.filter(func(e): return e["peso"] >= 10)
	var outros := Missao.eventos.filter(func(e): return e["peso"] < 10)
	outros.sort_custom(func(a, b): return a["peso"] > b["peso"] or (a["peso"] == b["peso"] and a["n"] < b["n"]))
	var escolhidos: Array = fixos + outros.slice(0, maxi(0, 5 - fixos.size()))
	var n := Missao.eventos.size()
	for d in Missao.historico:
		if escolhidos.size() >= 3:
			break
		if d["acoes"].is_empty() or escolhidos.any(func(e): return e["dia"] == d["dia"] and e["tipo"] != "fim"):
			continue
		escolhidos.append({"n": n, "dia": d["dia"], "tipo": "dia", "titulo": "TASKS DONE",
			"descricao": "Main task: %s." % str(d["acoes"][0]).to_lower().replace(" (failed)", ""), "impacto": "", "peso": 0})
		n += 1
	escolhidos.sort_custom(func(a, b): return a["dia"] < b["dia"] or (a["dia"] == b["dia"] and a["n"] < b["n"]))
	return escolhidos
 
 
## A curiosidade acompanha a decisão de maior impacto; sem texto para ela, usa o local de pouso.
static func curiosidade() -> Dictionary:
	var todas = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO_CURIOSIDADES))
	var chave: String = Missao.decisao_impacto.get("curiosidade", Missao.local_pouso)
	if not todas.has(chave):
		chave = Missao.local_pouso
	return todas.get(chave, todas.get("padrao", {"titulo": "", "texto": ""}))
 
 
# ================================================================ desenho
## Fundo do relatório: a Lua vista da órbita (a mesma da tela de pouso), bem escura, atrás da moldura.
static func fundo(ci: CanvasItem) -> void:
	ci.draw_texture(TEX_LUA, Vector2.ZERO, Color(1, 1, 1, 0.35))
 
 
static func aba_rect(i: int) -> Rect2:
	return Rect2(16 + i * 72, 24, 72, 11)
 
 
## Chamado depois de desenhar a moldura (MOLDURA): cabeçalho, abas, a página e os botões de baixo.
static func desenhar(ci: CanvasItem, pagina: int) -> void:
	var cor: Color = RES_COR[Missao.resultado]
	var topo := MOLDURA.position.y + 5
	Fonte.desenhar(ci, "ARTEMIS PROGRAM", Vector2(MOLDURA.position.x + 14, topo), METAL_CLARO)
	Fonte.centralizado(ci, "MISSION REPORT", 160, topo, AMARELO)
	var dia_txt := "DAY %d/%d" % [Missao.dia, int(_cache["total"])]
	Fonte.desenhar(ci, dia_txt, Vector2(MOLDURA.end.x - 14 - Fonte.largura(dia_txt), topo), cor)
	for i in PAGINAS.size():
		var a := aba_rect(i)
		var ativa := i == pagina
		if ativa:
			ci.draw_rect(a, FUNDO)
			ci.draw_rect(Rect2(a.position.x, a.end.y - 1, a.size.x, 1), COR_ABA[i])
		Fonte.centralizado(ci, PAGINAS[i], a.get_center().x, a.position.y + 3, BRANCO if ativa else METAL)
	match pagina:
		0:
			_pagina_resumo(ci)
		1:
			_pagina_log(ci)
		2:
			_pagina_ciencia(ci)
		3:
			_pagina_donki(ci)
	_navegacao(ci, pagina)
 
 
## 01 OVERVIEW: resultado, história causal, local de pouso e os 4 indicadores finais.
static func _pagina_resumo(ci: CanvasItem) -> void:
	var res := Missao.resultado
	var cor: Color = RES_COR[res]
	Fonte.desenhar(ci, "FINAL STATUS", Vector2(X0, Y0), METAL)
	var badge: String = RES_BADGE[res]
	var br := Rect2(X0 + LARG - Fonte.largura(badge) - 8, Y0 - 2, Fonte.largura(badge) + 8, 9)
	_borda(ci, br, cor)
	Fonte.centralizado(ci, badge, br.get_center().x, Y0, cor)
	Fonte.desenhar(ci, RES_TITULO[res], Vector2(X0, Y0 + 9), cor, 2)
	var y := Y0 + 22
	var linhas := _quebrar(_cache["historia"], LARG)
	for i in mini(linhas.size(), 5):
		Fonte.desenhar(ci, linhas[i], Vector2(X0, y), BRANCO)
		y += 8
	ci.draw_rect(Rect2(X0, 102, LARG, 1), CINZA_ESC)
	# local de pouso: a vista (assets/pouso/local_<id>.png), os medidores de sol e gelo e as noites
	var local: Dictionary = Missao.dados_local
	var cl := Color(str(local.get("cor", "#a8b5b2")))
	_borda(ci, Rect2(X0 - 1, 105, 98, 26), cl)
	if _cache["vista"] != null:
		ci.draw_texture(_cache["vista"], Vector2(X0, 106))
	Fonte.desenhar(ci, "LANDING SITE", Vector2(120, 106), METAL)
	Fonte.desenhar(ci, str(local.get("titulo", "")), Vector2(120, 114), cl)
	_medidor(ci, ICONE_SOL, int(local.get("sol", 0)), Vector2(120, 123))
	_medidor(ci, ICONE_GELO, int(local.get("gelo", 0)), Vector2(160, 123))
	Fonte.desenhar(ci, "LUNAR NIGHT", Vector2(214, 106), METAL)
	var noites := int(Missao.condicoes.get("dias_de_noite", 0))
	Fonte.desenhar(ci, "%d %s" % [noites, "DAY" if noites == 1 else "DAYS"], Vector2(214, 114), AZUL)
	Fonte.desenhar(ci, "FINAL TELEMETRY", Vector2(X0, 135), METAL)
	for i in Recursos.NOMES.size():
		_indicador(ci, Recursos.NOMES[i], Vector2(X0 + (i % 2) * 142, 144 + (i / 2) * 9))
 
 
## 02 LOG: linha do tempo (3 a 5 acontecimentos) e a decisão de maior impacto.
static func _pagina_log(ci: CanvasItem) -> void:
	var lista: Array = _cache["linha"]
	var y := Y0
	for i in lista.size():
		var e: Dictionary = lista[i]
		var cor := _cor_evento(e)
		if i < lista.size() - 1:
			ci.draw_rect(Rect2(X0 + 3, y + 8, 1, 9), CINZA_ESC)
		ci.draw_rect(Rect2(X0, y, 7, 7), FUNDO)
		_borda(ci, Rect2(X0, y, 7, 7), cor)
		Fonte.desenhar(ci, str(i + 1), Vector2(X0 + 2, y + 1), cor)
		Fonte.desenhar(ci, "DAY %02d - %s" % [int(e["dia"]), e["titulo"]], Vector2(X0 + 12, y), cor)
		var desc := _quebrar(str(e["descricao"]), LARG - 12)
		Fonte.desenhar(ci, desc[0], Vector2(X0 + 12, y + 8), BRANCO)
		y += 17
	var d: Dictionary = Missao.decisao_impacto
	var r := Rect2(X0, 125, LARG, 36)
	ci.draw_rect(r, FUNDO)
	_borda(ci, r, CINZA_ESC)
	ci.draw_rect(Rect2(r.position.x, r.position.y, 2, r.size.y), AMARELO)
	Fonte.desenhar(ci, "MOST IMPACTFUL DECISION", Vector2(r.position.x + 8, r.position.y + 4), AMARELO)
	Fonte.desenhar(ci, str(d.get("titulo", "")), Vector2(r.position.x + 8, r.position.y + 12), BRANCO)
	Fonte.desenhar(ci, str(d.get("texto", "")), Vector2(r.position.x + 8, r.position.y + 20), METAL_CLARO)
	Fonte.desenhar(ci, "TRADE-OFF: " + str(d.get("tradeoff", "")), Vector2(r.position.x + 8, r.position.y + 28), METAL)
 
 
## 03 SCIENCE: amostras e dados (ainda sem sistema de ciência: mostra "--"), objetivos e a curiosidade.
static func _pagina_ciencia(ci: CanvasItem) -> void:
	var c: Dictionary = Missao.ciencia
	var amostras: Array = c.get("amostras", [])
	var total := float(c.get("dados_totais", 0.0))
	var v1 := str(amostras.size()) if not amostras.is_empty() else "--"
	var v2 := "%d%%" % roundi(100.0 * float(c.get("dados_transmitidos", 0.0)) / total) if total > 0.0 else "--"
	_cartao_numero(ci, Rect2(X0, Y0, 140, 28), "SAMPLES COLLECTED", v1)
	_cartao_numero(ci, Rect2(X0 + 144, Y0, 140, 28), "DATA TRANSMITTED", v2)
	Fonte.desenhar(ci, "RESEARCH OBJECTIVES", Vector2(X0, 74), AZUL)
	var objetivos: Array = c.get("objetivos", [])
	if objetivos.is_empty():
		objetivos = OBJETIVOS_PADRAO.map(func(n): return {"nome": n, "feito": false})
	var y := 83
	for o in objetivos:
		ci.draw_rect(Rect2(X0, y + 1, 3, 3), AZUL)
		Fonte.desenhar(ci, str(o["nome"]), Vector2(X0 + 8, y), BRANCO)
		var estado := "DONE" if o.get("feito", false) else "PENDING"
		Fonte.desenhar(ci, estado, Vector2(X0 + LARG - Fonte.largura(estado), y), VERDE if o.get("feito", false) else METAL)
		y += 8
	if c.get("objetivos", []).is_empty():
		Fonte.desenhar(ci, "RESEARCH RESULTS WILL APPEAR WHEN THE SCIENCE SYSTEM IS READY.", Vector2(X0, 109), METAL)
	var cur: Dictionary = _cache["curiosidade"]
	var r := Rect2(X0, 117, LARG, 44)
	ci.draw_rect(r, FUNDO)
	_borda(ci, r, CINZA_ESC)
	ci.draw_rect(Rect2(r.position.x, r.position.y, 2, r.size.y), AMARELO)
	Fonte.desenhar(ci, "SCIENTIFIC FACT", Vector2(r.position.x + 8, r.position.y + 4), AMARELO)
	Fonte.desenhar(ci, str(cur.get("titulo", "")), Vector2(r.position.x + 8, r.position.y + 12), BRANCO)
	var ls := _quebrar(str(cur.get("texto", "")), LARG - 16)
	for i in mini(ls.size(), 3):
		Fonte.desenhar(ci, ls[i], Vector2(r.position.x + 8, r.position.y + 20 + i * 8), METAL_CLARO)
 
 
## 04 DONKI: espaço reservado para o evento de clima espacial (Missao.donki vazio = integração pendente).
static func _pagina_donki(ci: CanvasItem) -> void:
	var dk: Dictionary = Missao.donki
	var pronto := not dk.is_empty()
	var r := Rect2(X0, Y0, LARG, 86)
	ci.draw_rect(r, FUNDO)
	_borda(ci, r, AZUL)
	Fonte.desenhar(ci, "SPACE WEATHER DATABASE", Vector2(r.position.x + 8, r.position.y + 5), BRANCO)
	Fonte.desenhar(ci, "NASA OPEN DATA", Vector2(r.position.x + 8, r.position.y + 13), METAL)
	ci.draw_rect(Rect2(r.position.x + 4, r.position.y + 23, r.size.x - 8, 1), CINZA_ESC)
	var fonte_txt := "--"
	if pronto:
		fonte_txt = "LIVE DATA" if dk.get("fonte", "") == "ao_vivo" else "ARCHIVED DATA"
	var campos := [["EVENT TYPE", str(dk.get("tipo", "AWAITING INTEGRATION")) if pronto else "AWAITING INTEGRATION"],
		["EVENT DATE", str(dk.get("data", "--"))], ["DATA SOURCE", fonte_txt if pronto else "LIVE / ARCHIVED"]]
	for i in campos.size():
		var x: float = r.position.x + 8 + i * 94
		Fonte.desenhar(ci, campos[i][0], Vector2(x, r.position.y + 29), METAL)
		Fonte.desenhar(ci, campos[i][1], Vector2(x, r.position.y + 37), BRANCO)
	ci.draw_rect(Rect2(r.position.x + 4, r.position.y + 49, r.size.x - 8, 1), CINZA_ESC)
	var etiqueta := "INTEGRATION PENDING" if not pronto else ("LIVE EVENT" if dk.get("fonte", "") == "ao_vivo" else "ARCHIVED EVENT")
	var cor_et := Color("#d98a3d") if not pronto else VERDE
	var er := Rect2(r.position.x + 8, r.position.y + 55, Fonte.largura(etiqueta) + 8, 9)
	ci.draw_rect(er, Color(cor_et, 0.25))
	_borda(ci, er, cor_et)
	Fonte.desenhar(ci, etiqueta, Vector2(er.position.x + 4, er.position.y + 2), cor_et)
	var nota := "The related space weather event will appear here once the DONKI connection is implemented."
	if pronto:
		nota = str(dk.get("relacao", ""))
	var y := r.position.y + 69
	for l in _quebrar(nota, r.size.x - 16):
		Fonte.desenhar(ci, l, Vector2(r.position.x + 8, y), METAL_CLARO)
		y += 8
	y = Y0 + 94
	for l in _quebrar("DONKI reports space weather events such as flares and solar storms. It does not measure conditions on the lunar surface.", LARG):
		Fonte.desenhar(ci, l, Vector2(X0, y), METAL)
		y += 8
	Fonte.desenhar(ci, "EVENT TYPES: CME / SEP / GST / FLR", Vector2(X0, y + 4), AZUL)
 
 
## Botões de baixo (fora da moldura) e o número da página. O ciclo_dias.gd lê as teclas e o mouse.
static func _navegacao(ci: CanvasItem, pagina: int) -> void:
	var ultima := pagina == PAGINAS.size() - 1
	_botao(ci, BOTAO_VOLTAR, "< BACK", METAL_CLARO if pagina > 0 else CINZA_ESC)
	Fonte.centralizado(ci, "ARTEMIS REPORT %d/%d" % [pagina + 1, PAGINAS.size()], 160, 172, METAL)
	if ultima:
		_botao(ci, BOTAO_NOVA, "E: NEW MISSION", VERDE)
	else:
		_botao(ci, BOTAO_PROXIMO, "NEXT >", METAL_CLARO)
 
 
# ---------------------------------------------------------------- peças
static func _cor_evento(e: Dictionary) -> Color:
	match e["tipo"]:
		"pouso", "noite":
			return AZUL
		"critico", "desgaste", "falha":
			return VERMELHO
		"erros":
			return AMARELO
		"tempestade":
			return Color("#de9e41")             # erupção solar: laranja (a cor do alerta da tempestade)
		"fim":
			return RES_COR[Missao.resultado]
	return VERDE
 
 
static func _borda(ci: CanvasItem, r: Rect2, cor: Color) -> void:
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), cor)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), cor)
	ci.draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), cor)
	ci.draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), cor)
 
 
static func _botao(ci: CanvasItem, r: Rect2, txt: String, cor: Color) -> void:
	ci.draw_rect(r, FUNDO)
	_borda(ci, r, cor)
	Fonte.centralizado(ci, txt, r.get_center().x, r.position.y + 3, cor)
 
 
static func _cartao_numero(ci: CanvasItem, r: Rect2, rotulo: String, valor: String) -> void:
	ci.draw_rect(r, FUNDO)
	_borda(ci, r, CINZA_ESC)
	Fonte.desenhar(ci, rotulo, Vector2(r.position.x + 6, r.position.y + 5), METAL)
	Fonte.desenhar(ci, valor, Vector2(r.position.x + 6, r.position.y + 14), AZUL, 2)
 
 
## Ícones de 7x7 (sol ou gelo), `n` de 3 acesos e o resto apagado (como na tela de pouso).
static func _medidor(ci: CanvasItem, icone: Texture2D, n: int, pos: Vector2) -> void:
	for i in 3:
		ci.draw_texture(icone, pos + Vector2(i * 9, 0), Color(1, 1, 1, 1.0 if i < n else 0.25))
 
 
static func _indicador(ci: CanvasItem, nome: String, pos: Vector2) -> void:
	var cor: Color = Recursos.CORES[nome]
	var v: float = Recursos.valores[nome]
	Fonte.desenhar(ci, Recursos.ROTULOS[nome], pos, cor)
	var barra := Rect2(pos.x + 32, pos.y, 60, 5)
	ci.draw_rect(barra, CINZA_ESC)
	ci.draw_rect(Rect2(barra.position, Vector2(roundf(barra.size.x * v / 100.0), 5)), VERMELHO if Recursos.baixo(nome) else cor)
	Fonte.desenhar(ci, "%d%%" % ceili(v), Vector2(barra.end.x + 6, pos.y), BRANCO)
 
 
## Quebra o texto em linhas que cabem em `largura` px na fonte 3x5.
static func _quebrar(texto: String, largura: float) -> Array[String]:
	var linhas: Array[String] = []
	var atual := ""
	for p in texto.split(" ", false):
		var tentativa: String = p if atual == "" else atual + " " + p
		if Fonte.largura(tentativa) > largura and atual != "":
			linhas.append(atual)
			atual = p
		else:
			atual = tentativa
	if atual != "":
		linhas.append(atual)
	return linhas
 
