extends Control
## Tela inicial do jogo: PLAY, SETTINGS e EXIT sobre o fundo animado (estrelas piscando e brilho no título).
## Arte em res://assets/inicio/ (tirada da animação aprovada, 320x180 a 10 quadros por segundo):
##   - fundo_anim.png: 32 quadros de 320x180 numa folha de 8 colunas x 4 linhas (sem os botões);
##   - botoes.png: cada botão com 96x24; coluna 0 = normal, coluna 1 = selecionado; linhas = PLAY, SETTINGS, EXIT e
##     vazio (o vazio serve para os botões da tela de configurações, que escrevem o texto com a fonte do jogo).
## Teclas: cima/baixo (W/S ou setas) escolhem, E (ou Enter, X, J) confirma, Esc volta das configurações.
## Mouse: passar por cima seleciona e clicar confirma.
 
const Fonte = preload("res://scripts/fonte.gd")
const FUNDO := preload("res://assets/inicio/fundo_anim.png")
const BOTOES := preload("res://assets/inicio/botoes.png")
 
const CENA_ABERTURA := "res://cenas/abertura.tscn"      # PLAY: abertura (briefing) e depois a escolha do local de pouso
const QUADROS := 32
const COLUNAS := 8
const TEMPO_QUADRO := 0.1
const BOTAO := Vector2(96, 24)
const POS_MENU := [Vector2(112, 72), Vector2(112, 107), Vector2(112, 142)]    # PLAY, SETTINGS, EXIT
const POS_OPCOES := [Vector2(112, 80), Vector2(112, 115)]                     # FULLSCREEN, BACK
const LINHA_VAZIO := 3
 
const AMARELO := Color("#e8c170")
const BRANCO := Color("#ebede9")
const METAL := Color("#819796")
 
var t := 0.0
var selecionado := 0
var em_opcoes := false
var e_liberado := false              # só aceita o E depois que ele for solto uma vez (veio de outra tela)
var saindo := false
 
 
func _ready() -> void:
	_criar_teclas()
 
 
func _process(delta: float) -> void:
	t += delta
	queue_redraw()
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	if saindo:
		return
	var n := POS_OPCOES.size() if em_opcoes else POS_MENU.size()
	if Input.is_action_just_pressed("baixo"):
		selecionado = (selecionado + 1) % n
	elif Input.is_action_just_pressed("cima"):
		selecionado = (selecionado + n - 1) % n
	elif e_liberado and Input.is_action_just_pressed("usar"):
		_confirmar()
	elif em_opcoes and Input.is_action_just_pressed("ui_cancel"):
		_abrir_opcoes(false)
 
 
func _input(ev: InputEvent) -> void:
	if saindo or not ev is InputEventMouse:
		return
	var p: Vector2 = (make_input_local(ev) as InputEventMouse).position
	var lista: Array = POS_OPCOES if em_opcoes else POS_MENU
	for i in lista.size():
		if Rect2(lista[i], BOTAO).has_point(p):
			if ev is InputEventMouseMotion:
				selecionado = i
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				selecionado = i
				_confirmar()
			return
 
 
func _confirmar() -> void:
	if em_opcoes:
		if selecionado == 0:
			Opcoes.definir_tela_cheia(not Opcoes.tela_cheia)
		else:
			_abrir_opcoes(false)
		return
	match selecionado:
		0:
			saindo = true
			get_tree().change_scene_to_file(CENA_ABERTURA)
		1:
			_abrir_opcoes(true)
		2:
			saindo = true
			get_tree().quit()
 
 
func _abrir_opcoes(abrir: bool) -> void:
	em_opcoes = abrir
	selecionado = 0 if abrir else 1       # ao voltar, o cursor fica em SETTINGS
 
 
# ---------------------------------------------------------------- desenho
func _draw() -> void:
	var q := int(t / TEMPO_QUADRO) % QUADROS
	draw_texture_rect_region(FUNDO, Rect2(0, 0, 320, 180),
		Rect2((q % COLUNAS) * 320, (q / COLUNAS) * 180, 320, 180))
	if em_opcoes:
		_desenha_opcoes()
		return
	for i in POS_MENU.size():
		_botao(i, POS_MENU[i], i == selecionado)
 
 
func _botao(linha: int, pos: Vector2, sel: bool) -> void:
	draw_texture_rect_region(BOTOES, Rect2(pos, BOTAO), Rect2(Vector2(BOTAO.x if sel else 0.0, BOTAO.y * linha), BOTAO))
 
 
func _desenha_opcoes() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0.035, 0.039, 0.078, 0.95))
	Fonte.centralizado(self, "SETTINGS", 160, 40, AMARELO, 3)
	var textos := ["FULLSCREEN: " + ("ON" if Opcoes.tela_cheia else "OFF"), "BACK"]
	if not Opcoes.pode_tela_cheia():
		textos[0] = "FULLSCREEN: N/A"
	for i in POS_OPCOES.size():
		_botao(LINHA_VAZIO, POS_OPCOES[i], i == selecionado)
		Fonte.centralizado(self, textos[i], POS_OPCOES[i].x + BOTAO.x / 2.0, POS_OPCOES[i].y + 10,
			BRANCO if i == selecionado else AMARELO)
	Fonte.centralizado(self, "F11 ALSO TURNS FULLSCREEN ON AND OFF", 160, 160, METAL)
 
 
## Esta é a primeira cena do jogo, então as teclas ainda não existem (no resto do jogo, quem cria é o mapa).
func _criar_teclas() -> void:
	var teclas := {"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT], "cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN], "andar": [KEY_SHIFT], "usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]}
	for acao in teclas:
		if InputMap.has_action(acao):
			continue
		InputMap.add_action(acao)
		for k in teclas[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(acao, ev)
 
