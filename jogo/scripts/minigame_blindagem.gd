extends Control
## Minigame "reforçar a blindagem" (REINFORCE THE SHIELDING), no Abrigo: a parede interna tem 3 pontos fracos por
## onde a radiação de uma erupção solar passaria. O jogador arrasta uma placa de blindagem pesada (W A S D; ela
## desliza com inércia), alinha a placa exatamente sobre a brecha destacada e aperta E para parafusar. São 3 placas.
## Apertar E desalinhado ou demorar demais numa placa conta um erro (taxa_erro diminui o que a tarefa rende);
## MAX_ERROS erros perdem a tarefa (sinal falhou). Cada blindagem feita conta um reforço (Missao.blindagem), que
## diminui o dano da erupção para quem não chegar ao Abrigo a tempo.
## A ideia e a mecânica (mover 3 placas até os pontos vulneráveis e fixar com E) vieram do PR #11 (IltonBJSilva).
## Arte (paleta Apollo, PixelAi; gerada por arte/minijogo_blindagem.py) em res://assets/minigames/blindagem/:
## parede.png (192x121), brecha.png e brecha_b.png (brilho piscando), placa.png e placa_fixa.png (todas TAM x TAM). Se um arquivo faltar, o minigame desenha uma
## versão provisória no lugar dele. Radiação vazando, parafusos, moldura e textos são animados aqui.
## Contrato com o mapa: sinais `terminou`, `falhou` e `cancelou` (X ou Esc), taxa_erro(), comecou() e `demo`.

signal terminou
signal falhou
signal cancelou

const Fonte = preload("res://scripts/fonte.gd")
const DIR_ARTE := "res://assets/minigames/blindagem/"

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
const VERDE := Color("#75a743")
const VERMELHO := Color("#a53030")
const VERMELHO_CLARO := Color("#cf573c")
const RADIACAO := Color("#d0da91")                # brilho da radiação vazando (amarelo-esverdeado)

const PAINEL := Rect2(56, 13, 208, 154)
const JANELA := Vector2(64, 29)                   # canto da parede (192x121) na tela
const TAM_JANELA := Vector2(192, 121)
const BOTAO_X := Rect2(245, 17, 8, 8)
const TAM := 24                                   # brecha e placa (quadradas)
# as brechas caem dentro dos painéis da parede.png (vãos em x 47, 71, 96, 120, 145 e y 33, 58, 83): canto de cada
# coluna e das 3 fileiras de cima; o código sorteia 3, longe umas das outras e do ponto de partida
const COLUNAS := [23, 47, 71, 96, 120, 145]
const LINHAS := [8, 34, 58]
const PARTIDA := Vector2(84, 86)                  # onde cada placa nova aparece (fileira de baixo, no meio)
const LIMITE := Rect2(22, 6, 124, 80)             # até onde o canto da placa pode ir (dentro da moldura da parede)

const PLACAS := 3
const VEL_MAX := 70.0
const ACELERACAO := 150.0
const FREIO := 110.0                              # a placa é pesada: solta a tecla e ela ainda desliza
const ENCAIXE := 3.0                              # distância máxima (px) entre a placa e a brecha para parafusar
const TEMPO_PLACA := 10.0                         # segundos por placa antes de contar erro por demora
const TEMPO_FIM := 1.2
const MAX_ERROS := 3

var demo := false
var brechas: Array[Vector2] = []                  # canto de cada brecha, na ordem em que devem ser tapadas
var placa := 0                                    # quantas placas já foram parafusadas
var pos := PARTIDA                                # canto da placa solta
var vel := Vector2.ZERO
var erros := 0
var perdeu := false
var acabou := false
var e_liberado := false                           # o E que abriu o minigame não pode parafusar
var mexeu := false
var t := 0.0
var t_placa := TEMPO_PLACA
var t_erro := 0.0
var t_fim := -1.0
var t_parafuso := 0.0                             # animação dos parafusos da última placa fixada
var mensagem := ""
var cor_mensagem := AMARELO
var vazando: Array = []                           # [pos, vel, vida] partículas de radiação saindo das brechas abertas

var tex_parede: Texture2D
var tex_brecha: Texture2D
var tex_brecha_b: Texture2D
var tex_placa: Texture2D
var tex_placa_fixa: Texture2D

var modo_emergencia: String = ""
var tempo_restante_emergencia: float = 0.0

var player_audio: AudioStreamPlayer = null
var som_parafuso: AudioStreamWAV = null
var som_erro: AudioStreamWAV = null
var som_sucesso: AudioStreamWAV = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_teclas()
	_criar_audio()
	tex_parede = _textura("parede")
	tex_brecha = _textura("brecha")
	tex_brecha_b = _textura("brecha_b")
	tex_placa = _textura("placa")
	tex_placa_fixa = _textura("placa_fixa")
	_sortear_brechas()


func _criar_audio() -> void:
	player_audio = AudioStreamPlayer.new()
	player_audio.volume_db = -3.0
	add_child(player_audio)
	som_parafuso = _sintetizar_som_parafuso()
	som_erro = _sintetizar_som_erro()
	som_sucesso = _sintetizar_som_sucesso()


func _tocar_som(s: AudioStreamWAV) -> void:
	if player_audio != null and s != null:
		player_audio.stream = s
		player_audio.play()


func _textura(nome: String) -> Texture2D:
	var c := DIR_ARTE + nome + ".png"
	return load(c) if ResourceLoader.exists(c) else null


## 3 vagas sorteadas, a pelo menos 34 px umas das outras e longe do ponto de partida (para nenhuma vir de graça).
func _sortear_brechas() -> void:
	var vagas: Array = []
	for y in LINHAS:
		for x in COLUNAS:
			vagas.append(Vector2(x, y))
	vagas.shuffle()
	for v in vagas:
		if brechas.size() >= PLACAS:
			break
		var longe: bool = (v as Vector2).distance_to(PARTIDA) >= 30.0
		for b in brechas:
			longe = longe and (v as Vector2).distance_to(b) >= 34.0
		if longe:
			brechas.append(v)


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
	t_erro = maxf(0.0, t_erro - delta)
	t_parafuso = maxf(0.0, t_parafuso - delta)
	if modo_emergencia != "" and tempo_restante_emergencia > 0.0:
		tempo_restante_emergencia = maxf(0.0, tempo_restante_emergencia - delta)
	if not e_liberado and not Input.is_action_pressed("usar"):
		e_liberado = true
	if not acabou:
		if demo:
			_jogar_sozinho(delta)
		else:
			_controles(delta)
		t_placa -= delta
		if not acabou and t_placa <= 0.0:
			_errar("TOO SLOW")
	_animar(delta)
	if acabou:
		t_fim -= delta
		if t_fim < 0.0:
			set_process(false)
			if perdeu:
				falhou.emit()
			else:
				terminou.emit()
	queue_redraw()


func _controles(delta: float) -> void:
	var dir := Input.get_vector("esquerda", "direita", "cima", "baixo")
	if dir != Vector2.ZERO:
		vel = vel.move_toward(dir * VEL_MAX, ACELERACAO * delta)
	else:
		vel = vel.move_toward(Vector2.ZERO, FREIO * delta)
	_mover(delta)
	if e_liberado and Input.is_action_just_pressed("usar"):
		if alinhada():
			_parafusar()
		else:
			_errar("MISALIGNED")


## Demo: leva a placa direto até a brecha e parafusa.
func _jogar_sozinho(delta: float) -> void:
	pos = pos.move_toward(brechas[placa], 60.0 * delta)
	if pos.distance_to(brechas[placa]) < 0.5:
		_parafusar()


func _mover(delta: float) -> void:
	pos += vel * delta
	var p := pos.clamp(LIMITE.position, LIMITE.end)
	if p.x != pos.x:
		vel.x = 0.0                               # bateu na borda da parede: para naquele eixo
	if p.y != pos.y:
		vel.y = 0.0
	pos = p
	if vel != Vector2.ZERO:
		mexeu = true


func alinhada() -> bool:
	return placa < brechas.size() and pos.distance_to(brechas[placa]) <= ENCAIXE


func _parafusar() -> void:
	placa += 1
	t_parafuso = 0.5
	vel = Vector2.ZERO
	t_placa = TEMPO_PLACA
	_tocar_som(som_parafuso)
	if placa >= PLACAS:
		acabou = true
		t_fim = TEMPO_FIM
		_avisar("SHELTER SHIELDED!", VERDE_LIMA)
		_tocar_som(som_sucesso)
	else:
		pos = PARTIDA
		mensagem = ""


func _errar(txt: String) -> void:
	erros += 1
	t_erro = 0.4
	t_placa = TEMPO_PLACA
	_tocar_som(som_erro)
	if erros >= MAX_ERROS:
		perdeu = true
		acabou = true
		t_fim = TEMPO_FIM + 0.6
		_avisar("TOO MANY ERRORS - TASK FAILED", VERMELHO_CLARO)
	else:
		_avisar("%s (%d/%d)" % [txt, erros, MAX_ERROS], VERMELHO_CLARO)


func _avisar(txt: String, cor: Color) -> void:
	mensagem = txt
	cor_mensagem = cor


## Fração dos lances errados (E desalinhado ou demora) entre todos os lances (erros + placas fixadas).
func taxa_erro() -> float:
	return erros / maxf(1.0, float(erros + placa))


## O jogador já começou a jogar: a partir daqui, fechar no X ou no Esc conta como desistir (o mapa trata como
## falha, depois de confirmar). Antes disso (nem mexeu a placa), fechar é de graça.
func comecou() -> bool:
	return mexeu or erros > 0 or placa > 0


func _animar(delta: float) -> void:
	for i in range(placa, brechas.size()):          # radiação saindo das brechas ainda abertas
		if randf() < (14.0 if i == placa else 5.0) * delta:
			var c := brechas[i] + Vector2(TAM, TAM) / 2.0
			var ang := randf() * TAU
			vazando.append([c + Vector2(cos(ang), sin(ang)) * 4.0, Vector2(cos(ang), sin(ang)) * randf_range(8, 18),
				randf_range(0.6, 1.2)])
	for v in vazando:
		v[0] += v[1] * delta
		v[2] -= delta
	vazando = vazando.filter(func(v): return v[2] > 0.0)


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(PRETO, 0.68))
	_moldura()
	if modo_emergencia != "":
		var pisca_hdr := fmod(t, 0.3) < 0.15
		var txt_hdr := "[!] EMERGENCY HULL BREACH // %dS" % int(ceilf(tempo_restante_emergencia))
		Fonte.centralizado(self, txt_hdr, PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
			VERMELHO_CLARO if pisca_hdr else AMARELO)
	else:
		Fonte.centralizado(self, "REINFORCE THE SHIELDING", PAINEL.position.x + PAINEL.size.x / 2.0, PAINEL.position.y + 5,
			AMARELO)
	Fonte.desenhar(self, "%d/%d" % [placa, PLACAS], PAINEL.position + Vector2(12, 5), VERDE_LIMA)
	draw_rect(BOTAO_X.grow(1), PRETO)
	draw_rect(BOTAO_X.grow_individual(-1, -1, -1, -1), VERMELHO)
	for k in 4:
		draw_rect(Rect2(BOTAO_X.position + Vector2(2 + k, 2 + k), Vector2.ONE), BRANCO)
		draw_rect(Rect2(BOTAO_X.position + Vector2(5 - k, 2 + k), Vector2.ONE), BRANCO)
	draw_rect(Rect2(JANELA - Vector2.ONE, TAM_JANELA + Vector2(2, 2)), PRETO)
	if tex_parede:
		draw_texture(tex_parede, JANELA)
	else:
		_parede_provisoria()
	for i in brechas.size():
		if i < placa:
			_placa_fixa(brechas[i], i == placa - 1)
		else:
			_brecha(brechas[i], i == placa)
	for v in vazando:
		_px(v[0], Color(RADIACAO, clampf(v[2], 0.0, 1.0)))
	if not acabou or perdeu:
		_placa_solta()
	if not acabou:
		_barra_tempo()
	if t_erro > 0.0:
		draw_rect(Rect2(JANELA, TAM_JANELA), Color(VERMELHO_CLARO, 0.25 * t_erro / 0.4))
	var y_txt := JANELA.y + TAM_JANELA.y + 5
	if mensagem != "":
		Fonte.centralizado(self, mensagem, 160, y_txt, cor_mensagem)
	elif alinhada():
		Fonte.centralizado(self, "ALIGNED! PRESS E TO BOLT IT", 160, y_txt, VERDE_LIMA)
	else:
		Fonte.centralizado(self, "SLIDE THE PLATE (W A S D) OVER THE LEAK", 160, y_txt, BRANCO_SUJO)


func _px(p: Vector2, cor: Color) -> void:
	if Rect2(Vector2.ZERO, TAM_JANELA).has_point(p):
		draw_rect(Rect2(JANELA + p.floor(), Vector2.ONE), cor)


## Brecha aberta; a da vez pisca e ganha um contorno amarelo (como no PR #11).
func _brecha(c: Vector2, da_vez: bool) -> void:
	var r := Rect2(JANELA + c, Vector2(TAM, TAM))
	var forte := da_vez and fmod(t, 0.5) < 0.25
	if tex_brecha:
		draw_texture(tex_brecha_b if (forte and tex_brecha_b) else tex_brecha, r.position)
	else:
		draw_rect(r, PRETO)
		draw_rect(r.grow(-3), Color(RADIACAO, 0.55 if forte else 0.3))
		draw_rect(r.grow(-7), RADIACAO if forte else Color(RADIACAO, 0.6))
		for k in 5:                                 # rachadura
			draw_rect(Rect2(r.position + Vector2(3 + k * 4, 4 + (k % 2) * 3), Vector2(2, 1)), CINZA_ESC)
	if da_vez:
		var cor := VERDE_LIMA if alinhada() else (AMARELO if fmod(t, 0.6) < 0.4 else LARANJA)
		draw_rect(r.grow(2), cor, false, 1.0)


func _placa_fixa(c: Vector2, recente: bool) -> void:
	var o := JANELA + c
	if tex_placa_fixa:
		draw_texture(tex_placa_fixa, o)
	else:
		_placa_provisoria(o)
		draw_rect(Rect2(o + Vector2(TAM / 2.0 - 1, TAM / 2.0 - 1), Vector2(2, 2)), VERDE)
	# parafusos entrando um por um na placa recém-fixada (some depois de 0,5 s)
	if recente and t_parafuso > 0.0:
		var cantos := [Vector2(2, 2), Vector2(TAM - 4, 2), Vector2(2, TAM - 4), Vector2(TAM - 4, TAM - 4)]
		var n := clampi(int((0.5 - t_parafuso) / 0.1) + 1, 0, 4)
		for k in n:
			draw_rect(Rect2(o + cantos[k] - Vector2.ONE, Vector2(4, 4)), Color(BRANCO, t_parafuso * 2.0))
	elif not tex_placa_fixa:
		for cc in [Vector2(2, 2), Vector2(TAM - 4, 2), Vector2(2, TAM - 4), Vector2(TAM - 4, TAM - 4)]:
			draw_rect(Rect2(o + cc, Vector2(2, 2)), CINZA_ESC)


func _placa_solta() -> void:
	var o := JANELA + pos.round()
	if tex_placa:
		draw_texture(tex_placa, o + Vector2(2, 3), Color(PRETO, 0.5))                 # sombra: a placa está na frente
		draw_texture(tex_placa, o)
	else:
		draw_rect(Rect2(o + Vector2(2, 3), Vector2(TAM, TAM)), Color(PRETO, 0.45))
		_placa_provisoria(o)
		for cc in [Vector2(2, 2), Vector2(TAM - 4, 2), Vector2(2, TAM - 4), Vector2(TAM - 4, TAM - 4)]:
			draw_rect(Rect2(o + cc, Vector2(2, 2)), FUNDO)                         # furos dos parafusos


func _placa_provisoria(o: Vector2) -> void:
	draw_rect(Rect2(o, Vector2(TAM, TAM)), PRETO)
	draw_rect(Rect2(o + Vector2.ONE, Vector2(TAM - 2, TAM - 2)), METAL_CLARO)
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(TAM - 2, 1)), BRANCO)
	for k in range(0, TAM - 2, 4):                   # faixa amarela e preta embaixo
		draw_rect(Rect2(o + Vector2(1 + k, TAM - 5), Vector2(2, 3)), AMARELO)
		draw_rect(Rect2(o + Vector2(3 + k, TAM - 5), Vector2(2, 3)), PRETO)


## Tempo que sobra para a placa atual: barrinha na base da parede (fica vermelha no fim).
func _barra_tempo() -> void:
	var f := clampf(t_placa / TEMPO_PLACA, 0.0, 1.0)
	var r := Rect2(JANELA + Vector2(4, TAM_JANELA.y - 4), Vector2(TAM_JANELA.x - 8, 2))
	draw_rect(r, Color(PRETO, 0.7))
	draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), VERDE_LIMA if f > 0.3 else VERMELHO_CLARO)


func _parede_provisoria() -> void:
	draw_rect(Rect2(JANELA, TAM_JANELA), CINZA_ESC)
	for y in range(0, 121, 30):
		for x in range(0, 192, 48):
			var r := Rect2(JANELA + Vector2(x + 1, y + 1), Vector2(46, 28))
			draw_rect(r, CINZA)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), METAL)
			for cc in [Vector2(2, 2), Vector2(42, 2), Vector2(2, 24), Vector2(42, 24)]:
				draw_rect(Rect2(r.position + cc, Vector2.ONE), METAL_CLARO)


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


# --- Síntese de áudio procedural sem dependências externas ---
static func _sintetizar_som_parafuso() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.35
	var sample_count: int = int(duracao * 22050.0)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var st: float = float(i) / 22050.0
		var r: float = randf_range(-1.0, 1.0) * exp(-st * 16.0)
		var thud: float = sin(st * 140.0 * TAU) * exp(-st * 22.0)
		var drill: float = sin(st * 480.0 * TAU) * (0.6 if st < 0.22 else 0.0)
		var sample: float = (r * 0.3 + thud * 0.4 + drill * 0.4) * 0.95
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)
	stream.data = data
	return stream


static func _sintetizar_som_erro() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.25
	var sample_count: int = int(duracao * 22050.0)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var st: float = float(i) / 22050.0
		var freq: float = 140.0 if fmod(st, 0.08) < 0.04 else 105.0
		var onda: float = sin(st * freq * TAU)
		var env: float = exp(-st * 6.0)
		var val: int = int(clampf(onda * env * 0.65, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)
	stream.data = data
	return stream


static func _sintetizar_som_sucesso() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.60
	var sample_count: int = int(duracao * 22050.0)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var st: float = float(i) / 22050.0
		var f: float = 523.25
		if st > 0.30:
			f = 783.99
		elif st > 0.15:
			f = 659.25
		var onda: float = sin(st * f * TAU) * 0.7 + sin(st * f * 2.0 * TAU) * 0.3
		var env: float = exp(-st * 4.2)
		var val: int = int(clampf(onda * env * 0.70, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)
	stream.data = data
	return stream
