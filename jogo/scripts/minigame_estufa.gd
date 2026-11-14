extends Control
## Minigame da estufa (WATER THE PLANTS): 3 vasos de alface sob a luz de cultivo.
## Segurar o clique num vaso (ou escolher com esquerda/direita e segurar E) faz a umidade subir; com ela na faixa
## verde e a rega solta, a alface cresce até ficar pronta. Água demais encharca (o vaso escorre e é preciso esperar);
## sem água a umidade cai sozinha e a planta murcha. Os 3 vasos prontos concluem a tarefa.
## Arte do PixelAi (paleta Apollo) em res://assets/minigames/regar/; moldura, medidores e texto desenhados aqui.
## Contrato com o mapa: sinal `terminou` (concluiu), sinal `cancelou` (fechou no X ou Esc) e a variável `demo`.

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const TEX_CANTEIRO := preload("res://assets/minigames/regar/canteiro.png")
const TEX_ALFACE := preload("res://assets/minigames/regar/alface.png")   # 8 estágios + 2 de balanço, 31x29
const TEX_MURCHA := preload("res://assets/minigames/regar/alface_murcha.png")

const PRETO := Color("#090a14")
const NOITE := Color("#10141f")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const VERDE_ESC := Color("#25562e")
const VERDE := Color("#468232")
const VERDE_LIMA := Color("#a8ca58")
const AGUA := Color("#4f8fba")
const AGUA_CLARA := Color("#73bed3")
const AGUA_BRILHO := Color("#a4dddb")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                 # canto do canteiro (192x121) na tela
const BOTAO_X := Rect2(245, 17, 8, 8)
const VASOS := [46, 96, 146]                    # centro de cada vaso, no canteiro
const BICOS := [49, 95, 143]                    # gotejador de cada vaso
const MEDIDORES := [66, 115, 165]
const Y_BICO := 49
const Y_TERRA := 91
const Y_MED := 54
const ALT_MED := 38
const QUADRO := Vector2(31, 29)

const FAIXA := Vector2(0.55, 0.78)              # umidade certa
const ENCHE := 0.42                             # por segundo, regando
const SECA := 0.035                             # por segundo, evaporando sob o LED
const ESCORRE := 0.3                            # por segundo, encharcado
const SECO := 0.2                               # abaixo disso a planta murcha
const ESPERA_FAIXA := 0.6                       # tempo na faixa, sem regar, para começar a crescer
const PASSO_CRESCER := 0.22                     # tempo de cada estágio ao crescer

var demo := false
var vasos := []
var sel := 0
var regando := -1
var e_liberado := false                         # o E que abriu o minigame ainda pode estar apertado
var t := 0.0
var t_fim := -1.0
var aviso := ""
var cor_aviso := BRANCO
var t_aviso := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	for v in [[0.32, 3], [0.18, 2], [0.06, 2]]:
		vasos.append({"nivel": v[0], "estagio": v[1], "pronto": false, "crescendo": false, "t_faixa": 0.0,
			"t_cresce": 0.0, "pulo": 0.0, "encharcado": false})


func _input(ev: InputEvent) -> void:
	if t_fim >= 0.0 or demo:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if BOTAO_X.grow(1).has_point(get_local_mouse_position()):
			cancelou.emit()
	elif ev.is_action_pressed("ui_cancel"):
		cancelou.emit()


func _process(delta: float) -> void:
	t += delta
	t_aviso = maxf(0.0, t_aviso - delta)
	if t_fim >= 0.0:
		t_fim -= delta
		_animar(delta)
		queue_redraw()
		if t_fim < 0.0:
			set_process(false)
			terminou.emit()
		return
	regando = _quem_rega()
	for i in vasos.size():
		_atualizar(i, delta)
	_animar(delta)
	if vasos.all(func(v): return v["pronto"]):
		t_fim = 1.6
		_avisar("PLANTS WATERED!", VERDE_LIMA, 2.0)
	queue_redraw()


func _quem_rega() -> int:
	if demo:  # como um jogador: rega o vaso até o meio da faixa, solta e espera crescer; depois o próximo
		for i in vasos.size():
			var v: Dictionary = vasos[i]
			if not v["pronto"] and not v["crescendo"]:
				sel = i
				if v["nivel"] >= 0.68:
					v["demo_solto"] = true
				elif v["nivel"] < FAIXA.x:
					v["demo_solto"] = false
				return -1 if v.get("demo_solto", false) or v["encharcado"] else i
		return -1
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	if Input.is_action_just_pressed("esquerda"):
		sel = (sel + vasos.size() - 1) % vasos.size()
	if Input.is_action_just_pressed("direita"):
		sel = (sel + 1) % vasos.size()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var m := get_local_mouse_position()
		for i in vasos.size():
			if _area_vaso(i).has_point(m):
				sel = i
				return i
	if e_liberado and Input.is_action_pressed("usar"):
		return sel
	return -1


func _area_vaso(i: int) -> Rect2:
	return Rect2(JANELA + Vector2(VASOS[i] - 22, 52), Vector2(44, 69))


func _atualizar(i: int, delta: float) -> void:
	var v: Dictionary = vasos[i]
	if v["pronto"] or v["crescendo"]:
		return
	if v["encharcado"]:
		v["nivel"] -= ESCORRE * delta
		if v["nivel"] < 0.8:
			v["encharcado"] = false
	elif i == regando:
		v["nivel"] += ENCHE * delta
		if v["nivel"] >= 0.97:
			v["encharcado"] = true
			_avisar("TOO MUCH WATER! WAIT FOR IT TO DRAIN", VERMELHO_CLARO, 1.8)
	else:
		v["nivel"] -= SECA * delta
	v["nivel"] = clampf(v["nivel"], 0.0, 1.0)
	var na_faixa: bool = v["nivel"] >= FAIXA.x and v["nivel"] <= FAIXA.y
	if na_faixa and i != regando and not v["encharcado"]:
		v["t_faixa"] += delta
		if v["t_faixa"] >= ESPERA_FAIXA:
			v["crescendo"] = true
	else:
		v["t_faixa"] = 0.0


func _animar(delta: float) -> void:
	for v in vasos:
		v["pulo"] = maxf(0.0, v["pulo"] - delta)
		if not v["crescendo"]:
			continue
		v["t_cresce"] += delta
		if v["t_cresce"] >= PASSO_CRESCER:
			v["t_cresce"] = 0.0
			v["estagio"] += 1
			v["pulo"] = 0.07
			if v["estagio"] >= 7:
				v["estagio"] = 7
				v["crescendo"] = false
				v["pronto"] = true


func _avisar(txt: String, cor: Color, dur: float) -> void:
	aviso = txt
	cor_aviso = cor
	t_aviso = dur


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	var feitos := vasos.filter(func(v): return v["pronto"]).size()
	Fonte.centralizado(self, "WATER THE PLANTS", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "%d/3" % feitos, PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow(0).grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, Vector2(194, 123)), PRETO)
	draw_texture(TEX_CANTEIRO, JANELA)
	for i in vasos.size():
		_vaso(i)
	var y_txt := JANELA.y + 126
	if t_aviso > 0.0:
		Fonte.centralizado(self, aviso, 160, y_txt, cor_aviso)
	else:
		Fonte.centralizado(self, "HOLD A POT TO WATER, RELEASE IN THE GREEN ZONE", 160, y_txt, BRANCO_SUJO)


func _moldura() -> void:
	var p := PAINEL
	draw_rect(p, PRETO)
	draw_rect(p.grow(-1), CINZA)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(p.size.x - 2, 1)), METAL_CLARO)
	draw_rect(Rect2(p.position + Vector2(1, 1), Vector2(1, p.size.y - 2)), METAL)
	draw_rect(Rect2(p.position + Vector2(2, p.size.y - 2), Vector2(p.size.x - 3, 1)), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(p.size.x - 2, 2), Vector2(1, p.size.y - 3)), CINZA_ESC)
	for c in [Vector2(3, 3), Vector2(p.size.x - 6, 3), Vector2(3, p.size.y - 6), Vector2(p.size.x - 6, p.size.y - 6)]:
		draw_rect(Rect2(p.position + c, Vector2(3, 3)), METAL)
		draw_rect(Rect2(p.position + c + Vector2.ONE, Vector2.ONE), CINZA_ESC)
	draw_rect(Rect2(p.position + Vector2(8, 3), Vector2(p.size.x - 16, 10)), FUNDO)


func _vaso(i: int) -> void:
	var v: Dictionary = vasos[i]
	var cx: float = JANELA.x + VASOS[i]
	var terra: float = JANELA.y + Y_TERRA
	# planta
	if not v["pronto"] and not v["crescendo"] and v["nivel"] < SECO:
		draw_texture(TEX_MURCHA, Vector2(cx - TEX_MURCHA.get_width() / 2, terra - TEX_MURCHA.get_height() + 1))
	else:
		var q: int = v["estagio"]
		if v["pronto"]:
			q = [8, 7, 9, 7][int(t / 0.3) % 4]          # balanço da planta pronta
		var alto := QUADRO.y + (1.0 if v["pulo"] > 0.0 else 0.0)
		draw_texture_rect_region(TEX_ALFACE, Rect2(cx - 15, terra - alto + 1, QUADRO.x, alto),
			Rect2(Vector2(q * QUADRO.x, 0), QUADRO))
	# água encharcada em cima da terra
	if v["encharcado"]:
		draw_rect(Rect2(cx - 14, terra - 1, 28, 2), AGUA)
		draw_rect(Rect2(cx - 10, terra - 1, 6, 1), AGUA_BRILHO)
	# gotas caindo do gotejador
	if i == regando:
		var bx: float = JANELA.x + BICOS[i]
		var queda: float = Y_TERRA - Y_BICO - 4
		for k in 3:
			var gy: float = JANELA.y + Y_BICO + 2 + fmod(t * 60.0 + k * 13.0, queda)
			draw_rect(Rect2(bx, gy, 1, 2), AGUA_CLARA)
			draw_rect(Rect2(bx, gy - 1, 1, 1), AGUA_BRILHO)
	_medidor(i)
	# vaso escolhido pelo teclado
	if not demo and not v["pronto"] and i == sel:
		var y := JANELA.y + 122
		for k in 3:
			draw_rect(Rect2(cx - k, y + k, 1 + 2 * k, 1), AMARELO)


func _medidor(i: int) -> void:
	var v: Dictionary = vasos[i]
	var x: float = JANELA.x + MEDIDORES[i]
	var topo: float = JANELA.y + Y_MED
	draw_rect(Rect2(x - 1, topo - 1, 8, ALT_MED + 2), PRETO)
	draw_rect(Rect2(x, topo, 6, ALT_MED), NOITE)
	var f0 := topo + ALT_MED - roundf(ALT_MED * FAIXA.y)
	var f1 := topo + ALT_MED - roundf(ALT_MED * FAIXA.x)
	draw_rect(Rect2(x, f0, 6, f1 - f0), VERDE_ESC)
	var marca := VERDE_LIMA if v["pronto"] else VERDE
	for mx in [x - 2, x + 7]:
		draw_rect(Rect2(mx, f0, 1, 1), marca)
		draw_rect(Rect2(mx, f1 - 1, 1, 1), marca)
	var h := roundf(ALT_MED * float(v["nivel"]))
	if h > 0:
		draw_rect(Rect2(x + 1, topo + ALT_MED - h, 4, h), AGUA)
		draw_rect(Rect2(x + 1, topo + ALT_MED - h, 4, 1), AGUA_BRILHO)
		if h > 1:
			draw_rect(Rect2(x + 1, topo + ALT_MED - h + 1, 1, h - 1), AGUA_CLARA)
	if v["pronto"]:
		for pt in [Vector2(1, -5), Vector2(2, -4), Vector2(3, -5), Vector2(4, -6), Vector2(5, -7)]:
			draw_rect(Rect2(Vector2(x, topo) + pt, Vector2.ONE), VERDE_LIMA)
	elif (v["encharcado"] or v["nivel"] < SECO) and int(t * 4.0) % 2 == 0:
		draw_rect(Rect2(x + 2, topo - 8, 2, 4), VERMELHO_CLARO)
		draw_rect(Rect2(x + 2, topo - 3, 2, 1), VERMELHO_CLARO)


func _criar_teclas() -> void:
	# para a cena rodar sozinha com F6: no jogo, quem cria as teclas é o mapa
	var m := {"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER], "esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT]}
	for acao in m:
		if InputMap.has_action(acao):
			continue
		InputMap.add_action(acao)
		for k in m[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(acao, ev)
