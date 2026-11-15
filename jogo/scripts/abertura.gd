
extends Control
## Abertura (briefing) que aparece depois do PLAY: um texto sobe pela tela e vai afinando em direção ao horizonte, sobre o
## céu estrelado. Explica quem é o jogador, quais recursos a base gasta, o que fazer e a primeira decisão (o local de pouso).
## Os números (dias, ações por dia, consumo) vêm de dados/dias.json e dados/recursos.json, então acompanham o balanceamento.
##   - o texto é desenhado com a fonte 3x5 do jogo num SubViewport (LARG_TEXTO px de largura);
##   - um shader em um ColorRect de tela cheia projeta esse texto em perspectiva (nearest, sem suavizar os pixels);
##   - fases: 0 = título, 1 = texto subindo, 2 = escurece e abre a escolha do local de pouso.
## Teclas: E / Enter / clique pulam; segurar baixo acelera; segurar cima deixa mais devagar.
 
const Fonte = preload("res://scripts/fonte.gd")
const CAMINHO_MUSICA := "res://assets/sons/abertura.wav"
const CENA_SEGUINTE := "res://cenas/escolha_pouso.tscn"
const ARQUIVO_DIAS := "res://dados/dias.json"
 
const LARG_TELA := 320.0
const ALT_TELA := 180.0
const LARG_TEXTO := 128            # largura de uma linha de texto em px do jogo (32 letras)
const SUPER := 2                   # o texto é desenhado em dobro de resolução: as letras aguentam melhor o afinamento
const ESCALA := 1.0                # px de tela por px da textura do texto, na base da tela (texto de 256 px de largura)
const HORIZONTE := -140.0          # y (px) do horizonte, acima da tela: quanto mais perto de 0, mais forte a perspectiva
const VELOCIDADE := 12.0           # px da textura por segundo
const DURACAO_TITULO := 4.0
const DURACAO_FADE := 1.2
const ESPERA := 0.4                # o E do PLAY não pode já pular a abertura
 
const PRETO := Color("#090a14")
const AZUL := Color("#73bed3")
const BRANCO := Color("#ebede9")
const METAL := Color("#819796")
 
const SHADER := """
shader_type canvas_item;
uniform sampler2D texto : filter_nearest, repeat_disable;
uniform vec2 tam_texto = vec2(128.0, 300.0);
uniform float rolagem = 0.0;
uniform float horizonte = 26.0;
uniform float escala = 2.0;
uniform vec2 tela = vec2(320.0, 180.0);
uniform vec2 fade = vec2(6.0, 85.0);          // o texto some entre estes dois y da tela
void fragment() {
	vec2 p = UV * tela;
	float base = tela.y - horizonte;          // distância da base da tela até o horizonte
	float d = p.y - horizonte;                // distância deste ponto até o horizonte
	COLOR = vec4(0.0);
	if (d >= 1.0) {
		float s = escala * d / base;          // px de tela por px de texto, na horizontal
		float u = (p.x - tela.x * 0.5) / s + tam_texto.x * 0.5;
		float v = rolagem - (base / escala) * (base / d - 1.0);   // a linha de baixo da tela é a de número `rolagem`
		if (u >= 0.0 && u < tam_texto.x && v >= 0.0 && v < tam_texto.y) {
			vec4 c = texture(texto, vec2(u / tam_texto.x, v / tam_texto.y));
			float f = smoothstep(fade.x, fade.y, p.y);           // some na parte de cima da tela
			COLOR = vec4(c.rgb, c.a * f);
		}
	}
}
"""
 
var t := 0.0
var fase := 0
var t_fade := 0.0
var rolagem := 0.0
var fim_rolagem := 0.0
var alt_texto := 0
var e_liberado := false
var saindo := false
var estrelas: Array = []           # [posição, cor, fase do brilho, velocidade do brilho]
var material_texto: ShaderMaterial
var topo: Control
var player_musica: AudioStreamPlayer

func _configurar_musica() -> void:
	player_musica = AudioStreamPlayer.new()
	var stream = load(CAMINHO_MUSICA)
	if stream:
		player_musica.stream = stream
		add_child(player_musica)
		player_musica.play()
 
func _ready() -> void:
	_criar_teclas()
	_criar_estrelas()
	var linhas := _montar_linhas()
	alt_texto = 8
	for l in linhas:
		alt_texto += int(l["h"])
	# o texto, desenhado com a fonte do jogo, num SubViewport transparente
	var sub := SubViewport.new()
	sub.size = Vector2i(LARG_TEXTO * SUPER, alt_texto * SUPER)
	sub.transparent_bg = true
	sub.disable_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var papel := Control.new()
	papel.size = Vector2(LARG_TEXTO * SUPER, alt_texto * SUPER)
	papel.draw.connect(_desenha_texto.bind(papel, linhas))
	sub.add_child(papel)
	add_child(sub)
	# a projeção em perspectiva
	var sh := Shader.new()
	sh.code = SHADER
	material_texto = ShaderMaterial.new()
	material_texto.shader = sh
	material_texto.set_shader_parameter("texto", sub.get_texture())
	material_texto.set_shader_parameter("tam_texto", Vector2(LARG_TEXTO * SUPER, alt_texto * SUPER))
	material_texto.set_shader_parameter("horizonte", HORIZONTE)
	material_texto.set_shader_parameter("escala", ESCALA)
	var tela := ColorRect.new()
	tela.size = Vector2(LARG_TELA, ALT_TELA)
	tela.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tela.material = material_texto
	add_child(tela)
	# por cima de tudo: faixa com a dica das teclas e o escurecer
	topo = Control.new()
	topo.size = Vector2(LARG_TELA, ALT_TELA)
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topo.draw.connect(_desenha_topo)
	add_child(topo)
	# a última linha do texto sobe até o meio da tela e aí a abertura escurece
	fim_rolagem = alt_texto * SUPER + 0.7 * (ALT_TELA - HORIZONTE) / ESCALA
	_configurar_musica()
 
 
func _process(delta: float) -> void:
	t += delta
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	if saindo:
		return
	match fase:
		0:
			if t >= DURACAO_TITULO:
				fase = 1
		1:
			var v := VELOCIDADE
			if Input.is_action_pressed("baixo"):
				v *= 3.0
			elif Input.is_action_pressed("cima"):
				v *= 0.3
			rolagem += v * delta
			if rolagem >= fim_rolagem:
				fase = 2
		2:
			t_fade += delta
			if t_fade >= DURACAO_FADE:
				_seguir()
	if t > ESPERA and e_liberado and Input.is_action_just_pressed("usar"):
		_seguir()
	_atualizar()
 
 
func _input(ev: InputEvent) -> void:
	if saindo or t < ESPERA:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_seguir()
 
 
func _atualizar() -> void:
	material_texto.set_shader_parameter("rolagem", rolagem)
	queue_redraw()
	topo.queue_redraw()
 
 
func _seguir() -> void:
	if saindo:
		return
	saindo = true
	get_tree().change_scene_to_file(CENA_SEGUINTE)
 
 
# ---------------------------------------------------------------- texto
## Cada linha: {"seg": [{"t": texto, "c": cor, "x": posição}], "centro": bool, "h": altura}. Linha vazia = espaço.
func _linha(txt: String, cor: Color, centro := false) -> Dictionary:
	return {"seg": [{"t": txt, "c": cor, "x": 0}], "centro": centro, "h": 8}
 
 
func _espaco(h: int) -> Dictionary:
	return {"seg": [], "centro": false, "h": h}
 
 
func _titulo(L: Array, txt: String) -> void:
	L.append(_espaco(4))
	L.append(_linha(txt, AZUL, true))
	L.append(_espaco(6))
 
 
func _par(L: Array, txt: String) -> void:
	for l in _quebrar(txt, LARG_TEXTO):
		L.append(_linha(l, BRANCO))
	L.append(_espaco(8))
 
 
## "POWER   -18 EVERY NIGHT": o nome na cor do indicador (a mesma do HUD) e o resto em branco.
func _item(L: Array, nome: String, resto: String) -> void:
	L.append({"seg": [{"t": Recursos.ROTULOS[nome], "c": Recursos.CORES[nome], "x": 0},
		{"t": resto, "c": BRANCO, "x": 36}], "centro": false, "h": 8})
 
 
func _montar_linhas() -> Array:
	var dias: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO_DIAS))
	var regras: Dictionary = Recursos.regras
	var consumo: Dictionary = regras["consumo_por_dia"]
	var L: Array = []
	_titulo(L, "MISSION BRIEFING")
	_par(L, "You are a junior astronaut on your first mission to the Moon.")
	_par(L, "You command a lunar base and must keep the crew alive for %d days." % dias["dias"].size())
	_titulo(L, "THE BASE USES SUPPLIES")
	_item(L, "energia", "-%d EVERY NIGHT" % int(consumo["energia"]))
	_item(L, "oxigenio", "-%d EVERY NIGHT" % int(consumo["oxigenio"]))
	_item(L, "comida", "-%d EVERY NIGHT" % int(consumo["comida"]))
	_item(L, "condicao", "-%d FOR EACH LOW SUPPLY" % int(regras["queda_condicao_por_recurso_baixo"]))
	L.append(_espaco(8))
	_par(L, "A supply below %d is low and hurts the crew. If one reaches zero, the mission is aborted." % int(regras["limite_baixo"]))
	_par(L, "Solar panels give up to +%d power by day and nothing at night." % int(regras["geracao_solar_por_dia"]))
	_titulo(L, "YOUR JOB")
	_par(L, "Walk with WASD or the arrows. Press E to do a task. Tasks bring supplies back.")
	_par(L, "You only have time for %d tasks a day. Pick the most important ones, then sleep in the habitat to end the day." % int(dias["acoes_por_dia"]))
	_titulo(L, "YOUR FIRST DECISION")
	_par(L, "Choose where to land. Each site changes your sunlight, ice and nights, so it changes what you gain or lose every day.")
	_par(L, "Every choice goes into your final report.")
	L.append(_linha("GOOD LUCK, ASTRONAUT!", AZUL, true))
	return L
 
 
func _desenha_texto(papel: Control, linhas: Array) -> void:
	var y := 0
	for l in linhas:
		var segs: Array = l["seg"]
		if not segs.is_empty():
			if l["centro"]:
				var txt := ""
				for sg in segs:
					txt += sg["t"]
				var x := roundf((LARG_TEXTO * SUPER - Fonte.largura(txt, SUPER)) / 2.0)
				Fonte.desenhar(papel, txt, Vector2(x, y * SUPER), segs[0]["c"], SUPER)
			else:
				for sg in segs:
					Fonte.desenhar(papel, sg["t"], Vector2(int(sg["x"]) * SUPER, y * SUPER), sg["c"], SUPER)
		y += int(l["h"])
 
 
## Quebra o texto em linhas que cabem em `largura` px na fonte 3x5.
func _quebrar(texto: String, largura: float) -> Array[String]:
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
 
 
# ---------------------------------------------------------------- desenho
func _criar_estrelas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	for i in 110:
		var cor := [BRANCO, AZUL, METAL, Color("#577277")][rng.randi() % 4] as Color
		estrelas.append([Vector2(rng.randi_range(2, 317), rng.randi_range(2, 177)), cor,
			rng.randf() * TAU, rng.randf_range(0.6, 2.2)])
 
 
func _draw() -> void:
	draw_rect(Rect2(0, 0, LARG_TELA, ALT_TELA), PRETO)
	for e in estrelas:
		var brilho := 0.55 + 0.45 * sin(t * float(e[3]) + float(e[2]))
		var c: Color = e[1]
		draw_rect(Rect2(e[0], Vector2(1, 1)), Color(c, brilho))
	if fase == 0:
		var a := clampf(minf(t, DURACAO_TITULO - t), 0.0, 1.0)
		Fonte.centralizado(self, "ARTEMIS PROGRAM", 160, 74, Color(AZUL, a))
		Fonte.centralizado(self, "MISSION BRIEFING", 160, 88, Color(BRANCO, a), 2)
 
 
func _desenha_topo() -> void:
	Fonte.centralizado(topo, "E: SKIP   HOLD UP OR DOWN: SLOW OR FAST", 160, 5, METAL)
	var veu := 0.0
	if fase == 2:
		veu = clampf(t_fade / DURACAO_FADE, 0.0, 1.0)
	else:
		veu = clampf(1.0 - t / 0.6, 0.0, 1.0)      # entra do preto
	if veu > 0.0:
		topo.draw_rect(Rect2(0, 0, LARG_TELA, ALT_TELA), Color(0, 0, 0, veu))
 
 
## Se a cena for aberta direto pelo editor (F6), as teclas ainda não existem (o jogo normal cria na tela inicial).
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
 
