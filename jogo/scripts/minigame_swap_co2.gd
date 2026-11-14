extends Control
## Minigame "trocar o filtro de CO2": 4 passos em ordem (destravar, puxar o velho, encaixar o novo, travar).

signal terminou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const CINZA := Color("#577277")

# cada passo: o que mostrar, qual tecla, se é "apertar" (conta apertos) ou "segurar" (conta segundos) e quanto precisa
const PASSOS := [
	{"texto": "DESTRAVE O FILTRO", "dica": "APERTE E 6 VEZES", "tecla": "usar", "tipo": "apertar", "quanto": 6.0},
	{"texto": "PUXE O FILTRO VELHO", "dica": "SEGURE BAIXO", "tecla": "baixo", "tipo": "segurar", "quanto": 1.0},
	{"texto": "ENCAIXE O FILTRO NOVO", "dica": "SEGURE CIMA", "tecla": "cima", "tipo": "segurar", "quanto": 1.0},
	{"texto": "TRAVE O FILTRO", "dica": "APERTE E", "tecla": "usar", "tipo": "apertar", "quanto": 1.0},
]
const TECLAS := ["usar", "esquerda", "direita", "cima", "baixo"]
const DESCIDA := 20.0                    # quantos pixels o filtro anda ao sair ou entrar
const LARGURA_PROGRESSO := 160.0
const INTERVALO_DEMO := 0.2              # no demo, tempo entre um aperto e outro

var demo := false                        # o jogo coloca true no modo demo: o minigame se resolve sozinho
var passo := 0                           # passo atual: 0 a 3
var progresso := 0.0                     # apertos feitos ou segundos segurando, no passo atual
var t_aviso := 0.0                       # tempo restante do aviso "TECLA ERRADA"
var t_demo := 0.0
var e_liberado := false                  # só aceita o E depois que o jogador soltar o aperto que abriu o minigame
var acabou := false
var t_acabou := 0.0

@onready var textos: Control = $Textos
@onready var trava: ColorRect = $Trava
@onready var filtro_velho: ColorRect = $FiltroVelho
@onready var filtro_novo: ColorRect = $FiltroNovo
@onready var barra_progresso: ColorRect = $Progresso
@onready var y_encaixado: float = filtro_velho.position.y


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	filtro_velho.visible = true
	filtro_novo.visible = false
	trava.visible = true
	trava.color = AMARELO
	barra_progresso.size.x = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancelou.emit()
			set_process(false)


func _process(delta: float) -> void:
	t_aviso = maxf(0.0, t_aviso - delta)

	if acabou:
		t_acabou -= delta
		if t_acabou <= 0.0:
			terminou.emit()
			set_process(false)
		textos.queue_redraw()
		return

	# Só libera ação do E depois que o jogador soltar o botão de interação do mapa
	if not e_liberado:
		if not Input.is_action_pressed("usar"):
			e_liberado = true

	if demo:
		_processar_demo(delta)
	else:
		_processar_jogador(delta)

	textos.queue_redraw()


func _processar_jogador(delta: float) -> void:
	var p: Dictionary = PASSOS[passo]
	var tecla: String = p["tecla"]
	var tipo: String = p["tipo"]
	var quanto: float = p["quanto"]

	_checar_tecla_errada(tecla)

	if tipo == "apertar":
		if Input.is_action_just_pressed(tecla):
			if tecla == "usar" and not e_liberado:
				return
			progresso += 1.0
			barra_progresso.size.x = (progresso / quanto) * LARGURA_PROGRESSO

			if passo == 0:
				trava.position.y = 50.0 - (progresso / quanto) * 4.0
			elif passo == 3:
				trava.position.y = 50.0

			if progresso >= quanto:
				_avancar_passo()

	elif tipo == "segurar":
		if Input.is_action_pressed(tecla):
			progresso += delta
			var r: float = clampf(progresso / quanto, 0.0, 1.0)
			barra_progresso.size.x = r * LARGURA_PROGRESSO

			if passo == 1:
				filtro_velho.position.y = y_encaixado + r * DESCIDA
			elif passo == 2:
				filtro_novo.position.y = y_encaixado + DESCIDA - r * DESCIDA

			if progresso >= quanto:
				_avancar_passo()
		else:
			if progresso > 0.0:
				progresso = 0.0
				barra_progresso.size.x = 0.0
				if passo == 1:
					filtro_velho.position.y = y_encaixado
				elif passo == 2:
					filtro_novo.position.y = y_encaixado + DESCIDA


func _processar_demo(delta: float) -> void:
	var p: Dictionary = PASSOS[passo]
	var tipo: String = p["tipo"]
	var quanto: float = p["quanto"]

	if tipo == "apertar":
		t_demo += delta
		if t_demo >= INTERVALO_DEMO:
			t_demo = 0.0
			progresso += 1.0
			barra_progresso.size.x = (progresso / quanto) * LARGURA_PROGRESSO
			if passo == 0:
				trava.position.y = 50.0 - (progresso / quanto) * 4.0
			elif passo == 3:
				trava.position.y = 50.0
			if progresso >= quanto:
				_avancar_passo()

	elif tipo == "segurar":
		progresso += delta
		var r: float = clampf(progresso / quanto, 0.0, 1.0)
		barra_progresso.size.x = r * LARGURA_PROGRESSO
		if passo == 1:
			filtro_velho.position.y = y_encaixado + r * DESCIDA
		elif passo == 2:
			filtro_novo.position.y = y_encaixado + DESCIDA - r * DESCIDA
		if progresso >= quanto:
			_avancar_passo()


func _checar_tecla_errada(tecla_certa: String) -> void:
	for k in TECLAS:
		if k != tecla_certa and Input.is_action_just_pressed(k):
			t_aviso = 0.8
			break


func _avancar_passo() -> void:
	progresso = 0.0
	barra_progresso.size.x = 0.0
	t_demo = 0.0

	if passo == 0:
		trava.visible = false
		passo = 1

	elif passo == 1:
		filtro_velho.visible = false
		filtro_novo.visible = true
		filtro_novo.position.y = y_encaixado + DESCIDA
		passo = 2

	elif passo == 2:
		filtro_novo.position.y = y_encaixado
		e_liberado = false
		passo = 3

	elif passo == 3:
		trava.visible = true
		trava.color = VERDE
		trava.position.y = 50.0
		barra_progresso.size.x = LARGURA_PROGRESSO
		acabou = true
		t_acabou = 1.3


func _desenhar_textos() -> void:
	textos.draw_rect(Rect2(79, 127, LARGURA_PROGRESSO + 2, 6), Color(0.1, 0.13, 0.18, 0.9))

	if acabou:
		Fonte.centralizado(textos, "FILTRO TROCADO", 160, 36, VERDE, 2)
		Fonte.centralizado(textos, "FLUXO DE AR RESTAURADO", 160, 138, BRANCO)
		return

	var p: Dictionary = PASSOS[passo]
	Fonte.centralizado(textos, "TROCAR O FILTRO DE CO2", 160, 34, AMARELO)
	Fonte.centralizado(textos, "PASSO %d/4" % (passo + 1), 160, 42, CINZA)

	Fonte.centralizado(textos, str(p["texto"]), 160, 108, BRANCO)
	Fonte.centralizado(textos, str(p["dica"]), 160, 116, AMARELO)

	if t_aviso > 0.0:
		Fonte.centralizado(textos, "TECLA ERRADA", 160, 138, VERMELHO)


func _criar_teclas() -> void:
	var m := {
		"esquerda": [KEY_A, KEY_LEFT],
		"direita": [KEY_D, KEY_RIGHT],
		"cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN],
		"usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]
	}
	for acao in m:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
			for k in m[acao]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(acao, ev)
