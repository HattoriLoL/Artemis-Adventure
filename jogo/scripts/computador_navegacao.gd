extends Control
## Computador de navegação (ARTEMIS-OS), na mesa de monitores do Suporte (interação "computador" em
## salas/suporte.json; consultar não gasta ação do dia). 4 janelas com o que a base sabe da missão:
##   1 SPACE WEATHER  o Sol agora (calmo, CME detectada na véspera, tempestade, depois dela), a dose da erupção com a
##                    blindagem de agora e o arquivo de eventos reais do NASA DONKI (dados/eventos_solares.json)
##   2 MISSION LOG    o diário de cada dia (tarefas feitas e perdidas, a tempestade, os recursos no fim do dia)
##   3 FORECAST       os dias da missão: sol ou noite lunar (pelo local de pouso), risco solar e tarefas previstas
##   4 BASE STATUS    os 4 recursos, o que a noite vai cobrar deles e a blindagem
## Nada aqui adianta o dia sorteado da erupção: ela só aparece a partir do boletim da véspera, como no resto do jogo.
## O computador, o visual (barra ARTEMIS-OS, abas, barras de risco, efeito CRT) e o uso do NASA DONKI vieram do
## PR #24 (IltonBJSilva); adaptado ao ciclo de 5 dias, aos textos em inglês e aos dados reais do jogo.
## Contrato com o mapa: sinal `fechou` (Esc ou clique no X); o mapa preenche `mapa`.

signal fechou

const Fonte = preload("res://scripts/fonte.gd")
const Ciclo = preload("res://scripts/ciclo_dias.gd")
const EVENTOS := "res://dados/eventos_solares.json"
const BLINDAGEM := "abrigo/blindagem"
const VITAIS := "habitat/vitais"
const HORIZONTE := 2                  # dias à frente que o modelo solar enxerga (o boletim só vê 1)

const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const LARANJA := Color("#de9e41")
const AZUL := Color("#73bed3")
const CINZA := Color("#819796")
const CINZA_ESC := Color("#394a50")
const PRETO := Color("#090a14")
const TELA := Color("#060a0f")
const CAIXA := Color("#0d1622")
const LINHA := Color("#182635")

const ABAS := ["1 SPACE WEATHER", "2 MISSION LOG", "3 FORECAST", "4 BASE STATUS"]
const BOTAO_X := Rect2(293, 14, 8, 8)
const RODAPES := ["[1-4/TAB] WINDOW   [A/D] BROWSE DONKI EVENTS   [ESC] CLOSE",
	"[1-4/TAB] WINDOW   [A/D] CHANGE DAY   [ESC] CLOSE",
	"[1-4/TAB] WINDOW   [W/S] SELECT DAY   [ESC] CLOSE",
	"[1-4/TAB] WINDOW   [ESC] CLOSE"]

var mapa: Node2D                       # o mapa.gd (quem abre preenche)
var aba := 0
var evento := 0                        # registro do DONKI na janela 1
var dia_log := 1                       # dia na janela 2
var dia_prev := 1                      # dia selecionado na janela 3
var eventos: Array = []
var t := 0.0
var som: AudioStreamPlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dados: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTOS))
	if dados is Dictionary:
		eventos = dados.get("eventos", [])
	dia_log = maxi(1, Missao.dia)
	dia_prev = dia_log
	som = AudioStreamPlayer.new()
	som.volume_db = -20.0
	add_child(som)
	_bipe([880.0, 1320.0], 0.06)                                  # ligou


func _total() -> int:
	return mapa.ciclo.total_dias() if mapa else 5


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_clique(get_local_mouse_position())
		get_viewport().set_input_as_handled()
		return
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	if ev.is_action_pressed("ui_cancel"):
		_fechar()
	else:
		match ev.physical_keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				_mudar_aba(ev.physical_keycode - KEY_1)
			KEY_TAB:
				_mudar_aba((aba + (ABAS.size() - 1 if ev.shift_pressed else 1)) % ABAS.size())
			KEY_A, KEY_LEFT, KEY_W, KEY_UP:
				_passar(-1)
			KEY_D, KEY_RIGHT, KEY_S, KEY_DOWN:
				_passar(1)
	get_viewport().set_input_as_handled()


## Mouse: o X, as abas, as setas (< A / D >) do DONKI e do diário e as linhas da previsão.
func _clique(p: Vector2) -> void:
	if BOTAO_X.grow(2).has_point(p):
		_fechar()
		return
	for i in ABAS.size():
		if _ret_aba(i).has_point(p):
			_mudar_aba(i)
			return
	match aba:
		0:
			if Rect2(250, 108, 50, 9).has_point(p):                 # "< A   D >" do arquivo do DONKI
				_passar(-1 if p.x < 278 else 1)
		1:
			if Rect2(20, 38, 60, 12).has_point(p):
				_passar(-1)
			elif Rect2(240, 38, 60, 12).has_point(p):
				_passar(1)
		2:
			for d in range(1, _total() + 1):
				if Rect2(20, 55 + (d - 1) * 10, 280, 9).has_point(p) and d != dia_prev:
					dia_prev = d
					_bipe([1200.0], 0.025)


func _mudar_aba(i: int) -> void:
	if i != aba:
		aba = i
		_bipe([1040.0], 0.035)


func _passar(d: int) -> void:
	var antes := [evento, dia_log, dia_prev]
	match aba:
		0:
			if not eventos.is_empty():
				evento = posmod(evento + d, eventos.size())
		1:
			dia_log = clampi(dia_log + d, 1, _total())
		2:
			dia_prev = clampi(dia_prev + d, 1, _total())
	if antes != [evento, dia_log, dia_prev]:
		_bipe([1200.0], 0.025)


## Bipe de terminal feito no código (onda quadrada suave), como a sirene da erupção: um tom por item de `tons`.
func _bipe(tons: Array, dur: float) -> void:
	var taxa := 22050
	var n_tom := int(taxa * dur)
	var dados := PackedByteArray()
	dados.resize(n_tom * tons.size() * 2)
	var fase := 0.0
	for k in tons.size():
		for i in n_tom:
			fase += TAU * float(tons[k]) / taxa
			var env := minf(1.0, minf(float(i), float(n_tom - i)) / 60.0)          # sem estalo nas pontas
			dados.encode_s16((k * n_tom + i) * 2, int((0.5 if sin(fase) > 0.0 else -0.5) * env * 9000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = taxa
	s.data = dados
	som.stream = s
	som.play()


func _fechar() -> void:
	if is_queued_for_deletion():
		return
	set_process_input(false)
	fechou.emit()
	queue_free()


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


# ---------------------------------------------------------------- o que a base sabe do Sol
## O Sol num dia da missão, só com o que o computador sabe hoje. O modelo enxerga HORIZONTE dias à frente: dois
## dias antes da erupção ele já avisa que ela é possível (o boletim da manhã só avisa na véspera), então quem
## consulta o computador ganha um dia para reforçar a blindagem. {titulo, risco, cor, barra (0 a 10), vento, nota}
## Na CME, a velocidade é a real do evento do DONKI sorteado para a missão (eventos_solares.json).
func _sol(d: int) -> Dictionary:
	var e := Missao.dia_erupcao
	var hoje := Missao.dia
	var passou := not Missao.tempestade.is_empty()
	var v := int(Missao.evento_solar.get("velocidade", 1200))
	var vel := "%d KM/S" % v
	var calmo := {"titulo": "QUIET SUN", "risco": "LOW", "cor": VERDE, "barra": 2, "vento": "350 KM/S",
		"nota": "NO ALERTS FROM NASA DONKI. ROUTINE WORK OUTSIDE IS SAFE."}
	if e == 0:
		return calmo
	if d == e and (hoje > e or (hoje == e and passou)):
		var tp: Dictionary = Missao.tempestade
		var onde := "THE CREW REACHED THE SHELTER" if tp.get("abrigo", false) else "THE CREW WAS CAUGHT OUTSIDE"
		var dano := " (-%d HEALTH)" % roundi(tp["dano"]) if tp.has("dano") else ""
		return {"titulo": "PROTON STORM HIT THE BASE", "risco": "CRITICAL", "cor": VERMELHO, "barra": 10,
			"vento": vel, "nota": onde + dano + "."}
	if d == e and hoje == e:
		return {"titulo": "PROTON STORM TODAY", "risco": "CRITICAL", "cor": VERMELHO, "barra": 10, "vento": vel,
			"nota": "WHEN THE ALARM SOUNDS, RUN TO THE SHIELDED SHELTER."}
	if d > hoje + HORIZONTE:             # além do horizonte o modelo não garante nada (nem "calmo")
		return {"titulo": "NO DATA YET", "risco": "UNKNOWN", "cor": CINZA, "barra": 0, "vento": "--",
			"nota": "THE SOLAR MODEL ONLY SEES ABOUT TWO DAYS AHEAD. CHECK AGAIN LATER."}
	if d == e and hoje == e - 1:
		return {"titulo": "CME IMPACT EXPECTED", "risco": "CRITICAL", "cor": VERMELHO, "barra": 9, "vento": vel,
			"nota": "A PROTON STORM WILL HIT THE BASE THIS DAY. SHIELD THE SHELTER."}
	if d == e and hoje == e - 2:         # o alerta antecipado: só o computador sabe
		return {"titulo": "STORM POSSIBLE", "risco": "HIGH", "cor": LARANJA, "barra": 6, "vento": "--",
			"nota": "AN ACTIVE SUNSPOT REGION IS TURNING TOWARD THE MOON. SHIELD EARLY."}
	if d == e - 1 and hoje >= e - 1:
		return {"titulo": "CME DETECTED", "risco": "HIGH", "cor": LARANJA, "barra": 7, "vento": vel,
			"nota": "CME AT %s ON ITS WAY: REACHES THE MOON IN ABOUT %d HOURS." % [vel, _horas_ate_lua(v)]}
	if d == e + 1 and hoje >= e - 1:
		return {"titulo": "STORM DECAYING", "risco": "MODERATE", "cor": AMARELO, "barra": 4, "vento": "560 KM/S",
			"nota": "PARTICLE FLUX FALLING BACK TO NORMAL LEVELS."}
	return calmo


## Quanto a CME leva do Sol à Lua (1 UA) na velocidade medida, sem contar a desaceleração no caminho.
func _horas_ate_lua(v: int) -> int:
	return roundi(149.6e6 / maxf(1.0, float(v)) / 3600.0)


## O pior risco que o computador vê de hoje até o horizonte (o LED da barra de título e a setinha do mapa).
func risco_a_frente() -> int:
	var pior := 0
	for d in range(Missao.dia, mini(Missao.dia + HORIZONTE, _total()) + 1):
		pior = maxi(pior, int(_sol(d)["barra"]))
	return pior


## Tarefas previstas num dia (as de dias.json; no dia da erupção, já conhecido, também a blindagem).
func _tarefas_do_dia(d: int) -> Array:
	var ids: Array = mapa.ciclo.hoje.duplicate() if d == Missao.dia else \
		mapa.ciclo.regras["dias"][d - 1]["tarefas"].duplicate()
	if d == Missao.dia_erupcao and Missao.dia >= d - 1 and not BLINDAGEM in ids:
		ids.append(BLINDAGEM)
	if d == Missao.dia_erupcao + 1 and Missao.dia >= Missao.dia_erupcao - 1 and not VITAIS in ids:
		ids.append(VITAIS)
	var nomes := []
	for id in ids:
		var tf: Dictionary = mapa._tarefa(id)
		if not tf.is_empty():
			nomes.append(str(tf["texto"]))
	return nomes


func _noite(d: int) -> bool:
	return mapa.ciclo.eh_noite(d)


func _geracao_solar() -> int:
	return roundi(float(Recursos.regras["geracao_solar_por_dia"]) * float(Missao.condicoes.get("geracao_solar", 1.0)))


func _site() -> String:
	return str(Missao.dados_local.get("titulo", "LUNAR")).to_upper()


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.75))
	draw_rect(Rect2(11, 7, 298, 166), PRETO)                     # monitor
	draw_rect(Rect2(12, 8, 296, 164), Color("#2e383f"))
	draw_rect(Rect2(12, 8, 296, 1), Color("#4d5b62"))
	draw_rect(Rect2(16, 12, 288, 156), TELA)
	_barra_titulo()
	for i in ABAS.size():
		_aba(i)
	draw_rect(Rect2(16, 35, 288, 1), Color("#285264"))
	match aba:
		0: _janela_clima()
		1: _janela_diario()
		2: _janela_previsao()
		3: _janela_base()
	for y in range(36, 155, 3):                                   # efeito CRT
		draw_rect(Rect2(16, y, 288, 1), Color(0, 0, 0, 0.12))
	draw_rect(Rect2(16, 155, 288, 13), Color("#0a0f16"))
	draw_rect(Rect2(16, 155, 288, 1), Color("#1b2b38"))
	Fonte.desenhar(self, RODAPES[aba], Vector2(22, 159), CINZA)


func _barra_titulo() -> void:
	draw_rect(Rect2(16, 12, 288, 12), Color("#0e151f"))
	Fonte.desenhar(self, "ARTEMIS-OS V2.4", Vector2(20, 15), AMARELO)
	Fonte.desenhar(self, "%s BASE // DAY %d OF %d" % [_site(), Missao.dia, _total()], Vector2(88, 15), BRANCO)
	var pior := risco_a_frente()                                  # LED: o pior risco até o horizonte; pisca no alerta
	var cor := VERMELHO if pior >= 9 else (LARANJA if pior >= 6 else (AMARELO if pior >= 4 else VERDE))
	if pior >= 6 and fmod(t, 0.8) < 0.4:
		cor = Color(cor, 0.25)
	draw_rect(Rect2(281, 16, 4, 4), cor)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), Color("#a53030"))
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)


func _ret_aba(i: int) -> Rect2:
	return Rect2(18 + i * 71, 24, 69, 10)


func _aba(i: int) -> void:
	var r := _ret_aba(i)
	if i == aba:
		draw_rect(r, Color("#1f3342"))
		draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), AMARELO)
		Fonte.desenhar(self, ABAS[i], r.position + Vector2(3, 2), AMARELO)
	else:
		draw_rect(r, Color("#0d141d"))
		Fonte.desenhar(self, ABAS[i], r.position + Vector2(3, 2), CINZA)


## Caixa com a faixa colorida à esquerda (o estilo das janelas do PR #24).
func _caixa(r: Rect2, cor: Color) -> void:
	draw_rect(r, CAIXA)
	draw_rect(Rect2(r.position, Vector2(3, r.size.y)), cor)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), LINHA)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), LINHA)


func _direita(txt: String, x_fim: float, y: float, cor: Color) -> void:
	Fonte.desenhar(self, txt, Vector2(x_fim - Fonte.largura(txt), y), cor)


func _barras(x: float, y: float, n: int, cor: Color) -> void:
	for b in 10:
		draw_rect(Rect2(x + b * 4, y, 3, 5), cor if b < n else Color("#141d24"))


# ---------------------------------------------------------------- janela 1: clima espacial
func _janela_clima() -> void:
	var s := _sol(Missao.dia)
	var cor: Color = s["cor"]
	_caixa(Rect2(20, 38, 280, 28), cor)
	Fonte.desenhar(self, "STATUS: " + str(s["titulo"]), Vector2(26, 41), cor)
	_direita("SOLAR WIND: " + str(s["vento"]), 296, 41, BRANCO)
	Fonte.desenhar(self, "RISK: " + str(s["risco"]), Vector2(26, 49), cor)
	_barras(110, 49, int(s["barra"]), cor)
	_direita("NASA DONKI / SDO", 296, 49, CINZA)
	Fonte.desenhar(self, str(s["nota"]), Vector2(26, 57), BRANCO)

	# os próximos dias que o modelo enxerga (onde aparece o alerta antecipado)
	var pior := 0
	var x := 26.0
	for d in range(Missao.dia + 1, mini(Missao.dia + HORIZONTE, _total()) + 1):
		pior = maxi(pior, int(_sol(d)["barra"]))
	_caixa(Rect2(20, 69, 280, 12), LARANJA if pior >= 6 else VERDE)
	Fonte.desenhar(self, "OUTLOOK:", Vector2(x, 72), CINZA)
	x += Fonte.largura("OUTLOOK:") + 6
	if Missao.dia >= _total():
		Fonte.desenhar(self, "LAST DAY OF THE MISSION", Vector2(x, 72), CINZA)
	for d in range(Missao.dia + 1, mini(Missao.dia + HORIZONTE, _total()) + 1):
		var sd := _sol(d)
		var txt := "DAY %d %s" % [d, sd["titulo"]]
		Fonte.desenhar(self, txt, Vector2(x, 72), sd["cor"])
		x += Fonte.largura(txt) + 10

	# a blindagem de agora e quanto a erupção tiraria da saúde
	var n := Missao.blindagem
	_caixa(Rect2(20, 84, 280, 20), VERDE if n > 0 else LARANJA)
	Fonte.desenhar(self, "SHELTER SHIELDING: %d %s" % [n, "REINFORCEMENT" if n == 1 else "REINFORCEMENTS"],
		Vector2(26, 87), VERDE if n > 0 else LARANJA)
	Fonte.desenhar(self, "STORM DOSE: IN THE SHELTER -%d HEALTH / OUTSIDE -%d HEALTH" % [
		roundi(Recursos.dano_tempestade(true)), roundi(Recursos.dano_tempestade(false))], Vector2(26, 95), BRANCO)

	# arquivo de eventos reais do DONKI (com a CME e a velocidade medidas)
	_caixa(Rect2(20, 107, 280, 45), AMARELO)
	if eventos.is_empty():
		return
	var ev: Dictionary = eventos[evento]
	Fonte.desenhar(self, "NASA DONKI ARCHIVE - REAL EVENT %d/%d" % [evento + 1, eventos.size()], Vector2(26, 110),
		AMARELO)
	_direita("< A   D >", 296, 110, CINZA)
	Fonte.desenhar(self, str(ev["data"]), Vector2(26, 119), AZUL)
	Fonte.desenhar(self, str(ev["titulo"]), Vector2(26 + Fonte.largura(str(ev["data"])) + 8, 119), BRANCO)
	var y := 128
	if ev.has("velocidade"):
		var cme := str(ev.get("cme", "")).replace("T", " ").replace("Z", " UTC")   # o Z da fonte 3x5 parece um 2
		Fonte.desenhar(self, "CME %s - %d KM/S - MOON IN ABOUT %d H" % [cme, int(ev["velocidade"]),
			_horas_ate_lua(int(ev["velocidade"]))], Vector2(26, y), LARANJA)
		y += 8
	# depois da tempestade, o evento em que ela se baseou ganha uma linha verde (no lugar da 2ª linha do texto)
	var modelo := not Missao.tempestade.is_empty() and str(ev["data"]) == str(Missao.evento_solar.get("data", ""))
	var linhas := Ciclo.quebrar(str(ev["detalhe"]), 266).slice(0, 1 if modelo else 2)
	for l in linhas:
		Fonte.desenhar(self, l, Vector2(26, y), CINZA)
		y += 8
	if modelo:
		Fonte.desenhar(self, "THIS MISSION'S STORM WAS MODELED ON THIS EVENT.", Vector2(26, y), VERDE)


# ---------------------------------------------------------------- janela 2: diário de bordo
func _janela_diario() -> void:
	draw_rect(Rect2(20, 38, 280, 12), CAIXA)
	Fonte.desenhar(self, "< A", Vector2(24, 41), AMARELO if dia_log > 1 else CINZA_ESC)
	Fonte.centralizado(self, "DAY %d OF %d" % [dia_log, _total()], 160, 41, BRANCO)
	_direita("D >", 296, 41, AMARELO if dia_log < _total() else CINZA_ESC)
	if dia_log > Missao.dia or dia_log > Missao.historico.size():
		_caixa(Rect2(20, 54, 280, 24), CINZA)
		Fonte.desenhar(self, "DAY %d: LOCKED" % dia_log, Vector2(26, 58), LARANJA)
		Fonte.desenhar(self, "THIS DAY HAS NOT STARTED YET. THE LOG IS WRITTEN AS IT HAPPENS.", Vector2(26, 67),
			CINZA)
		return
	var h: Dictionary = Missao.historico[dia_log - 1]
	var fechado := not (h.get("valores", {}) as Dictionary).is_empty()
	var noite: bool = h.get("noite", false)
	var cor := VERDE if fechado else AMARELO
	_caixa(Rect2(20, 54, 280, 98), cor)
	Fonte.desenhar(self, "DAY %d - %s" % [dia_log, "LUNAR NIGHT" if noite else "DAYLIGHT"], Vector2(26, 58),
		AZUL if noite else AMARELO)
	_direita("[LOG CLOSED]" if fechado else "[SHIFT IN PROGRESS]", 296, 58, cor)
	var y := 70
	Fonte.desenhar(self, "TASKS:", Vector2(26, y), CINZA)
	y += 9
	var acoes: Array = h.get("acoes", [])
	if acoes.is_empty():
		Fonte.desenhar(self, "- NONE" if fechado else "- NONE YET", Vector2(30, y), CINZA)
		y += 9
	for a in acoes:
		var falhou := str(a).ends_with("(FAILED)")
		Fonte.desenhar(self, "- " + str(a), Vector2(30, y), VERMELHO if falhou else BRANCO)
		y += 9
	var tp: Dictionary = Missao.tempestade
	if int(tp.get("dia", 0)) == dia_log:
		y += 3
		var onde := "REACHED THE SHELTER" if tp.get("abrigo", false) else (
			"CAUGHT IN BED, OUTSIDE THE SHELTER" if tp.get("dormindo", false) else "CAUGHT OUTSIDE THE SHELTER")
		var dano := " -%d HEALTH" % roundi(tp["dano"]) if tp.has("dano") else ""
		Fonte.desenhar(self, "SOLAR STORM: " + onde + dano, Vector2(26, y), VERMELHO)
	if fechado:
		var v: Dictionary = h["valores"]
		var limite := float(Recursos.regras["limite_baixo"])
		Fonte.desenhar(self, "END OF DAY:", Vector2(26, 134), CINZA)
		var x := 26.0
		for nome in Recursos.NOMES:
			var valor: float = v.get(nome, 0.0)
			var txt := "%s %d" % [Recursos.ROTULOS[nome], roundi(valor)]
			Fonte.desenhar(self, txt, Vector2(x, 143), VERMELHO if valor < limite else BRANCO)
			x += Fonte.largura(txt) + 12


# ---------------------------------------------------------------- janela 3: previsão
func _janela_previsao() -> void:
	Fonte.desenhar(self, "%d-DAY FORECAST // WSA-ENLIL MODEL + NASA DONKI" % _total(), Vector2(22, 38), AZUL)
	Fonte.desenhar(self, "DAY", Vector2(30, 47), CINZA)
	Fonte.desenhar(self, "LIGHT", Vector2(62, 47), CINZA)
	Fonte.desenhar(self, "SOLAR RISK", Vector2(104, 47), CINZA)
	Fonte.desenhar(self, "TASKS", Vector2(250, 47), CINZA)
	var y := 55.0
	for d in range(1, _total() + 1):
		var sel := d == dia_prev
		var hoje := d == Missao.dia
		draw_rect(Rect2(20, y, 280, 9), Color("#182937") if sel else (Color("#101822") if hoje else Color("#080e15")))
		if sel:
			draw_rect(Rect2(20, y, 2, 9), AMARELO)
		elif hoje:
			draw_rect(Rect2(20, y, 2, 9), AZUL)
		var s := _sol(d)
		var cor: Color = s["cor"]
		Fonte.desenhar(self, "DAY %d" % d, Vector2(30, y + 2), AMARELO if sel else (AZUL if hoje else BRANCO))
		var noite := _noite(d)
		Fonte.desenhar(self, "NIGHT" if noite else "SUN", Vector2(62, y + 2), AZUL if noite else AMARELO)
		_barras(104, y + 2, int(s["barra"]), cor)
		Fonte.desenhar(self, str(s["risco"]), Vector2(148, y + 2), cor)
		if hoje:
			Fonte.desenhar(self, "TODAY", Vector2(206, y + 2), AZUL)
		Fonte.desenhar(self, str(_tarefas_do_dia(d).size()), Vector2(250, y + 2), BRANCO if sel else CINZA)
		y += 10.0
	# detalhe do dia selecionado
	var s := _sol(dia_prev)
	var cor: Color = s["cor"]
	_caixa(Rect2(20, 107, 280, 45), cor)
	Fonte.desenhar(self, "DAY %d: %s" % [dia_prev, s["titulo"]], Vector2(26, 110), AMARELO)
	if _noite(dia_prev):
		_direita("LUNAR NIGHT: NO SOLAR POWER", 296, 110, AZUL)
	else:
		_direita("DAYLIGHT: PANELS +%d POWER" % _geracao_solar(), 296, 110, AMARELO)
	Fonte.desenhar(self, str(s["nota"]), Vector2(26, 119), cor)
	var y2 := 128
	for l in Ciclo.quebrar("TASKS: " + ", ".join(PackedStringArray(_tarefas_do_dia(dia_prev))), 266).slice(0, 3):
		Fonte.desenhar(self, l, Vector2(26, y2), CINZA)
		y2 += 8


# ---------------------------------------------------------------- janela 4: setores da base
func _janela_base() -> void:
	Fonte.desenhar(self, "BASE STATUS // WHAT TONIGHT WILL TAKE", Vector2(22, 38), AZUL)
	var consumo: Dictionary = Recursos.regras["consumo_por_dia"]
	var limite := float(Recursos.regras["limite_baixo"])
	var queda := roundi(float(Recursos.regras["queda_condicao_por_recurso_baixo"]))
	var noite_hoje := _noite(Missao.dia)
	var solar := 0 if noite_hoje else _geracao_solar()
	var baixos := 0
	for nome in ["energia", "oxigenio", "comida"]:
		if Recursos.baixo(nome):
			baixos += 1
	var muda := {
		"energia": solar - roundi(float(consumo["energia"])),
		"oxigenio": -roundi(float(consumo["oxigenio"])),
		"comida": -roundi(float(consumo["comida"])),
		"condicao": -baixos * queda,
	}
	var notas := {
		"energia": "BASE USE -%d, SOLAR PANELS +%d%s" % [roundi(float(consumo["energia"])), solar,
			" (LUNAR NIGHT)" if noite_hoje else ""],
		"oxigenio": "THE CREW BREATHES -%d EVERY NIGHT" % roundi(float(consumo["oxigenio"])),
		"comida": "THE CREW EATS -%d EVERY NIGHT" % roundi(float(consumo["comida"])),
		"condicao": "-%d FOR EACH RESOURCE BELOW %d AT NIGHT" % [queda, roundi(limite)],
	}
	var y := 47.0
	for nome in Recursos.NOMES:
		var v: float = Recursos.valores[nome]
		var cor := VERMELHO if v < limite else (AMARELO if v < 50.0 else VERDE)
		_caixa(Rect2(20, y, 280, 19), cor)
		Fonte.desenhar(self, str(Recursos.ROTULOS[nome]), Vector2(26, y + 3), AMARELO)
		draw_rect(Rect2(66, y + 3, 100, 5), Color("#141d24"))
		draw_rect(Rect2(66, y + 3, roundi(clampf(v, 0.0, 100.0)), 5), cor)
		draw_rect(Rect2(66 + roundi(limite), y + 2, 1, 7), Color(VERMELHO, 0.8))   # marca do "baixo"
		Fonte.desenhar(self, "%d" % roundi(v), Vector2(172, y + 3), BRANCO)
		var dn: int = muda[nome]
		_direita("TONIGHT %+d" % dn if dn != 0 else "TONIGHT 0", 296, y + 3,
			VERMELHO if dn < 0 and v + dn < limite else (VERDE if dn > 0 else BRANCO))
		Fonte.desenhar(self, str(notas[nome]), Vector2(26, y + 11), CINZA)
		y += 21.0
	Fonte.desenhar(self, "SHELTER SHIELDING: %d   ACTIONS LEFT TODAY: %d OF %d" % [Missao.blindagem,
		mapa.ciclo.acoes_restantes(), mapa.ciclo.acoes_por_dia()], Vector2(22, 134), BRANCO)
	Fonte.desenhar(self, "ANY RESOURCE AT 0 ABORTS THE MISSION.", Vector2(22, 143), CINZA)
