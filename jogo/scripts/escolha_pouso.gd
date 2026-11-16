extends Control
## Tela de escolha do local de pouso: 3 cartões lado a lado.
## Esquerda / direita (ou o mouse em cima) escolhem; E (ou clique) confirma. Depois guarda a escolha na Missao e
## abre a base. Os textos e números de cada local ficam em res://dados/locais_pouso.json.
## Arte (paleta Apollo) em res://assets/pouso/: a Lua vista da órbita no fundo, a vista de cada local na faixa do
## topo do cartão (local_<id>.png, 96x24, com 1 px da cor do local embaixo) e os ícones do Sol e do gelo nos medidores.

const Fonte = preload("res://scripts/fonte.gd")
const BRANCO := Color("#ebede9")
const CINZA := Color("#819796")
const AMARELO := Color("#e8c170")
const VERDE := Color("#a8ca58")
const VERMELHO := Color("#cf573c")
const AZUL := Color("#73bed3")
const APAGADO := Color("#394a50")
const ICONE_SOL := preload("res://assets/pouso/icone_sol.png")     # 7x7
const ICONE_GELO := preload("res://assets/pouso/icone_gelo.png")   # 7x7
const ALTURA_VISTA := 23                 # a vista cobre a faixa menos a última linha, que fica com a cor do local

const ARQUIVO := "res://dados/locais_pouso.json"
const BASE := "res://cenas/mapa.tscn"
const LETRAS_POR_LINHA := 22             # cabe no cartão: (96 - 8) / 4 px por letra
const ESPERA_POUSO := 1.0                # tempo mostrando "LANDING: ..." antes de abrir a base
const INTERVALO_DEMO := 0.7              # no demo, tempo entre um movimento e outro

var demo := false                        # true: a tela escolhe sozinha (modo demo do jogo)
var locais: Array = []
var selecionado := 1                     # começa no cartão do meio
var e_liberado := false                  # só aceita o E depois que ele for solto uma vez
var confirmado := false
var t_demo := 0.0
var passos_demo := 0

@onready var textos: Control = $Textos
@onready var moldura: ColorRect = $Moldura
@onready var cartoes := [$Cartao1, $Cartao2, $Cartao3]


func _ready() -> void:
	_criar_teclas()
	demo = "--demo" in OS.get_cmdline_user_args()
	locais = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	for i in cartoes.size():
		var faixa: ColorRect = cartoes[i].get_node("Faixa")
		faixa.color = Color(locais[i]["cor"])
		var vista := TextureRect.new()       # a vista do local por cima da faixa (o cartão apagado apaga ela junto)
		vista.name = "Vista"
		vista.texture = load("res://assets/pouso/local_%s.png" % locais[i]["id"])
		vista.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # sem isso o tamanho mínimo é o da textura (24)
		vista.size = Vector2(faixa.size.x, ALTURA_VISTA)
		vista.stretch_mode = TextureRect.STRETCH_KEEP
		vista.clip_contents = true
		vista.mouse_filter = Control.MOUSE_FILTER_IGNORE
		faixa.add_child(vista)
	textos.draw.connect(_desenhar_textos)
	_atualizar_visual()


func _input(ev: InputEvent) -> void:
	# mouse: passar por cima seleciona o cartão, clicar confirma
	if confirmado or demo or not ev is InputEventMouse:
		return
	var i := _cartao_no_mouse((make_input_local(ev) as InputEventMouse).position)
	if i < 0:
		return
	selecionado = i
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_confirmar()
	_atualizar_visual()


func _process(delta: float) -> void:
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	if confirmado:
		return
	if demo:
		_jogar_sozinho(delta)
	else:
		if Input.is_action_just_pressed("esquerda"):
			selecionado = maxi(0, selecionado - 1)
		if Input.is_action_just_pressed("direita"):
			selecionado = mini(locais.size() - 1, selecionado + 1)
		if e_liberado and Input.is_action_just_pressed("usar"):
			_confirmar()
	_atualizar_visual()


## m: posição do mouse já na tela de 320x180 (vem do próprio evento, não do cursor do sistema)
func _cartao_no_mouse(m: Vector2) -> int:
	for i in cartoes.size():
		if Rect2(cartoes[i].position, cartoes[i].size).has_point(m):
			return i
	return -1


func _jogar_sozinho(delta: float) -> void:
	# no demo, passa pelos 3 cartões, volta para o do meio e confirma
	t_demo += delta
	if t_demo < INTERVALO_DEMO:
		return
	t_demo = 0.0
	passos_demo += 1
	if passos_demo <= 3:
		selecionado = passos_demo - 1
	elif passos_demo == 4:
		selecionado = 1
	else:
		_confirmar()


func _confirmar() -> void:
	confirmado = true
	_atualizar_visual()
	var id: String = locais[selecionado]["id"]
	Missao.escolher_local(id)
	await get_tree().create_timer(ESPERA_POUSO).timeout
	get_tree().change_scene_to_file(BASE)


func _atualizar_visual() -> void:
	moldura.position.x = cartoes[selecionado].position.x - 2
	for i in cartoes.size():
		cartoes[i].modulate = Color.WHITE if i == selecionado else Color(1, 1, 1, 0.55)
	textos.queue_redraw()


func _desenhar_textos() -> void:
	Fonte.centralizado(textos, "CHOOSE THE LANDING SITE", 160, 6, AMARELO)
	for i in locais.size():
		_desenhar_cartao(locais[i], cartoes[i].position, i == selecionado)
	if confirmado:
		Fonte.centralizado(textos, "LANDING: " + str(locais[selecionado]["titulo"]), 160, 162, VERDE)
	else:
		Fonte.centralizado_com_teclas(textos, "[A/D] OR MOUSE   [E] OR CLICK: LAND", 160, 162, BRANCO, Color("#cf573c"))


func _desenhar_cartao(local: Dictionary, pos: Vector2, ativo: bool) -> void:
	var x := pos.x + 4
	var y := pos.y + 30                      # logo abaixo da faixa colorida
	var cor_texto := BRANCO if ativo else CINZA
	Fonte.desenhar(textos, local["titulo"], Vector2(x, y), AMARELO if ativo else CINZA)
	y += 11
	Fonte.desenhar(textos, "+ ADVANTAGE", Vector2(x, y), VERDE)
	y += 8
	for linha in _quebrar(local["vantagem"]):
		Fonte.desenhar(textos, linha, Vector2(x, y), cor_texto)
		y += 7
	y += 4
	Fonte.desenhar(textos, "! RISK", Vector2(x, y), VERMELHO)
	y += 8
	for linha in _quebrar(local["risco"]):
		Fonte.desenhar(textos, linha, Vector2(x, y), cor_texto)
		y += 7
	# medidores de 1 a 3 quadradinhos, iguais em todos os cartões, para comparar de olho
	_medidor("SUN", int(local["sol"]), Vector2(x, pos.y + 120), AMARELO)
	_medidor("ICE", int(local["gelo"]), Vector2(x + 44, pos.y + 120), AZUL)


func _medidor(nome: String, nivel: int, pos: Vector2, cor: Color) -> void:
	textos.draw_texture(ICONE_SOL if nome == "SUN" else ICONE_GELO, pos + Vector2(0, -1))
	Fonte.desenhar(textos, nome, pos + Vector2(9, 0), BRANCO)
	for i in 3:
		textos.draw_rect(Rect2(pos.x + 25 + i * 5, pos.y, 4, 5), cor if i < nivel else APAGADO)


func _quebrar(texto: String) -> Array:
	# quebra o texto em linhas de até LETRAS_POR_LINHA letras, sem cortar palavras
	var linhas := []
	var linha := ""
	for palavra in texto.split(" "):
		var tentativa: String = palavra if linha == "" else linha + " " + palavra
		if tentativa.length() > LETRAS_POR_LINHA and linha != "":
			linhas.append(linha)
			linha = palavra
		else:
			linha = tentativa
	if linha != "":
		linhas.append(linha)
	return linhas


func _criar_teclas() -> void:
	# esta é a primeira cena do jogo, então as teclas ainda não existem (no resto do jogo, quem cria é o mapa)
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
