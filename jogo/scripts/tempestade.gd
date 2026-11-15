extends CanvasLayer
## Erupção solar (tempestade de prótons): num dia sorteado da missão (Missao.dia_erupcao, avisado no boletim da
## véspera), o alarme toca logo depois que o jogador conclui a 1ª ou a 2ª tarefa do dia (sorteado), ou quando ele
## tenta dormir antes disso. Ele tem
## radiacao.tempo_abrigo segundos para chegar ao Abrigo (a sala "abrigo"): a tela pulsa em vermelho, a sirene toca,
## o minimapa pisca o Abrigo e as tarefas ficam bloqueadas. Chegando ou não, o resto das ações do dia se perde e o
## dia termina ali; o dano na saúde (Recursos.dano_tempestade) entra no fechamento da noite (ciclo_dias.gd).
## Na vida real, os prótons de uma erupção chegam minutos ou horas depois dela, e a tripulação se protege na parte
## mais blindada da base. A ideia do alarme com sirene e luz de emergência veio do PR #24 (IltonBJSilva).
## Criado pelo mapa.gd; desenhado em código como o resto da interface.

const Fonte = preload("res://scripts/fonte.gd")
const VERMELHO := Color("#cf573c")
const AMARELO := Color("#e8c170")
const BRANCO := Color("#ebede9")
const PRETO := Color("#090a14")
const SALA_ABRIGO := "abrigo"

var mapa: Node2D                   # o mapa.gd (quem cria preenche)
var ativo := false
var t_resta := 0.0
var t := 0.0
var tela: Control
var sirene: AudioStreamPlayer
var direcao := Vector2.ZERO        # para onde a seta aponta: o próximo trecho do caminho até o Abrigo
var t_caminho := 0.0


func _ready() -> void:
	layer = 12                     # acima do HUD, abaixo dos painéis do ciclo (15) e do menu de pausa (20)
	tela = Control.new()
	tela.size = Vector2(320, 180)
	tela.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tela.visible = false
	tela.draw.connect(_desenha)
	add_child(tela)
	sirene = AudioStreamPlayer.new()
	sirene.stream = _sirene()
	sirene.volume_db = -16.0
	add_child(sirene)


## O alarme dispara agora (chamado pelo mapa depois da primeira tarefa do dia da erupção).
func iniciar() -> void:
	ativo = true
	t = 0.0
	t_resta = float(Recursos.regras["radiacao"]["tempo_abrigo"])
	t_caminho = 0.0
	tela.visible = true
	sirene.play()
	mapa.jogador.bot_correr = true


## Fim do alarme: chegou ou não ao Abrigo. Perde o resto das ações do dia e (com `encerrar`) o dia termina.
## O robô de teste chama com encerrar = false e fecha o dia ele mesmo.
func resolver(no_abrigo: bool, encerrar := true) -> void:
	ativo = false
	tela.visible = false
	sirene.stop()
	mapa.jogador.bot_correr = false
	Missao.tempestade = {"dia": Missao.dia, "abrigo": no_abrigo}
	mapa.ciclo.acoes = mapa.ciclo.acoes_por_dia()
	mapa._atualizar_marcas()
	if encerrar:
		mapa.fim_do_dia_tempestade(no_abrigo)


func _process(delta: float) -> void:
	if not ativo:
		return
	t += delta
	if mapa.sala_atual == SALA_ABRIGO:
		resolver(true)
		return
	t_resta -= delta
	if t_resta <= 0.0:
		resolver(false)
		return
	t_caminho -= delta
	if t_caminho <= 0.0:
		t_caminho = 0.25
		direcao = _direcao_abrigo()
	tela.queue_redraw()


## Direção do caminho de verdade (grade de navegação) até o Abrigo, a uns 40 px à frente: a linha reta
## apontaria para uma parede (do Suporte, por exemplo, o caminho desce pelo túnel e sobe pela estufa).
func _direcao_abrigo() -> Vector2:
	var ab: Dictionary = mapa.salas[SALA_ABRIGO]
	var tam: Array = ab["dados"]["tamanho"]
	var alvo: Vector2 = ab["pos"] + Vector2(tam[0], tam[1]) / 2.0
	var p: Vector2 = mapa.jogador.global_position
	var cam: PackedVector2Array = mapa.astar.get_point_path(mapa._livre_perto(Vector2i(p / mapa.celula)),
		mapa._livre_perto(Vector2i(alvo / mapa.celula)))
	for ponto in cam:
		if p.distance_to(ponto) >= 40.0:
			return (ponto - p).normalized()
	return (alvo - p).normalized()


func _desenha() -> void:
	var pulso := 0.2 + 0.14 * (0.5 + 0.5 * sin(t * 7.0))
	tela.draw_rect(Rect2(0, 0, 320, 180), Color(VERMELHO, pulso))
	var r := Rect2(48, 122, 204, 30)               # embaixo, longe do astronauta (meio da tela) e do minimapa
	tela.draw_rect(r, Color(PRETO, 0.85))
	tela.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), VERMELHO)
	tela.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), VERMELHO)
	var cor := AMARELO if fmod(t, 0.5) < 0.25 else BRANCO
	var cx := r.get_center().x
	Fonte.centralizado(tela, "SOLAR STORM! RUN TO THE SHELTER", cx, r.position.y + 4, cor)
	Fonte.centralizado(tela, str(ceili(t_resta)), cx, r.position.y + 12, VERMELHO, 2)
	var ev: Dictionary = Missao.evento_solar
	if not ev.is_empty():
		Fonte.centralizado(tela, "REAL EVENT: %s (NASA DONKI)" % ev["data"], cx, r.end.y + 4, BRANCO)
	_desenha_seta()


## Seta amarela girando em volta do astronauta, apontando o caminho até o Abrigo.
func _desenha_seta() -> void:
	if direcao == Vector2.ZERO:
		return
	var no_tela: Vector2 = mapa.get_viewport().get_canvas_transform() * mapa.jogador.global_position
	var c := (no_tela + Vector2(0, -20) + direcao * (24.0 + 2.0 * sin(t * 10.0))).round()
	var lado := Vector2(-direcao.y, direcao.x)
	var ponta := c + direcao * 6.0
	var base1 := c - direcao * 4.0 + lado * 5.0
	var base2 := c - direcao * 4.0 - lado * 5.0
	tela.draw_colored_polygon(PackedVector2Array([ponta + direcao * 1.5, base1 + (base1 - c).normalized() * 1.5,
		base2 + (base2 - c).normalized() * 1.5]), PRETO)
	tela.draw_colored_polygon(PackedVector2Array([ponta, base1, base2]), AMARELO if fmod(t, 0.4) < 0.25 else BRANCO)


## Sirene de dois tons (onda quadrada suave, em loop), feita no código: o jogo não tem arquivo de som para isso.
func _sirene() -> AudioStreamWAV:
	var taxa := 22050
	var n := taxa                   # 1 s: meio segundo em cada tom
	var dados := PackedByteArray()
	dados.resize(n * 2)
	var fase := 0.0
	for i in n:
		var tt := float(i) / taxa
		var f := 620.0 if tt < 0.5 else 860.0
		fase += TAU * f / taxa
		var env := minf(1.0, minf(fmod(tt, 0.5), 0.5 - fmod(tt, 0.5)) * 40.0)   # sem estalo na troca de tom
		var v := (0.6 if sin(fase) > 0.0 else -0.6) * env
		dados.encode_s16(i * 2, int(v * 12000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = taxa
	s.stereo = false
	s.data = dados
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s
