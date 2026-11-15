extends Control
## Minigame "trocar o filtro de CO2" (SWAP THE CO2 FILTER), nos tanques do Suporte à Vida. 4 passos em ordem:
## destravar (E 6 vezes), puxar o filtro velho (segurar baixo), encaixar o novo (segurar cima) e travar (E).
## O filtro é um cartucho cilíndrico: o novo é branco, o velho está gasto.
## Soltar antes do tempo só zera o passo de segurar (sem erro). Tecla errada mostra WRONG KEY sem perder o progresso
## e é erro: taxa_erro diminui o que a tarefa rende e MAX_ERROS erros perdem a tarefa (sinal falhou).
## Arte (paleta Apollo) em res://assets/minigames/co2/; moldura, LED, barra e texto desenhados aqui.
## Contrato com o mapa: sinais `terminou` (concluiu), `falhou` (errou demais) e `cancelou` (X ou Esc), taxa_erro()
## e a variável `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const TEX_MODULO := preload("res://assets/minigames/co2/modulo.png")             # 192x121
const TEX_FILTRO_VELHO := preload("res://assets/minigames/co2/filtro_velho.png")
const TEX_FILTRO_NOVO := preload("res://assets/minigames/co2/filtro_novo.png")
const TEX_TRAVA := preload("res://assets/minigames/co2/trava.png")
const TEX_TRAVA_VERDE := preload("res://assets/minigames/co2/trava_verde.png")

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
const VERDE_LIMA := Color("#a8ca58")
const VERDE_CLARO := Color("#d0da91")
const VINHO := Color("#752438")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")

const PAINEL := Rect2(56, 9, 208, 162)
const JANELA := Vector2(64, 25)                  # canto do módulo (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 13, 8, 8)
const BARRA := Rect2(80, 159, 160, 3)
const CX_ENCAIXE := 96                           # centro do encaixe, no módulo
const Y_FILTRO := 12                             # topo do filtro encaixado
const Y_TRAVA := 22                              # trava fechada, cruzando a tampa de cima do cilindro
const Y_TRAVA_ABERTA := 3                        # trava recolhida em cima da moldura
const LED := Vector2(130, 20)                    # luz de estado ao lado do encaixe
const DESCIDA := 111.0                           # o filtro sai inteiro pela borda de baixo da janela

# cada passo: o que mostrar, qual tecla, se é "apertar" (conta apertos) ou "segurar" (conta segundos) e quanto precisa
const PASSOS := [
	{"texto": "UNLOCK THE FILTER: PRESS E 6 TIMES", "tecla": "usar", "tipo": "apertar", "quanto": 6.0},
	{"texto": "PULL OUT THE OLD FILTER: HOLD DOWN", "tecla": "baixo", "tipo": "segurar", "quanto": 1.0},
	{"texto": "SLIDE IN THE NEW FILTER: HOLD UP", "tecla": "cima", "tipo": "segurar", "quanto": 1.0},
	{"texto": "LOCK THE FILTER: PRESS E", "tecla": "usar", "tipo": "apertar", "quanto": 1.0},
]
const TECLAS := ["usar", "esquerda", "direita", "cima", "baixo"]
const INTERVALO_DEMO := 0.2                      # no demo, tempo entre um aperto e outro
const VEL_TRAVA := 120.0                         # px/s da trava ao recolher e ao voltar
const TEMPO_FIM := 1.3
const MAX_ERROS := 4                             # com tantos erros a tarefa é perdida (era 6: tolerante demais)

var demo := false                                # o jogo coloca true no modo demo: o minigame se resolve sozinho
var passo := 0                                   # passo atual: 0 a 3 (4 = acabou)
var progresso := 0.0                             # apertos feitos ou segundos segurando, no passo atual
var t := 0.0
var t_aviso := 0.0                               # tempo restante do aviso WRONG KEY
var t_demo := 0.0
var t_tremor := 0.0                              # a trava treme um instante a cada aperto
var e_liberado := false                          # só aceita o E depois que o jogador soltar o aperto que abriu
var t_fim := -1.0
var trava_y := float(Y_TRAVA)                    # posição desenhada da trava (anda até o alvo)
var acertos := 0                                 # apertos certos e passos de segurar completos
var erros := 0                                   # teclas erradas e soltar antes da hora
var perdeu := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()


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
	t_tremor = maxf(0.0, t_tremor - delta)
	trava_y = move_toward(trava_y, _alvo_trava(), VEL_TRAVA * delta)
	if t_fim >= 0.0:
		t_fim -= delta
		queue_redraw()
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
		return
	if not Input.is_action_pressed("usar"):
		e_liberado = true
	var p: Dictionary = PASSOS[passo]
	if demo:
		_jogar_sozinho(p, delta)
	elif p["tipo"] == "apertar":
		_passo_apertar(p)
	else:
		_passo_segurar(p, delta)
	if progresso >= p["quanto"]:
		_proximo_passo()
	queue_redraw()


func _passo_apertar(p: Dictionary) -> void:
	if _apertou(p["tecla"]):
		progresso += 1.0
		acertos += 1
		t_tremor = 0.08
	elif _apertou_outra(p["tecla"]):
		_errar()


func _passo_segurar(p: Dictionary, delta: float) -> void:
	if Input.is_action_pressed(p["tecla"]):
		progresso += delta
	else:
		progresso = 0.0                          # soltou antes do tempo: só volta a zero (tocar em vez de segurar
		                                         # é engano de novato; com MAX_ERROS 4 perderia a tarefa à toa)
	if _apertou_outra(p["tecla"]):
		_errar()


func _errar() -> void:
	t_aviso = 0.8
	erros += 1
	if erros >= MAX_ERROS:
		perdeu = true
		t_fim = TEMPO_FIM


## Fração dos lances que foram erros.
func taxa_erro() -> float:
	return erros / maxf(1.0, float(erros + acertos))


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso, fechar é de graça.
func comecou() -> bool:
	return erros > 0 or acertos > 0 or passo > 0 or progresso > 0.0


func _apertou(tecla: String) -> bool:
	if tecla == "usar" and not e_liberado:
		return false
	return Input.is_action_just_pressed(tecla)


func _apertou_outra(tecla: String) -> bool:
	for k in TECLAS:
		if k != tecla and _apertou(k):
			return true
	return false


func _jogar_sozinho(p: Dictionary, delta: float) -> void:
	# no demo, mexe no progresso direto, num ritmo que dá para ver; espera a trava chegar antes de cada passo
	if absf(trava_y - _alvo_trava()) > 0.5:
		return
	if p["tipo"] == "segurar":
		progresso += delta
		return
	t_demo += delta
	if t_demo >= INTERVALO_DEMO:
		t_demo = 0.0
		progresso += 1.0
		t_tremor = 0.08


func _proximo_passo() -> void:
	if PASSOS[passo]["tipo"] == "segurar":
		acertos += 1
	passo += 1
	progresso = 0.0
	t_demo = 0.0
	if passo >= PASSOS.size():
		t_fim = TEMPO_FIM


## Onde a trava deve estar: sobe 1 px por aperto ao destravar, fica em cima enquanto troca e volta ao travar.
func _alvo_trava() -> float:
	if passo == 0:
		return Y_TRAVA - progresso
	if passo >= PASSOS.size():
		return Y_TRAVA
	return Y_TRAVA_ABERTA


func _fracao() -> float:
	if passo >= PASSOS.size():
		return 1.0
	return clampf(progresso / PASSOS[passo]["quanto"], 0.0, 1.0)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	Fonte.centralizado(self, "SWAP THE CO2 FILTER", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
		AMARELO)
	Fonte.desenhar(self, "%d/4" % mini(passo + 1, 4), PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	draw_texture(TEX_MODULO, JANELA)
	_filtros()
	var tremor := 1.0 if t_tremor > 0.0 else 0.0
	var tex_trava: Texture2D = TEX_TRAVA_VERDE if passo >= PASSOS.size() else TEX_TRAVA
	var x_trava := CX_ENCAIXE - floori(tex_trava.get_width() / 2.0)
	draw_texture(tex_trava, JANELA + Vector2(x_trava + tremor, round(trava_y)))
	_led()
	var y_txt := JANELA.y + TAM_JANELA.y + 4
	if perdeu:
		Fonte.centralizado(self, "TOO MANY ERRORS - TASK FAILED", 160, y_txt, VERMELHO_CLARO)
	elif passo >= PASSOS.size():
		Fonte.centralizado(self, "FILTER SWAPPED - AIRFLOW RESTORED", 160, y_txt, VERDE_LIMA)
	elif t_aviso > 0.0:
		Fonte.centralizado(self, "WRONG KEY (%d/%d)" % [erros, MAX_ERROS], 160, y_txt, VERMELHO_CLARO)
	else:
		Fonte.centralizado(self, PASSOS[passo]["texto"], 160, y_txt, BRANCO_SUJO)
	_barra()


## Filtro velho descendo (passo 1) ou o novo subindo (passo 2), cortados na borda de baixo da janela.
func _filtros() -> void:
	var r := _fracao()
	if passo <= 1:
		var y := roundf(DESCIDA * r * r) if passo == 1 else 0.0
		_textura_cortada(TEX_FILTRO_VELHO, Y_FILTRO + y)
	else:
		var y := roundf(DESCIDA * (1.0 - r) * (1.0 - r)) if passo == 2 else 0.0
		_textura_cortada(TEX_FILTRO_NOVO, Y_FILTRO + y)


func _textura_cortada(tex: Texture2D, y: float) -> void:
	var alto := minf(tex.get_height(), TAM_JANELA.y - y)
	if alto <= 0.0:
		return
	var x := CX_ENCAIXE - floori(tex.get_width() / 2.0)
	draw_texture_rect_region(tex, Rect2(JANELA + Vector2(x, y), Vector2(tex.get_width(), alto)),
		Rect2(0, 0, tex.get_width(), alto))


## LED do módulo: vermelho piscando com o filtro velho, laranja durante a troca, verde no fim.
func _led() -> void:
	var pos := JANELA + LED
	var cor := LARANJA
	if passo == 0:
		cor = VERMELHO_CLARO if fmod(t, 0.5) < 0.25 else VINHO
	elif passo >= PASSOS.size():
		cor = VERDE_LIMA
	draw_rect(Rect2(pos, Vector2(3, 3)), cor)
	if cor != VINHO:
		draw_rect(Rect2(pos, Vector2.ONE), BRANCO)


func _barra() -> void:
	draw_rect(BARRA.grow(1), PRETO)
	draw_rect(BARRA, FUNDO)
	var cheio := roundf(BARRA.size.x * _fracao())
	if cheio > 0:
		draw_rect(Rect2(BARRA.position, Vector2(cheio, BARRA.size.y)), VERDE_LIMA)
		draw_rect(Rect2(BARRA.position, Vector2(cheio, 1)), VERDE_CLARO)


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
