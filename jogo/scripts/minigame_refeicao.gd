extends Control
## Minigame "preparar refeição" (PREPARE A MEAL), na bancada da cozinha do Habitat: o astronauta põe um pacote de
## comida espacial no reidratador e aquecedor (como o food warmer da ISS). Segurar E esquenta e soltar esfria; a
## comida só cozinha enquanto o termômetro fica na faixa ideal, e a barra de preparo enche até a refeição ficar
## pronta. Não tem falha (cozinhar sempre termina), mas esquentar demais queima: cada vez que o termômetro passa
## da marca vermelha (QUEIMA) conta um erro e o preparo perde um pouco; taxa_erro diminui o que a tarefa rende.
## A ideia e a mecânica (modular o aquecedor com E para manter a temperatura na faixa) vieram do PR #13
## (IltonBJSilva).
## Arte (paleta Apollo, PixelAi) em res://assets/minigames/refeicao/: fundo.png (192x121), comida_crua.png e
## comida_pronta.png (mesmo tamanho e alinhamento) e termometro.png. Se um arquivo faltar, o minigame desenha uma
## versão provisória no lugar dele. O líquido do termômetro, a faixa ideal, o vapor e os textos são desenhados aqui.
## Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e `demo`.

signal terminou
signal cancelou
signal falhou                                    # nunca emitido aqui: com ele e comecou(), o mapa trata fechar
                                                 # depois de começar como desistência (gasta a ação, não rende)

const Fonte = preload("res://scripts/fonte.gd")
const DIR_ARTE := "res://assets/minigames/refeicao/"

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const CINZA_ESC := Color("#394a50")
const CINZA := Color("#577277")
const METAL := Color("#819796")
const METAL_CLARO := Color("#a8b5b2")
const BRANCO := Color("#ebede9")
const BRANCO_SUJO := Color("#c7cfcc")
const AMARELO := Color("#e8c170")
const LARANJA := Color("#de9e41")
const MARROM := Color("#a8662e")
const VERDE := Color("#75a743")
const VERDE_LIMA := Color("#a8ca58")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const AZUL := Color("#4f8fba")
const CIANO := Color("#73bed3")

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                   # canto do fundo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
# dentro do fundo: o centro do pacote de comida e o miolo do tubo do termômetro (x, topo, base)
const COMIDA := Vector2(90, 65)                   # dentro do forno, apoiada no fundo do compartimento (base em y 84)
const TAM_COMIDA_PROVISORIA := Vector2(56, 40)
const TERMOMETRO := Vector2(134, 23)              # canto do termometro.png (16x60), na fenda do painel do forno
const TUBO_X := TERMOMETRO.x + 6.0                 # miolo do tubo no termometro.png: x 6..11, de y 5 a 47
const TUBO_LARG := 6.0
const TUBO_TOPO := TERMOMETRO.y + 5.0
const TUBO_BASE := TERMOMETRO.y + 47.0
const BULBO := TERMOMETRO + Vector2(8.5, 52.5)     # centro do bulbo (raio 4.6): sempre cheio de líquido

const FAIXA_MIN := 0.40                            # faixa ideal (fração do tubo)
const FAIXA_MAX := 0.75
const AQUECE := 0.65                               # por segundo segurando E
const ESFRIA := 0.35                               # por segundo solto
const TEMPO_NECESSARIO := 2.5                      # segundos na faixa ideal
const QUEIMA := 0.85                               # acima disto a comida queima: um erro por vez que passar
const PERDA_QUEIMA := 0.5                          # segundos de preparo perdidos a cada queima
const TEMPO_FIM := 1.2

var demo := false
var temp := 0.15                                   # 0 (frio) a 1 (muito quente)
var tempo_cozinhando := 0.0
var queimas := 0                                   # quantas vezes passou da marca vermelha
var queimando := false                             # está acima da marca (só conta de novo depois de esfriar)
var t_queima := 0.0                                # aviso BURNED! na tela
var e_liberado := false                            # o E que abriu o minigame não pode já esquentar
var aquecendo := false
var mexeu := false                                 # já esquentou alguma vez (comecou)
var acabou := false
var t := 0.0
var t_fim := -1.0
var vapor: Array = []                              # [pos, vel, vida]

var tex_fundo: Texture2D
var tex_crua: Texture2D
var tex_pronta: Texture2D
var tex_termometro: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	tex_fundo = _textura("fundo")
	tex_crua = _textura("comida_crua")
	tex_pronta = _textura("comida_pronta")
	tex_termometro = _textura("termometro")


func _textura(nome: String) -> Texture2D:
	var c := DIR_ARTE + nome + ".png"
	return load(c) if ResourceLoader.exists(c) else null


func _input(ev: InputEvent) -> void:
	if acabou or demo:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if BOTAO_X.grow(1).has_point(get_local_mouse_position()):
			cancelou.emit()
	elif ev.is_action_pressed("ui_cancel"):
		cancelou.emit()


func _process(delta: float) -> void:
	t += delta
	t_queima = maxf(0.0, t_queima - delta)
	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true
	if not acabou:
		aquecendo = temp < 0.58 if demo else (e_liberado and Input.is_action_pressed("usar"))
		mexeu = mexeu or aquecendo
		temp = clampf(temp + (AQUECE if aquecendo else -ESFRIA) * delta, 0.0, 1.0)
		if na_faixa():
			tempo_cozinhando += delta
		if temp > QUEIMA and not queimando:
			queimando = true
			queimas += 1
			t_queima = 1.0
			tempo_cozinhando = maxf(0.0, tempo_cozinhando - PERDA_QUEIMA)
		elif temp <= FAIXA_MAX:
			queimando = false
		if tempo_cozinhando >= TEMPO_NECESSARIO:
			acabou = true
			t_fim = TEMPO_FIM
	_animar(delta)
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			terminou.emit()
	queue_redraw()


## Fração das tentativas que queimaram: 1 queima ~ 84% do ganho, 2 ~ 62%, 3 ~ 50%.
func taxa_erro() -> float:
	return queimas / (queimas + 2.0)


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça. Sem isso, dava para fechar um preparo ruim e
## jogar de novo até sair perfeito, e a perda de ganho por erro não valia nada.
func comecou() -> bool:
	return mexeu


func na_faixa() -> bool:
	return temp >= FAIXA_MIN and temp <= FAIXA_MAX


func progresso() -> float:
	return clampf(tempo_cozinhando / TEMPO_NECESSARIO, 0.0, 1.0)


## Vapor saindo da comida: mais forte quanto mais quente e mais pronta.
func _animar(delta: float) -> void:
	var forca := temp * (0.3 + progresso())
	if randf() < 22.0 * forca * delta:
		var x := COMIDA.x + randf_range(-18, 18)
		vapor.append([Vector2(x, COMIDA.y - 12), Vector2(randf_range(-4, 4), randf_range(-16, -10)),
			randf_range(0.8, 1.4)])
	for v in vapor:
		v[0] += v[1] * delta
		v[2] -= delta
	vapor = vapor.filter(func(v): return v[2] > 0.0)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "PREPARE A MEAL", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "%d%%" % roundi(progresso() * 100.0), PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	if tex_fundo:
		draw_texture(tex_fundo, JANELA)
	else:
		_fundo_provisorio()
	if aquecendo and not acabou:                   # a grade do aquecedor brilha enquanto esquenta
		draw_rect(Rect2(JANELA + COMIDA + Vector2(-30, 20), Vector2(60, 2)),
			Color(LARANJA, 0.5 + 0.3 * sin(t * 20.0)))
	_comida()
	for v in vapor:
		var a: float = clampf(v[2], 0.0, 1.0) * 0.8
		_px(v[0], Color(BRANCO_SUJO, a))
		_px(v[0] + Vector2(1, 0), Color(BRANCO_SUJO, a * 0.5))
	_termometro()
	_barra_preparo()
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if acabou:
		Fonte.centralizado(self, "MEAL READY!", 160, y_txt, VERDE_LIMA)
	elif t_queima > 0.0 or temp > QUEIMA:
		Fonte.centralizado(self, "BURNED! (%d) RELEASE E TO COOL" % queimas, 160, y_txt,
			VERMELHO_CLARO if fmod(t, 0.3) < 0.18 else LARANJA)
	elif na_faixa():
		Fonte.centralizado(self, "PERFECT TEMPERATURE - KEEP IT THERE", 160, y_txt, VERDE_LIMA)
	elif temp > FAIXA_MAX:
		Fonte.centralizado_com_teclas(self, "TOO HOT! RELEASE [E] TO COOL", 160, y_txt, VERMELHO_CLARO if fmod(t, 0.4) < 0.25 else LARANJA, AMARELO)
	else:
		Fonte.centralizado_com_teclas(self, "TOO COLD - HOLD [E] TO HEAT", 160, y_txt, CIANO, VERMELHO)


func _px(p: Vector2, cor: Color) -> void:
	if Rect2(Vector2.ZERO, TAM_JANELA).has_point(p):
		draw_rect(Rect2(JANELA + p.floor(), Vector2.ONE), cor)


## O pacote: o cru por baixo e o pronto por cima, aparecendo conforme cozinha.
func _comida() -> void:
	var p := progresso()
	if tex_crua and tex_pronta:
		var canto := JANELA + COMIDA - (tex_crua.get_size() / 2.0).floor()
		draw_texture(tex_crua, canto)
		draw_texture(tex_pronta, canto, Color(1, 1, 1, p))
	else:
		var r := Rect2(JANELA + COMIDA - TAM_COMIDA_PROVISORIA / 2.0, TAM_COMIDA_PROVISORIA)
		draw_rect(r, PRETO)
		draw_rect(r.grow(-1), METAL.lerp(LARANJA, p))
		draw_rect(Rect2(r.position + Vector2(6, 8), Vector2(r.size.x - 12, 10)), METAL_CLARO.lerp(MARROM, p))
		draw_rect(Rect2(r.position + Vector2(10, 24), Vector2(14, 8)), CINZA.lerp(VERDE, p))
		draw_rect(Rect2(r.position + Vector2(30, 24), Vector2(16, 8)), METAL_CLARO.lerp(AMARELO, p))


## Termômetro: o tubo (arte ou provisório), a faixa ideal em verde e o líquido subindo.
func _termometro() -> void:
	var altura := TUBO_BASE - TUBO_TOPO
	if tex_termometro:
		draw_texture(tex_termometro, JANELA + TERMOMETRO)
	else:
		draw_rect(Rect2(JANELA + Vector2(TUBO_X - 3, TUBO_TOPO - 3), Vector2(TUBO_LARG + 6, altura + 6)), PRETO)
		draw_rect(Rect2(JANELA + Vector2(TUBO_X - 2, TUBO_TOPO - 2), Vector2(TUBO_LARG + 4, altura + 4)), METAL)
		draw_rect(Rect2(JANELA + Vector2(TUBO_X, TUBO_TOPO), Vector2(TUBO_LARG, altura)), FUNDO)
		draw_rect(Rect2(JANELA + Vector2(TUBO_X - 3, TUBO_BASE + 1), Vector2(TUBO_LARG + 6, 8)), PRETO)
	var y_max := TUBO_BASE - FAIXA_MAX * altura
	var y_min := TUBO_BASE - FAIXA_MIN * altura
	# faixa ideal: marcas verdes dos dois lados do tubo
	var cor_faixa := Color(VERDE_LIMA, 0.9 if na_faixa() else 0.5)
	draw_rect(Rect2(JANELA + Vector2(TUBO_X - 4, y_max), Vector2(2, y_min - y_max)), cor_faixa)
	draw_rect(Rect2(JANELA + Vector2(TUBO_X + TUBO_LARG + 2, y_max), Vector2(2, y_min - y_max)), cor_faixa)
	draw_rect(Rect2(JANELA + Vector2(TUBO_X, y_max), Vector2(TUBO_LARG, y_min - y_max)), Color(VERDE, 0.25))
	# marca vermelha da queima: acima dela a comida queima
	var y_queima := TUBO_BASE - QUEIMA * altura
	var cor_queima := VERMELHO_CLARO if temp > QUEIMA and fmod(t, 0.3) < 0.18 else VERMELHO
	draw_rect(Rect2(JANELA + Vector2(TUBO_X - 4, TUBO_TOPO), Vector2(2, y_queima - TUBO_TOPO)), cor_queima)
	draw_rect(Rect2(JANELA + Vector2(TUBO_X + TUBO_LARG + 2, TUBO_TOPO), Vector2(2, y_queima - TUBO_TOPO)), cor_queima)
	var h := roundf(temp * altura)
	var cor := VERMELHO_CLARO if temp > FAIXA_MAX else (AMARELO if na_faixa() else CIANO)
	draw_circle(JANELA + BULBO, 3.6, cor)                                          # bulbo e o pescoço até o tubo
	draw_rect(Rect2(JANELA + Vector2(TUBO_X + 1, TUBO_BASE), Vector2(TUBO_LARG - 2, BULBO.y - TUBO_BASE)), cor)
	draw_rect(Rect2(JANELA + Vector2(TUBO_X + 1, TUBO_BASE - h), Vector2(TUBO_LARG - 2, h)), cor)
	draw_rect(Rect2(JANELA + Vector2(TUBO_X + 1, TUBO_BASE - h), Vector2(TUBO_LARG - 2, 1)), BRANCO)


## Barra de preparo na base do fundo.
func _barra_preparo() -> void:
	var r := Rect2(JANELA + Vector2(8, TAM_JANELA.y - 7), Vector2(TAM_JANELA.x - 16, 4))
	draw_rect(r.grow(1), PRETO)
	draw_rect(r, CINZA_ESC)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * progresso()), r.size.y)), VERDE_LIMA)


func _fundo_provisorio() -> void:
	draw_rect(Rect2(JANELA, TAM_JANELA), CINZA)
	draw_rect(Rect2(JANELA + Vector2(20, 22), Vector2(110, 74)), CINZA_ESC)          # compartimento
	draw_rect(Rect2(JANELA + Vector2(24, 26), Vector2(102, 66)), FUNDO)
	for x in range(28, 124, 6):                                                    # grade do aquecedor
		draw_rect(Rect2(JANELA + Vector2(x, 86), Vector2(3, 2)), CINZA_ESC)
	draw_rect(Rect2(JANELA + Vector2(20, 22), Vector2(110, 1)), METAL_CLARO)
	for i in 3:                                                                    # botões
		draw_rect(Rect2(JANELA + Vector2(136, 30 + i * 12), Vector2(6, 6)), [VERDE, AMARELO, VERMELHO][i])


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


func _criar_teclas() -> void:
	# para a cena rodar sozinha com F6: no jogo, quem cria as teclas é o mapa
	var teclas := {"esquerda": [KEY_A, KEY_LEFT], "direita": [KEY_D, KEY_RIGHT], "cima": [KEY_W, KEY_UP],
		"baixo": [KEY_S, KEY_DOWN], "usar": [KEY_E, KEY_X, KEY_J, KEY_ENTER]}
	for acao in teclas:
		if InputMap.has_action(acao):
			continue
		InputMap.add_action(acao)
		for k in teclas[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(acao, ev)
