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
const ARQUIVO := "res://dados/dias.json"
const TELA_POUSO := "res://cenas/escolha_pouso.tscn"
const EVENTOS_SOLARES := "res://dados/eventos_solares.json"
const BLINDAGEM := "abrigo/blindagem"         # o dia da erupção sempre oferece reforçar a blindagem
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
const TITULOS_FIM := {"concluida": "MISSION COMPLETE", "dificuldades": "MISSION COMPLETE WITH DIFFICULTIES",
	"abortada": "MISSION ABORTED"}
const CORES_FIM := {"concluida": VERDE, "dificuldades": AMARELO, "abortada": VERMELHO}
const CAUSAS := {"energia": "The base lost all power", "oxigenio": "The oxygen ran out",
	"comida": "The food ran out", "condicao": "The crew became too sick to work"}

var mapa: Node2D                   # o mapa.gd (quem cria preenche)
var regras: Dictionary = {}
var hoje: Array = []               # ids ("sala/tarefa") das tarefas oferecidas hoje
var acoes := 0                     # ações gastas hoje
var painel := ""                   # "manha", "noite", "fim" ou "" (sem painel: o jogo corre)
var resumo := {}                   # da última noite: {"antes": {...}, "depois": {...}, "solar": 4.2, "desgaste": 0}
var t_painel := 0.0
var quadro_fechou := -1
var tela: Control


func _ready() -> void:
	layer = 15                     # acima do HUD, abaixo do menu de pausa (20)
	regras = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	tela = Control.new()
	tela.size = Vector2(320, 180)
	tela.visible = false
	tela.draw.connect(_desenha)
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
func registrar(tf: Dictionary) -> void:
	acoes += 1
	Missao.historico[-1]["acoes"].append(str(tf["texto"]))


## Aba DEV: devolve as ações do dia.
func zerar_dia() -> void:
	acoes = 0
	Missao.historico[-1]["acoes"].clear()


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
	resumo = {"antes": antes, "depois": Recursos.valores.duplicate(), "solar": partes["solar"],
		"desgaste": partes["desgaste"], "tempestade": Missao.tempestade if Missao.dia == Missao.dia_erupcao else {}}
	Missao.historico[-1]["valores"] = Recursos.valores.duplicate()
	_abrir("noite")


func _comecar_dia() -> void:
	hoje = regras["dias"][Missao.dia - 1]["tarefas"].duplicate()
	if Missao.dia == Missao.dia_erupcao and not BLINDAGEM in hoje:
		hoje.append(BLINDAGEM)
	acoes = 0
	Recursos.noite = eh_noite(Missao.dia)
	Missao.historico.append({"dia": Missao.dia, "noite": Recursos.noite, "acoes": [], "valores": {}})
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
	if Input.is_action_just_pressed("usar") or (mapa.demo and painel != "fim" and t_painel > ESPERA_DEMO):
		_avancar()


func _unhandled_input(ev: InputEvent) -> void:
	if painel == "" or t_painel < ESPERA:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_avancar()


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
	Fonte.centralizado(tela, "E: START THE DAY", 160, r.end.y + 4, METAL)


## Previsão do clima espacial no boletim: na véspera da erupção, o aviso; no dia, o que fazer quando o alarme tocar.
func _clima_espacial(largura: float) -> Array[String]:
	if Missao.dia_erupcao == 0:
		return []
	if Missao.dia == Missao.dia_erupcao - 1:
		return quebrar("SPACE WEATHER: solar activity rising. A solar storm is likely tomorrow. Reinforcing the shielding cuts the dose.", largura)
	if Missao.dia == Missao.dia_erupcao:
		return quebrar("SOLAR STORM TODAY: when the alarm sounds, run to the shielded shelter.", largura)
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
	var dica := "E: MISSION RESULT" if _ultima_noite() else "E: NEXT DAY"
	Fonte.centralizado(tela, dica, 160, r.end.y + 4, METAL)


## Fim da missão: resultado, causa, local, indicadores finais e o diário (o que foi feito em cada dia).
func _desenha_fim() -> void:
	tela.draw_rect(Rect2(0, 0, 320, 180), PRETO)
	var r := Rect2(8, 6, 304, 160)
	moldura(tela, r)
	var res := Missao.resultado
	Fonte.centralizado(tela, TITULOS_FIM[res], 160, r.position.y + 5, CORES_FIM[res])
	var x := r.position.x + 10
	var y := r.position.y + 19
	for l in quebrar(_frase_fim(), r.size.x - 20):
		Fonte.desenhar(tela, l, Vector2(x, y), BRANCO)
		y += 8
	Fonte.desenhar(tela, "LANDING SITE: " + str(Missao.dados_local.get("titulo", "")), Vector2(x, y), METAL)
	y += 12
	for nome in Recursos.NOMES:
		_linha_indicador(nome, Vector2(x, y), x + 150, Recursos.valores[nome])
		y += 8
	y += 4
	Fonte.desenhar(tela, "MISSION LOG", Vector2(x, y), AMARELO)
	y += 8
	for d in Missao.historico:
		var feito := ", ".join(PackedStringArray(d["acoes"])) if not d["acoes"].is_empty() else "NO TASKS DONE"
		var txt := "DAY %d: %s" % [d["dia"], feito]
		Fonte.desenhar(tela, txt, Vector2(x, y), BRANCO if not d["acoes"].is_empty() else CINZA)
		if d["noite"]:
			Fonte.desenhar(tela, "NIGHT", Vector2(r.end.x - 10 - Fonte.largura("NIGHT"), y), AZUL)
		y += 8
	if not Missao.tempestade.is_empty():
		var tp: Dictionary = Missao.tempestade
		y += 4
		var onde := "SAFE IN THE SHELTER" if tp["abrigo"] else "CAUGHT OUTSIDE THE SHELTER"
		Fonte.desenhar(tela, "SOLAR STORM, DAY %d: %s (%+d HEALTH)" % [tp["dia"], onde, -roundi(tp.get("dano", 0.0))],
			Vector2(x, y), LARANJA if tp["abrigo"] else VERMELHO)
		y += 8
		var ev: Dictionary = Missao.evento_solar
		if not ev.is_empty():
			for l in quebrar("REAL EVENT (NASA DONKI): %s, %s" % [ev["data"], ev["titulo"]], r.size.x - 20).slice(0, 2):
				Fonte.desenhar(tela, l, Vector2(x, y), METAL)
				y += 8
	Fonte.centralizado(tela, "E: NEW MISSION", 160, r.end.y + 4, METAL)


func _frase_fim() -> String:
	match Missao.resultado:
		"abortada":
			return "%s on day %d. The mission was aborted and the crew returned to Orion." % [
				CAUSAS[Missao.causa], Missao.dia]
		"dificuldades":
			var baixos := Recursos.NOMES.filter(func(n): return Recursos.baixo(n))
			var nomes := PackedStringArray(baixos.map(func(n): return Recursos.ROTULOS[n]))
			return "The crew made it to day %d, but the base is in bad shape. Running low: %s." % [
				total_dias(), ", ".join(nomes)]
	return "All systems held for %d days. The base is ready for the next crew." % total_dias()


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
