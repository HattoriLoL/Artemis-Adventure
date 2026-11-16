extends CanvasLayer
## Ciclo da missão: os dias de dias.json (hoje 5) com 2 ações por dia (regras em res://dados/dias.json). Criado pelo mapa.gd.
##   - manhã: boletim do controle da missão com as tarefas oferecidas no dia e o que cada uma rende;
##   - durante o dia: cada tarefa concluída gasta uma ação (registrar); sem ações, só resta dormir;
##   - noite (dormir na cama do habitat): o consumo do dia, a geração solar e o dano à saúde da equipe por recurso
##     baixo (Recursos.fechar_dia) e um resumo de quanto cada indicador mudou;
##   - fim: um indicador zerou (missão abortada) ou o último dia terminou (concluída, ou com dificuldades se algum
##     indicador terminou baixo). A tela do fim mostra o resultado e o diário da missão; E começa uma nova missão.
## Desenhado em código como o menu de pausa: moldura de metal, fonte 3x5 e cores da paleta.

signal noite_fechou                # o jogador saiu do resumo da noite e o dia seguinte começou (o mapa clareia)

const Fonte = preload("res://scripts/fonte.gd")
const Relatorio = preload("res://scripts/relatorio.gd")
const ARQUIVO := "res://dados/dias.json"
const TELA_POUSO := "res://cenas/escolha_pouso.tscn"
const EVENTOS_SOLARES := "res://dados/eventos_solares.json"
const BLINDAGEM := "abrigo/blindagem"         # o dia da erupção sempre oferece reforçar a blindagem
const VITAIS := "habitat/vitais"              # e o dia seguinte a ela, o exame dos sinais vitais da tripulação
const LARANJA := Color("#de9e41")

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

const ESPERA := 0.4                # o E que abriu o painel (ou o de antes) não pode já fechá-lo
const ESPERA_DEMO := 1.6

var mapa: Node2D                   # o mapa.gd (quem cria preenche)
var regras: Dictionary = {}
var hoje: Array = []               # ids ("sala/tarefa") das tarefas oferecidas hoje
var acoes := 0                     # ações gastas hoje
var painel := ""                   # "manha", "noite", "fim" ou "" (sem painel: o jogo corre)
var resumo := {}                   # da última noite: {"antes": {...}, "depois": {...}, "solar": 4.2, "desgaste": 0}
var t_painel := 0.0
var quadro_fechou := -1
var tela: Control
var pagina := 0                    # página do relatório final (0 a 3)
var baixos_antes := {}             # indicadores que já estavam baixos no fechamento do dia anterior (evento só na queda)

const TEXTOS_CRITICO := {"energia": "Power reserves fell below the safe level.", "oxigenio": "Oxygen reserves fell below the safe level.",
	"comida": "Food stores ran low.", "condicao": "The health of the crew dropped to a low level."}


func _ready() -> void:
	layer = 15                     # acima do HUD, abaixo do menu de pausa (20)
	regras = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	tela = Control.new()
	tela.size = Vector2(320, 180)
	tela.visible = false
	tela.draw.connect(_desenha)
	tela.gui_input.connect(_clique_relatorio)
	add_child(tela)


func total_dias() -> int:
	return regras["dias"].size()


func acoes_por_dia() -> int:
	return int(regras["acoes_por_dia"])


func acoes_restantes() -> int:
	return acoes_por_dia() - acoes


## A tarefa pode ser feita agora: foi oferecida hoje e ainda sobra ação.
func disponivel(id: String) -> bool:
	return id in hoje and acoes < acoes_por_dia()


## Há um painel na tela (ou ele fechou neste quadro): o mapa não aceita o E.
func ocupado() -> bool:
	return painel != "" or Engine.get_process_frames() == quadro_fechou


## As noites são do local de pouso: começam no primeira_noite do local (sem ele, o de dias.json) e duram
## dias_de_noite. Nelas os painéis não geram energia.
func eh_noite(dia: int) -> bool:
	var primeira := int(Missao.condicoes.get("primeira_noite", regras["primeira_noite"]))
	return dia >= primeira and dia < primeira + int(Missao.condicoes.get("dias_de_noite", 0))


func iniciar() -> void:
	Missao.dia = 1
	Missao.historico = []
	Missao.resultado = ""
	Missao.causa = ""
	Missao.blindagem = 0
	Missao.tempestade = {}
	Missao.eventos = []
	Missao.decisao_impacto = {}
	baixos_antes = {}
	Missao.registrar_evento(1, "pouso", "LANDING", "The crew landed at the %s and set up the base." % str(
		Missao.dados_local.get("titulo", "site")).to_lower(), "", 10)
	_sortear_erupcao()
	_comecar_dia()


## O dia da erupção solar (entre radiacao.dia_min e dia_max) e o evento real do DONKI que serve de referência.
func _sortear_erupcao() -> void:
	var r: Dictionary = Recursos.regras.get("radiacao", {})
	if r.is_empty():
		Missao.dia_erupcao = 0
		return
	Missao.dia_erupcao = randi_range(int(r["dia_min"]), mini(int(r["dia_max"]), total_dias()))
	Missao.alarme_apos = int(r.get("alarme_apos", [1]).pick_random())
	var eventos: Array = JSON.parse_string(FileAccess.get_file_as_string(EVENTOS_SOLARES))["eventos"]
	Missao.evento_solar = eventos.pick_random()


## Hoje é o dia da erupção e o alarme ainda não tocou (ele toca depois da tarefa sorteada ou quando o jogador vai
## dormir antes disso).
func erupcao_pendente() -> bool:
	return Missao.dia == Missao.dia_erupcao and Missao.tempestade.is_empty()


## Hoje é o dia da erupção, ela ainda não aconteceu e o jogador já fez a tarefa sorteada (1ª ou 2ª): o alarme toca.
func erupcao_agora() -> bool:
	return Missao.dia == Missao.dia_erupcao and Missao.tempestade.is_empty() and acoes >= Missao.alarme_apos


## Uma tarefa foi concluída: gasta uma ação e entra no diário do dia.
func registrar(tf: Dictionary, perdeu := false, fator := 1.0) -> void:
	acoes += 1
	Missao.historico[-1]["acoes"].append(str(tf["texto"]))
	Missao.historico[-1]["ids"].append(str(tf.get("id", "")))
	var nome := str(tf["texto"]).replace(" (FAILED)", "").to_lower()
	if perdeu:
		Missao.registrar_evento(Missao.dia, "falha", "TASK FAILED", "The crew failed to %s." % nome, "", 3)
	elif fator < 1.0:
		Missao.registrar_evento(Missao.dia, "erros", "SLOPPY WORK", "Mistakes cut the result of: %s." % nome, "", 2)


## Aba DEV: devolve as ações do dia.
func zerar_dia() -> void:
	acoes = 0
	Missao.historico[-1]["acoes"].clear()
	Missao.historico[-1]["ids"].clear()


## Dormir (o mapa já escureceu a tela): a cama (id_cama, vazio = aba DEV), o consumo do dia e o resumo da noite.
func fechar_dia(id_cama := "") -> void:
	var antes: Dictionary = Recursos.valores.duplicate()
	if id_cama != "":
		Recursos.aplicar(id_cama)
	var partes := Recursos.fechar_dia()
	if Missao.dia == Missao.dia_erupcao:
		if Missao.tempestade.is_empty():           # dormiu sem fazer nada no dia da erupção: pego fora do Abrigo
			Missao.tempestade = {"dia": Missao.dia, "abrigo": false, "dormindo": true}
		Missao.tempestade["dano"] = Recursos.ferir("condicao", Recursos.dano_tempestade(Missao.tempestade["abrigo"]))
		_registrar_tempestade()
	resumo = {"antes": antes, "depois": Recursos.valores.duplicate(), "solar": partes["solar"],
		"desgaste": partes["desgaste"], "tempestade": Missao.tempestade if Missao.dia == Missao.dia_erupcao else {}}
	Missao.historico[-1]["valores"] = Recursos.valores.duplicate()
	_registrar_noite(partes)
	_abrir("noite")


## Acontecimentos do fechamento do dia para o relatório: indicador que ficou baixo agora e equipe machucada.
func _registrar_noite(partes: Dictionary) -> void:
	for nome in Recursos.NOMES:
		var baixo := Recursos.baixo(nome)
		if baixo and not baixos_antes.get(nome, false):
			Missao.registrar_evento(Missao.dia, "critico", "%s LOW" % Recursos.ROTULOS[nome], TEXTOS_CRITICO[nome], nome, 8)
		baixos_antes[nome] = baixo
	if partes["desgaste"] > 0.0 and not baixos_antes.get("desgaste", false):
		Missao.registrar_evento(Missao.dia, "desgaste", "CREW HURT", "Low supplies started to hurt the crew.", "condicao", 6)
		baixos_antes["desgaste"] = true


## A erupção solar na linha do tempo do relatório (uma linha de até ~68 caracteres na página LOG).
func _registrar_tempestade() -> void:
	var tp: Dictionary = Missao.tempestade
	var dano := roundi(tp.get("dano", 0.0))
	var txt := "A proton storm hit. The crew made it to the shelter: -%d health." % dano
	if not tp.get("abrigo", false):
		txt = "A proton storm hit the crew outside the shelter: -%d health." % dano
	Missao.registrar_evento(Missao.dia, "tempestade", "SOLAR STORM", txt, "condicao", 9)


## Página 04 DONKI do relatório: o evento real (eventos_solares.json) em que a erupção da missão se baseou.
## Missao.donki fica no formato que o relatorio.gd espera: {"id", "tipo", "data", "fonte", "relacao"}.
func _preparar_donki() -> void:
	var ev: Dictionary = Missao.evento_solar
	if ev.is_empty():
		return
	var relacao := "This mission's solar storm was modeled on it: %s." % str(ev["titulo"]).to_lower()
	if Missao.tempestade.is_empty():
		relacao = "The solar storm forecast for this mission was modeled on it, but the mission ended first."
	if ev.has("velocidade"):
		relacao += " Its CME left the Sun at %d km/s." % int(ev["velocidade"])
	Missao.donki = {"id": str(ev.get("cme", "")), "tipo": "CME + PROTON STORM", "data": str(ev["data"]),
		"fonte": "arquivo", "relacao": relacao}


func _comecar_dia() -> void:
	hoje = regras["dias"][Missao.dia - 1]["tarefas"].duplicate()
	if Missao.dia == Missao.dia_erupcao and not BLINDAGEM in hoje:
		hoje.append(BLINDAGEM)
	if Missao.dia_erupcao > 0 and Missao.dia == Missao.dia_erupcao + 1 and not VITAIS in hoje:
		hoje.append(VITAIS)
	acoes = 0
	Recursos.noite = eh_noite(Missao.dia)
	Missao.historico.append({"dia": Missao.dia, "noite": Recursos.noite, "acoes": [], "ids": [], "valores": {}})
	if Recursos.noite and not eh_noite(Missao.dia - 1):
		Missao.registrar_evento(Missao.dia, "noite", "LUNAR NIGHT", "The sun faded and the solar panels stopped making power.", "energia", 5)
	mapa.novo_dia()
	_abrir("manha")


func _ultima_noite() -> bool:
	return Recursos.esgotado() != "" or Missao.dia >= total_dias()


func _avancar() -> void:
	match painel:
		"manha":
			_fechar()
		"noite":
			_fechar()
			var zerou := Recursos.esgotado()
			if zerou != "":
				_terminar("abortada", zerou)
			elif Missao.dia >= total_dias():
				var baixos := Recursos.NOMES.filter(func(n): return Recursos.baixo(n))
				_terminar("dificuldades" if not baixos.is_empty() else "concluida")
			else:
				Missao.dia += 1
				noite_fechou.emit()
				_comecar_dia()
		"fim":
			Missao.reiniciar()
			get_tree().change_scene_to_file(TELA_POUSO)


func _terminar(resultado: String, causa := "") -> void:
	Missao.resultado = resultado
	Missao.causa = causa
	mapa.fim = true
	pagina = 0
	_preparar_donki()
	Relatorio.preparar(regras["dias"])
	print("Missao: ", resultado, " no dia ", Missao.dia, " ", Recursos.valores, " erupcao=", Missao.dia_erupcao, " ", Missao.tempestade)
	_abrir("fim")
	if mapa.demo:
		await get_tree().create_timer(4.0).timeout
		get_tree().quit()


func _abrir(p: String) -> void:
	painel = p
	t_painel = 0.0
	tela.visible = true
	mapa.travar(true)
	tela.queue_redraw()


func _fechar() -> void:
	painel = ""
	tela.visible = false
	quadro_fechou = Engine.get_process_frames()
	mapa.travar(false)


func _process(delta: float) -> void:
	if painel == "":
		return
	t_painel += delta
	tela.queue_redraw()
	if t_painel < ESPERA:
		return
	if painel == "fim":
		_navegar_relatorio()
		return
	if Input.is_action_just_pressed("usar") or (mapa.demo and painel != "fim" and t_painel > ESPERA_DEMO):
		_avancar()


func _unhandled_input(ev: InputEvent) -> void:
	if painel == "" or painel == "fim" or t_painel < ESPERA:   # no fim, o mouse é tratado em _clique_relatorio
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_avancar()


## Relatório final: esquerda / direita trocam de página, E avança e, na última página, começa a nova missão.
func _navegar_relatorio() -> void:
	if Input.is_action_just_pressed("direita"):
		_pagina(1)
	elif Input.is_action_just_pressed("esquerda"):
		_pagina(-1)
	elif Input.is_action_just_pressed("usar"):
		if pagina < Relatorio.PAGINAS.size() - 1:
			_pagina(1)
		else:
			_avancar()


func _pagina(delta: int) -> void:
	pagina = clampi(pagina + delta, 0, Relatorio.PAGINAS.size() - 1)
	tela.queue_redraw()


## Mouse no relatório: botões BACK / NEXT (ou NEW MISSION na última página) e as abas.
func _clique_relatorio(ev: InputEvent) -> void:
	if painel != "fim" or t_painel < ESPERA:
		return
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = ev.position
	if Relatorio.BOTAO_VOLTAR.has_point(p):
		_pagina(-1)
	elif pagina == Relatorio.PAGINAS.size() - 1 and Relatorio.BOTAO_NOVA.has_point(p):
		_avancar()
	elif pagina < Relatorio.PAGINAS.size() - 1 and Relatorio.BOTAO_PROXIMO.has_point(p):
		_pagina(1)
	else:
		for i in Relatorio.PAGINAS.size():
			if Relatorio.aba_rect(i).has_point(p):
				pagina = i
				tela.queue_redraw()


# ---------------------------------------------------------------- desenho
func _desenha() -> void:
	match painel:
		"manha":
			_desenha_manha()
		"noite":
			_desenha_noite()
		"fim":
			_desenha_fim()


## Boletim da manhã: dia, noite (sem sol), mensagem do controle, tarefas do dia com o efeito e os recursos baixos.
func _desenha_manha() -> void:
	tela.draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	var largura := 252
	var boletim := quebrar(str(regras["dias"][Missao.dia - 1]["boletim"]), largura - 16)
	var baixos := Recursos.NOMES.filter(func(n): return Recursos.baixo(n))
	var clima := _clima_espacial(largura - 16)
	var linhas := boletim.size() + 2 + hoje.size() + clima.size()
	if Recursos.noite:
		linhas += 1
	if not baixos.is_empty():
		linhas += 1
	var r := _painel(largura, 18 + linhas * 8 + 4)
	moldura(tela, r)
	Fonte.centralizado(tela, "DAY %d OF %d" % [Missao.dia, total_dias()], r.get_center().x, r.position.y + 5, AMARELO)
	var x := r.position.x + 8
	var y := r.position.y + 19
	if Recursos.noite:
		Fonte.desenhar(tela, "LUNAR NIGHT: THE PANELS MAKE NO POWER TODAY", Vector2(x, y), AZUL)
		y += 8
	for l in boletim:
		Fonte.desenhar(tela, l, Vector2(x, y), BRANCO)
		y += 8
	for l in clima:
		Fonte.desenhar(tela, l, Vector2(x, y), VERMELHO if Missao.dia == Missao.dia_erupcao else LARANJA)
		y += 8
	y += 4
	Fonte.desenhar(tela, "TODAY'S TASKS - YOU HAVE TIME FOR %d:" % acoes_por_dia(), Vector2(x, y), METAL)
	y += 8
	for id in hoje:
		var tf: Dictionary = mapa._tarefa(id)
		tela.draw_rect(Rect2(x, y + 1, 3, 3), AMARELO)
		Fonte.desenhar(tela, str(tf["texto"]), Vector2(x + 6, y), BRANCO)
		var efeito: String = mapa.texto_previa(id)
		var cor := AZUL if efeito == mapa.SEM_SOL else METAL_CLARO
		Fonte.desenhar(tela, efeito, Vector2(r.end.x - 8 - Fonte.largura(efeito), y), cor)
		y += 8
	if not baixos.is_empty():
		y += 4
		var nomes := PackedStringArray(baixos.map(func(n): return Recursos.ROTULOS[n]))
		Fonte.desenhar(tela, "RUNNING LOW: " + ", ".join(nomes), Vector2(x, y), VERMELHO)
	Fonte.centralizado_com_teclas(tela, "[E] START THE DAY", 160, r.end.y + 4, METAL, VERMELHO)


## Previsão do clima espacial no boletim: na véspera da erupção, o aviso; no dia, o que fazer quando o alarme tocar.
func _clima_espacial(largura: float) -> Array[String]:
	if Missao.dia_erupcao == 0:
		return []
	if Missao.dia == Missao.dia_erupcao - 1:
		return quebrar("SPACE WEATHER: solar activity rising. A solar storm is likely tomorrow. Reinforcing the shielding cuts the dose. Details on the navigation computer.", largura)
	if Missao.dia == Missao.dia_erupcao:
		return quebrar("SOLAR STORM TODAY: when the alarm sounds, run to the shielded shelter.", largura)
	if Missao.dia == Missao.dia_erupcao + 1:
		return quebrar("AFTER THE STORM: the crew took a radiation dose. Check their vitals at the bunks in the habitat.", largura)
	return []


## Resumo da noite: cada indicador antes e depois (barra, números e diferença), a geração solar e o desgaste.
func _desenha_noite() -> void:
	var largura := 216
	var linhas := Recursos.NOMES.size() + 2
	if resumo["desgaste"] > 0.0:
		linhas += 1
	if not resumo["tempestade"].is_empty():
		linhas += 1
	var r := _painel(largura, 18 + linhas * 8 + 6)
	moldura(tela, r)
	Fonte.centralizado(tela, "END OF DAY %d" % Missao.dia, r.get_center().x, r.position.y + 5, AMARELO)
	var x := r.position.x + 8
	var y := r.position.y + 19
	for nome in Recursos.NOMES:
		var antes: float = resumo["antes"][nome]
		var depois: float = resumo["depois"][nome]
		_linha_indicador(nome, Vector2(x, y), r.end.x - 8, depois, antes)
		y += 8
	y += 4
	if resumo["solar"] > 0.0:
		Fonte.desenhar(tela, "SOLAR PANELS: %+d POWER" % roundi(resumo["solar"]), Vector2(x, y), AMARELO)
	else:
		Fonte.desenhar(tela, "LUNAR NIGHT: NO SOLAR POWER", Vector2(x, y), AZUL)
	y += 8
	if resumo["desgaste"] > 0.0:
		Fonte.desenhar(tela, "LOW SUPPLIES HURT THE CREW: %+d HEALTH" % -roundi(resumo["desgaste"]),
			Vector2(x, y), VERMELHO)
		y += 8
	if not resumo["tempestade"].is_empty():
		var tp: Dictionary = resumo["tempestade"]
		var onde := "SHELTERED" if tp["abrigo"] else "CAUGHT OUTSIDE"
		Fonte.desenhar(tela, "SOLAR STORM, %s: %+d HEALTH" % [onde, -roundi(tp.get("dano", 0.0))], Vector2(x, y),
			LARANJA if tp["abrigo"] else VERMELHO)
	var dica := "[E] MISSION RESULT" if _ultima_noite() else "[E] NEXT DAY"
	Fonte.centralizado_com_teclas(tela, dica, 160, r.end.y + 4, METAL, VERMELHO)


## Fim da missão: o relatório de 4 páginas (relatorio.gd) dentro da mesma moldura de metal dos outros painéis.
func _desenha_fim() -> void:
	tela.draw_rect(Rect2(0, 0, 320, 180), PRETO)
	Relatorio.fundo(tela)
	moldura(tela, Relatorio.MOLDURA)
	Relatorio.desenhar(tela, pagina)


## Nome, barra de 60 px e valor do indicador. Com `antes`, mostra a parte perdida em vermelho escuro ou a ganha
## na cor do indicador mais clara, e "60 > 51  -9" à direita (alinhado em x_fim).
func _linha_indicador(nome: String, pos: Vector2, x_fim: float, v: float, antes := -1.0) -> void:
	var cor: Color = Recursos.CORES[nome]
	Fonte.desenhar(tela, Recursos.ROTULOS[nome], pos, cor)
	var barra := Rect2(pos.x + 30, pos.y, 60, 5)
	tela.draw_rect(barra, CINZA_ESC)
	var w := roundf(barra.size.x * v / 100.0)
	tela.draw_rect(Rect2(barra.position, Vector2(w, 5)), VERMELHO if Recursos.baixo(nome) else cor)
	var txt := str(ceili(v))
	if antes >= 0.0:
		var wa := roundf(barra.size.x * antes / 100.0)
		if wa > w:
			tela.draw_rect(Rect2(barra.position.x + w, barra.position.y, wa - w, 5), Color(VERMELHO, 0.45))
		var d := ceili(v) - ceili(antes)
		var s := "%+d" % d if d != 0 else "0"
		Fonte.desenhar(tela, s, Vector2(x_fim - Fonte.largura(s), pos.y), VERDE if d > 0 else (VERMELHO if d < 0 else CINZA))
		txt = "%d > %d" % [ceili(antes), ceili(v)]
		Fonte.desenhar(tela, txt, Vector2(barra.end.x + 6, pos.y), BRANCO)
	else:
		Fonte.desenhar(tela, txt, Vector2(barra.end.x + 6, pos.y), BRANCO)


func _painel(largura: float, altura: float) -> Rect2:
	return Rect2(round((320 - largura) / 2.0), round((180 - altura) / 2.0) - 4, largura, altura)


## Quebra o texto em linhas que cabem em `largura` px na fonte 3x5.
static func quebrar(texto: String, largura: float) -> Array[String]:
	var linhas: Array[String] = []
	var atual := ""
	for p in texto.split(" ", false):
		var tentativa := p if atual == "" else atual + " " + p
		if Fonte.largura(tentativa) > largura and atual != "":
			linhas.append(atual)
			atual = p
		else:
			atual = tentativa
	if atual != "":
		linhas.append(atual)
	return linhas


## Mesma moldura de metal do menu de pausa: borda preta, chanfro claro em cima/esquerda e rebites nos cantos.
static func moldura(ci: CanvasItem, p: Rect2) -> void:
	ci.draw_rect(p, PRETO)
	ci.draw_rect(p.grow(-1), CINZA)
	ci.draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(p.size.x - 2, 1)), METAL_CLARO)
	ci.draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(1, p.size.y - 2)), METAL)
	ci.draw_rect(Rect2(p.position + Vector2(2, p.size.y - 2), Vector2(p.size.x - 3, 1)), CINZA_ESC)
	ci.draw_rect(Rect2(p.position + Vector2(p.size.x - 2, 2), Vector2(1, p.size.y - 3)), CINZA_ESC)
	for c in [Vector2(3, 3), Vector2(p.size.x - 6, 3), Vector2(3, p.size.y - 6), Vector2(p.size.x - 6, p.size.y - 6)]:
		ci.draw_rect(Rect2(p.position + c, Vector2(3, 3)), METAL)
		ci.draw_rect(Rect2(p.position + c + Vector2.ONE, Vector2.ONE), CINZA_ESC)
	ci.draw_rect(Rect2(p.position + Vector2(8, 3), Vector2(p.size.x - 16, 10)), FUNDO)
	ci.draw_rect(Rect2(p.position + Vector2(4, 15), Vector2(p.size.x - 8, p.size.y - 19)), Color(PRETO, 0.35))
