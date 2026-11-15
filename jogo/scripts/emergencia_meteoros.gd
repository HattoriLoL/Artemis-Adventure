class_name EmergenciaMeteoros
extends Node2D
## Sistema autônomo de Emergência e Chuva de Meteoros (GDD Seções 8, 17 e 19).
## Sorteia 1 ocorrência durante a missão (fora das noites e fora do sono).
## Avisa com sirene e banner no HUD: [!] METEOR IMPACT INCOMING: <SALA> [25s]
## Gera uma estação de emergência com contorno pulsante na sala sorteada.
## Se o jogador interagir a tempo (tecla E), os escudos seguram o impacto sem danos.
## Se o tempo zerar, a base sofre tremor de tela (0.5s) e avaria nos recursos.
## Atalho F8 disponível para teste imediato de debug.

const Fonte = preload("res://scripts/fonte.gd")

const PRETO := Color("#090a14")
const FUNDO := Color("#151d28")
const AMARELO := Color("#e8c170")
const VERMELHO := Color("#cf573c")
const VERDE := Color("#a8ca58")
const BRANCO := Color("#ebede9")
const CINZA := Color("#819796")
const CINZA_ESC := Color("#394a50")
const AZUL := Color("#73bed3")

const DURACAO_JANELA: float = 25.0
const DISTANCIA_USO: float = 26.0

const SETORES: Array[String] = ["energia", "abrigo", "suporte"]

const NOMES_SETORES: Dictionary = {
	"energia": "POWER ROOM",
	"abrigo": "SHELTER",
	"suporte": "LIFE SUPPORT"
}

const POSICOES_SETORES: Dictionary = {
	"energia": Vector2(243, 153),
	"abrigo": Vector2(776, 553),
	"suporte": Vector2(248, 953)
}

var mapa: Node2D = null
var ativa: bool = false
var ja_ocorreu: bool = false
var dia_sorteado: int = -1
var tempo_espera_dia: float = 0.0
var tempo_dia_decorrido: float = 0.0

var setor_atual: String = ""
var posicao_estacao: Vector2 = Vector2.ZERO
var tempo_restante: float = 0.0
var t_animacao: float = 0.0
var t_proximo_bip: float = 0.0

var status_resolucao: String = ""
var texto_resolucao: String = ""
var t_banner_resolucao: float = 0.0
var alavanca_puxada: bool = false

var player_alarme: AudioStreamPlayer = null
var player_sfx: AudioStreamPlayer = null
var som_sirene: AudioStreamWAV = null
var som_sucesso: AudioStreamWAV = null
var som_impacto: AudioStreamWAV = null
var som_clank: AudioStreamWAV = null


func _ready() -> void:
	z_index = 2
	_criar_audio()


func _criar_audio() -> void:
	som_sirene = _sintetizar_sirene()
	som_sucesso = _sintetizar_sucesso()
	som_impacto = _sintetizar_impacto()
	som_clank = _sintetizar_clank()

	player_alarme = AudioStreamPlayer.new()
	player_alarme.stream = som_sirene
	player_alarme.volume_db = -4.0
	add_child(player_alarme)

	player_sfx = AudioStreamPlayer.new()
	player_sfx.volume_db = -3.0
	add_child(player_sfx)


func iniciar(p_mapa: Node2D) -> void:
	mapa = p_mapa
	_sortear_dia()


func _sortear_dia() -> void:
	if mapa == null or not mapa.has_node("CicloDias"):
		dia_sorteado = 2
		tempo_espera_dia = 18.0
		return

	var ciclo: Node = mapa.get("ciclo")
	var dias_validos: Array[int] = []
	var total: int = int(ciclo.call("total_dias")) if ciclo.has_method("total_dias") else 5
	for d in range(2, total + 1):
		var eh_noite: bool = bool(ciclo.call("eh_noite", d)) if ciclo.has_method("eh_noite") else false
		if not eh_noite:
			dias_validos.append(d)

	if dias_validos.is_empty():
		dia_sorteado = 2
	else:
		dia_sorteado = dias_validos.pick_random()

	tempo_espera_dia = randf_range(14.0, 26.0)
	tempo_dia_decorrido = 0.0
	print("EmergenciaMeteoros: Agendada para o Dia %d (apos %.1fs de atividade)" % [dia_sorteado, tempo_espera_dia])


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_F8:
			print("EmergenciaMeteoros: Disparo manual de teste (F8)")
			disparar()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	t_animacao += delta

	# Agendamento autônomo durante o dia sorteado
	if not ja_ocorreu and not ativa and mapa != null:
		var dia_atual: int = int(Missao.dia)
		var dormindo: bool = bool(mapa.get("dormindo"))
		var em_minigame: bool = bool(mapa.get("em_minigame"))
		var fim: bool = bool(mapa.get("fim"))
		var ciclo_ocupado: bool = false
		if mapa.has_node("CicloDias") or mapa.get("ciclo") != null:
			var c: Node = mapa.get("ciclo")
			if c.has_method("ocupado"):
				ciclo_ocupado = bool(c.call("ocupado"))

		if dia_atual == dia_sorteado and not dormindo and not em_minigame and not ciclo_ocupado and not fim:
			tempo_dia_decorrido += delta
			if tempo_dia_decorrido >= tempo_espera_dia:
				disparar()

	if ativa:
		tempo_restante -= delta
		t_proximo_bip -= delta
		if t_proximo_bip <= 0.0:
			_tocar_sirene()
			t_proximo_bip = 2.4

		queue_redraw()

		if tempo_restante <= 0.0:
			_falhar_impacto()

	if t_banner_resolucao > 0.0:
		t_banner_resolucao = maxf(0.0, t_banner_resolucao - delta)


func disparar(setor_forcado: String = "") -> void:
	if ativa:
		return

	ja_ocorreu = true
	if setor_forcado != "" and SETORES.has(setor_forcado):
		setor_atual = setor_forcado
	else:
		setor_atual = SETORES.pick_random()

	posicao_estacao = POSICOES_SETORES.get(setor_atual, Vector2(243, 153))
	tempo_restante = DURACAO_JANELA
	ativa = true
	alavanca_puxada = false
	status_resolucao = ""
	texto_resolucao = ""
	t_banner_resolucao = 0.0
	t_proximo_bip = 0.0

	var nome_sala: String = NOMES_SETORES.get(setor_atual, setor_atual.to_upper())
	print("EmergenciaMeteoros: ALERTA DE METEOROS! Setor: %s, Janela: 25s" % nome_sala)

	if not Missao.historico.is_empty():
		Missao.historico[-1]["acoes"].append("[ALERT] METEOR SHOWER TARGETING " + nome_sala)

	_tocar_sirene()
	queue_redraw()


func perto_estacao(pos_jogador: Vector2) -> bool:
	if not ativa:
		return false
	return pos_jogador.distance_to(posicao_estacao) <= DISTANCIA_USO


func bot_quer_usar(pos_jogador: Vector2) -> bool:
	return ativa and pos_jogador.distance_to(posicao_estacao) <= DISTANCIA_USO


func ativar_escudos() -> void:
	if not ativa:
		return

	ativa = false
	alavanca_puxada = true
	status_resolucao = "sucesso"
	texto_resolucao = "SHIELDS HELD // BASE SECURED"
	t_banner_resolucao = 3.5

	_parar_alarme()
	_tocar_clank_e_sucesso()

	var nome_sala: String = NOMES_SETORES.get(setor_atual, setor_atual.to_upper())
	if not Missao.historico.is_empty():
		Missao.historico[-1]["acoes"].append("METEORS: SHIELDS HELD IN " + nome_sala + " (NO DAMAGE)")

	if mapa != null and mapa.has_method("_avisar"):
		mapa.call("_avisar", texto_resolucao)

	queue_redraw()
	print("EmergenciaMeteoros: Escudos acionados a tempo! A base foi totalmente protegida.")


func _falhar_impacto() -> void:
	if not ativa:
		return

	ativa = false
	status_resolucao = "falha"
	var nome_sala: String = NOMES_SETORES.get(setor_atual, setor_atual.to_upper())
	texto_resolucao = "[!] METEOR IMPACT // %s DAMAGED!" % nome_sala
	t_banner_resolucao = 3.5

	_parar_alarme()
	_tocar_impacto()

	# Tremor de tela de 0.5s
	if mapa != null and mapa.has_method("tremer_tela"):
		mapa.call("tremer_tela", 0.5, 3.5)

	# Aplica dano direto aos recursos
	_aplicar_dano_recursos()

	if not Missao.historico.is_empty():
		Missao.historico[-1]["acoes"].append("METEORS: IMPACT IN " + nome_sala + " (HULL DAMAGE)")

	if mapa != null and mapa.has_method("_avisar"):
		mapa.call("_avisar", texto_resolucao)

	queue_redraw()
	print("EmergenciaMeteoros: Tempo esgotado! Impacto de meteoros no setor %s." % nome_sala)


func _aplicar_dano_recursos() -> void:
	var id_emergencia := "emergencia/" + setor_atual
	# Garante que a regra de dano exista mesmo se o JSON for sobrescrito
	if not Recursos.regras.get("efeitos", {}).has(id_emergencia):
		if not Recursos.regras.has("efeitos"):
			Recursos.regras["efeitos"] = {}
		match setor_atual:
			"energia":
				Recursos.regras["efeitos"][id_emergencia] = {"energia": -20.0, "condicao": -10.0}
			"abrigo":
				Recursos.regras["efeitos"][id_emergencia] = {"condicao": -15.0, "oxigenio": -10.0}
			"suporte":
				Recursos.regras["efeitos"][id_emergencia] = {"oxigenio": -15.0, "condicao": -10.0}

	Recursos.aplicar(id_emergencia)


func _draw() -> void:
	# Desenha as Alavancas de Emergência nas 3 salas da base
	for s: String in SETORES:
		var pos: Vector2 = POSICOES_SETORES[s]
		var eh_alvo_ativo: bool = ativa and s == setor_atual
		var eh_alvo_resolvido: bool = (t_banner_resolucao > 0.0) and (s == setor_atual)
		_desenhar_estacao_alavanca(pos, eh_alvo_ativo, eh_alvo_resolvido)


func _desenhar_estacao_alavanca(p: Vector2, alvo_ativo: bool, alvo_resolvido: bool) -> void:
	var pulso: float = (sin(t_animacao * 8.0) + 1.0) * 0.5
	var cor_pulso: Color = VERMELHO.lerp(AMARELO, pulso)

	# 1. Retículo / Perímetro Tático quando a emergência está ativa nesta sala
	if alvo_ativo:
		var r_tatico := Rect2(p.x - 13, p.y - 25, 26, 30)
		draw_rect(r_tatico, Color(cor_pulso, 0.25), false, 1.0)
		var d: float = 13.0
		var tam_c: float = 4.0
		# Cantoneiras táticas pulsantes
		draw_line(p + Vector2(-d, -25), p + Vector2(-d + tam_c, -25), cor_pulso, 1.2)
		draw_line(p + Vector2(-d, -25), p + Vector2(-d, -25 + tam_c), cor_pulso, 1.2)
		draw_line(p + Vector2(d, -25), p + Vector2(d - tam_c, -25), cor_pulso, 1.2)
		draw_line(p + Vector2(d, -25), p + Vector2(d, -25 + tam_c), cor_pulso, 1.2)
		draw_line(p + Vector2(-d, 5), p + Vector2(-d + tam_c, 5), cor_pulso, 1.2)
		draw_line(p + Vector2(-d, 5), p + Vector2(-d, 5 - tam_c), cor_pulso, 1.2)
		draw_line(p + Vector2(d, 5), p + Vector2(d - tam_c, 5), cor_pulso, 1.2)
		draw_line(p + Vector2(d, 5), p + Vector2(d, 5 - tam_c), cor_pulso, 1.2)

	# 2. Pedestal Metálico e Caixa da Alavanca
	draw_rect(Rect2(p.x - 8, p.y - 15, 16, 20), PRETO)
	draw_rect(Rect2(p.x - 7, p.y - 14, 14, 18), CINZA_ESC)
	draw_rect(Rect2(p.x - 6, p.y - 13, 12, 16), FUNDO)

	# Faixas Zebradas de Perigo (Hazard Stripes) na base do console
	for stripe: int in 4:
		var xs: float = p.x - 6.0 + float(stripe) * 3.0
		draw_rect(Rect2(xs, p.y + 1, 2.0, 3.0), AMARELO if stripe % 2 == 0 else PRETO)

	# Canaleta / Fenda vertical de acionamento da alavanca
	draw_rect(Rect2(p.x - 2, p.y - 11, 4, 10), Color("#0a1017"))
	draw_rect(Rect2(p.x - 1, p.y - 10, 2, 8), PRETO)

	# Pivô da alavanca (eixo circular metálico)
	var pivo := Vector2(p.x, p.y - 3)
	draw_circle(pivo, 2.2, CINZA)
	draw_circle(pivo, 1.2, BRANCO)

	# 3. Braço e Manopla da Alavanca Mecânica
	var p_fim_braco: Vector2
	var cor_manopla: Color

	if alvo_resolvido and alavanca_puxada:
		# Posição PUXADA PARA BAIXO (ativada / escudos travados)
		p_fim_braco = pivo + Vector2(5.0, 3.0)
		draw_line(pivo, p_fim_braco, Color("#a8b5b2"), 1.8)
		cor_manopla = VERDE_LIMA
		draw_circle(p_fim_braco, 2.6, cor_manopla)
		draw_rect(Rect2(p_fim_braco.x - 0.5, p_fim_braco.y - 0.5, 1.0, 1.0), BRANCO)
	elif alvo_ativo:
		# Posição ARMADA PARA CIMA (aguardando puxar)
		p_fim_braco = pivo + Vector2(-5.0, -7.0)
		draw_line(pivo, p_fim_braco, BRANCO, 1.8)
		cor_manopla = VERMELHO_CLARO if fmod(t_animacao, 0.2) < 0.1 else AMARELO
		draw_circle(p_fim_braco, 2.8, cor_manopla)
		draw_circle(p_fim_braco, 1.4, BRANCO)
	else:
		# Posição NEUTRA / REPOUSO em salas sem alarme
		p_fim_braco = pivo + Vector2(0.0, -6.5)
		draw_line(pivo, p_fim_braco, Color("#819796"), 1.6)
		cor_manopla = Color("#852828")
		draw_circle(p_fim_braco, 2.2, cor_manopla)

	# 4. Giroflex / Alerta no Topo da Caixa da Alavanca
	var p_strobe := Vector2(p.x, p.y - 16)
	draw_rect(Rect2(p.x - 3, p.y - 16, 6, 2), CINZA)
	if alvo_ativo:
		var aceso: bool = fmod(t_animacao, 0.24) < 0.12
		var c_luz: Color = BRANCO if aceso else VERMELHO_CLARO
		draw_circle(p_strobe, 6.0, Color(VERMELHO.r, VERMELHO.g, VERMELHO.b, 0.35))
		draw_rect(Rect2(p.x - 2, p.y - 19, 4, 3), c_luz)
	elif alvo_resolvido and alavanca_puxada:
		draw_circle(p_strobe, 4.0, Color(VERDE.r, VERDE.g, VERDE.b, 0.3))
		draw_rect(Rect2(p.x - 2, p.y - 19, 4, 3), VERDE_LIMA)
	else:
		draw_rect(Rect2(p.x - 2, p.y - 19, 4, 3), Color("#394a50"))

	# 5. Indicador Flutuante com Seta e Texto "LEVER" quando ativa
	if alvo_ativo:
		var y_flutuante: float = p.y - 25.0 + round(sin(t_animacao * 6.0) * 2.0)
		var pts := PackedVector2Array([
			Vector2(p.x - 4, y_flutuante - 2),
			Vector2(p.x + 4, y_flutuante - 2),
			Vector2(p.x, y_flutuante + 3)
		])
		draw_polygon(pts, [cor_pulso])
		Fonte.centralizado(self, "LEVER", p.x, y_flutuante - 9.0, AMARELO)


func desenhar_hud(hud: Control, t: float) -> void:
	# Alerta compacto posicionado no canto inferior direito, logo ACIMA do minimapa!
	# Não interfere com Lista de Tarefas (canto sup. esq), Túnel, Jogador ou Minimapa.
	var bx: float = 236.0
	var by: float = 68.0
	var bw: float = 79.0
	var bh: float = 24.0

	if ativa:
		var segs: int = ceili(tempo_restante)
		var sala_nome: String = NOMES_SETORES.get(setor_atual, setor_atual.to_upper())
		var pulso_hud: float = (sin(t * 10.0) + 1.0) * 0.5
		var cor_borda: Color = VERMELHO.lerp(AMARELO, pulso_hud)
		var cor_header: Color = AMARELO if fmod(t, 0.4) < 0.2 else BRANCO

		# Caixa de alerta tática compacta
		hud.draw_rect(Rect2(bx, by, bw, bh), Color(0.04, 0.02, 0.02, 0.90))
		hud.draw_rect(Rect2(bx, by, bw, bh), cor_borda, false, 1.0)
		hud.draw_rect(Rect2(bx + 1, by + 1, 3, bh - 2), cor_borda)

		# Linha 1: Contagem de impacto
		Fonte.centralizado(hud, "[!] METEOR %dS" % segs, bx + bw / 2.0 + 1.0, by + 4.0, cor_header)
		# Linha 2: Sala alvo
		Fonte.centralizado(hud, "> " + sala_nome, bx + bw / 2.0 + 1.0, by + 13.0, cor_borda)

	elif t_banner_resolucao > 0.0:
		var sala_nome: String = NOMES_SETORES.get(setor_atual, setor_atual.to_upper())
		if status_resolucao == "sucesso":
			hud.draw_rect(Rect2(bx, by, bw, bh), Color(0.02, 0.05, 0.03, 0.92))
			hud.draw_rect(Rect2(bx, by, bw, bh), VERDE, false, 1.0)
			hud.draw_rect(Rect2(bx + 1, by + 1, 3, bh - 2), VERDE_LIMA)
			Fonte.centralizado(hud, "[!] SHIELDS UP", bx + bw / 2.0 + 1.0, by + 4.0, VERDE_LIMA)
			Fonte.centralizado(hud, "BASE SECURED", bx + bw / 2.0 + 1.0, by + 13.0, BRANCO)
		else:
			hud.draw_rect(Rect2(bx, by, bw, bh), Color(0.06, 0.02, 0.02, 0.92))
			hud.draw_rect(Rect2(bx, by, bw, bh), VERMELHO, false, 1.0)
			hud.draw_rect(Rect2(bx + 1, by + 1, 3, bh - 2), VERMELHO)
			Fonte.centralizado(hud, "[!] IMPACT!", bx + bw / 2.0 + 1.0, by + 4.0, VERMELHO_CLARO)
			Fonte.centralizado(hud, "%s HIT" % sala_nome, bx + bw / 2.0 + 1.0, by + 13.0, AMARELO)


func _tocar_sirene() -> void:
	if player_alarme != null:
		player_alarme.stream = som_sirene
		player_alarme.play()


func _parar_alarme() -> void:
	if player_alarme != null and player_alarme.playing:
		player_alarme.stop()


func _tocar_clank_e_sucesso() -> void:
	if player_sfx != null:
		player_sfx.stream = som_clank if som_clank != null else som_sucesso
		player_sfx.play()
		# Toca o chime de sucesso logo em seguida
		get_tree().create_timer(0.18).timeout.connect(func():
			if player_sfx != null:
				player_sfx.stream = som_sucesso
				player_sfx.play()
		)


static func _sintetizar_clank() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.22
	var sample_count: int = int(duracao * 22050.0)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in range(sample_count):
		var t: float = float(i) / 22050.0
		var r: float = randf_range(-1.0, 1.0) * exp(-t * 22.0)
		var thud: float = sin(t * 120.0 * TAU) * exp(-t * 18.0)
		var click: float = sin(t * 880.0 * TAU) * exp(-t * 40.0)
		var sample: float = (r * 0.4 + thud * 0.45 + click * 0.35) * 0.95
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream


func _tocar_impacto() -> void:
	if player_sfx != null:
		player_sfx.stream = som_impacto
		player_sfx.play()


# --- Síntese de áudio procedural sem dependências externas ---
static func _sintetizar_sirene() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.55
	var sample_count: int = int(duracao * 22050.0)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in range(sample_count):
		var t: float = float(i) / 22050.0
		var freq: float = 880.0 if fmod(t, 0.18) < 0.09 else 660.0
		var onda: float = sin(t * freq * TAU)
		var env: float = clampf(1.0 - (t / duracao) * 0.4, 0.0, 1.0)
		var sample: float = onda * env * 0.55
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream


static func _sintetizar_sucesso() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.65
	var sample_count: int = int(duracao * 22050.0)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in range(sample_count):
		var t: float = float(i) / 22050.0
		var f: float = 523.25
		if t > 0.32:
			f = 783.99
		elif t > 0.16:
			f = 659.25

		var harm: float = sin(t * f * TAU) * 0.7 + sin(t * f * 2.0 * TAU) * 0.3
		var env: float = exp(-t * 3.8)
		var sample: float = harm * env * 0.65
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream


static func _sintetizar_impacto() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duracao: float = 0.60
	var sample_count: int = int(duracao * 22050.0)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in range(sample_count):
		var t: float = float(i) / 22050.0
		var ruido: float = randf_range(-1.0, 1.0)
		var sub_bass: float = sin(t * 48.0 * TAU)
		var onda: float = ruido * 0.55 + sub_bass * 0.45
		var env: float = exp(-t * 5.2)
		var sample: float = onda * env * 0.85
		var val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)

	stream.data = data
	return stream
