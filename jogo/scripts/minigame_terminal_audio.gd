class_name AudioTerminal
extends Node
## Módulo de síntese procedural de áudio nativo em GDScript para o Terminal de Disjuntores.
## Gera buffers de áudio PCM diretamente em AudioStreamWAV (16-bit mono @ 22050Hz).
## Não depende de arquivos externos ou assets pré-gravados.

const TAXA_AMOSTRAGEM: int = 22050
const CANAIS: int = 1 # Mono

# Frequências padrão para bips de sequência (índices 0 a 3)
const FREQS_BIP: Array[float] = [440.0, 660.0, 880.0, 1100.0]

# Cache em memória para evitar re-sintetização durante o jogo
static var _cache_clique: AudioStreamWAV = null
static var _cache_encaixe: AudioStreamWAV = null
static var _cache_bips: Array[AudioStreamWAV] = []
static var _cache_erro: AudioStreamWAV = null
static var _cache_rearme: AudioStreamWAV = null

# Pool de players para reprodução polifônica gerenciada
var _players_pool: Array[AudioStreamPlayer] = []
var _tamanho_pool: int = 6
var _player_idx: int = 0
var volume_master_db: float = 0.0


func _ready() -> void:
	_inicializar_pool()
	pre_carregar_todos()


# ==============================================================================
# SÍNTESE PROCEDURAL DE ÁUDIO (100% GDScript)
# ==============================================================================

## 1. Clique mecânico pesado e nítido (snap metálico de chave rocker com impacto seco ~0.08s).
static func sintetizar_clique_disjuntor() -> AudioStreamWAV:
	var duracao: float = 0.08
	var total_amostras: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total_amostras * 2)

	var fase_thud: float = 0.0
	for i: int in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)

		# Envelopes de decaimento físico rápido
		var env_snap: float = exp(-t / 0.007)
		var env_corpo: float = exp(-t / 0.024)
		var env_geral: float = clampf((duracao - t) / 0.008, 0.0, 1.0)

		# Ruído branco mecânico inicial (atrito e micro-centelha mecânica)
		var ruido: float = (randf() * 2.0 - 1.0) * env_snap * 0.40

		# Ressonância metálica de alta frequência (palheta de mola da chave rocker)
		var snap_metal: float = sin(TAU * 3200.0 * t) * env_snap * 0.45
		var snap_armacao: float = sin(TAU * 1450.0 * t) * exp(-t / 0.015) * 0.30

		# Thud mecânico grave (alavanca rocker atingindo o batente físico)
		var freq_thud: float = 55.0 + 190.0 * exp(-t / 0.018)
		fase_thud += TAU * freq_thud / float(TAXA_AMOSTRAGEM)
		var thud: float = sin(fase_thud) * env_corpo * 0.65

		# Mixagem com leve saturação quente
		var sinal: float = (ruido + snap_metal + snap_armacao + thud) * env_geral
		sinal = clampf(sinal * 0.90, -1.0, 1.0)

		var val_s16: int = int(sinal * 32767.0)
		bytes.encode_s16(i * 2, val_s16)

	return _construir_stream_wav(bytes)


## 2. Som de relé de alta voltagem atracando (click duplo metálico com micro-ressonância ~0.12s).
static func sintetizar_encaixe_sucesso() -> AudioStreamWAV:
	var duracao: float = 0.12
	var total_amostras: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total_amostras * 2)

	var t_segundo_click: float = 0.022
	for i: int in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var env_geral: float = clampf((duracao - t) / 0.010, 0.0, 1.0)

		# Primeiro impacto (contatos de cobre encostando)
		var env_c1: float = exp(-t / 0.006)
		var click1: float = ((randf() * 2.0 - 1.0) * 0.35 + sin(TAU * 2600.0 * t) * 0.55) * env_c1

		# Segundo impacto (armadura magnética atracando no polo do solenoide)
		var click2: float = 0.0
		if t >= t_segundo_click:
			var dt: float = t - t_segundo_click
			var env_c2: float = exp(-dt / 0.014)
			var freq_thud: float = 80.0 + 130.0 * exp(-dt / 0.015)
			var thud_rele: float = sin(TAU * freq_thud * dt) * 0.70
			var ruido2: float = (randf() * 2.0 - 1.0) * 0.30 * exp(-dt / 0.005)
			click2 = (thud_rele + ruido2) * env_c2

		# Micro-ressonância metálica do chassi do contator
		var res1: float = sin(TAU * 1950.0 * t) * exp(-t / 0.035) * 0.28
		var res2: float = sin(TAU * 3300.0 * t) * exp(-t / 0.022) * 0.18

		var sinal: float = (click1 * 0.70 + click2 * 0.85 + res1 + res2) * env_geral
		sinal = clampf(sinal * 0.88, -1.0, 1.0)

		var val_s16: int = int(sinal * 32767.0)
		bytes.encode_s16(i * 2, val_s16)

	return _construir_stream_wav(bytes)


## 3. Tom curto e limpo senoidal/triangular de indicador luminoso da NASA (~0.15s).
## Frequências: 0: 440Hz, 1: 660Hz, 2: 880Hz, 3: 1100Hz.
static func sintetizar_bip_sequencia(indice: int = 0) -> AudioStreamWAV:
	var idx: int = clampi(indice, 0, FREQS_BIP.size() - 1)
	var freq: float = FREQS_BIP[idx]
	var duracao: float = 0.15
	var total_amostras: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total_amostras * 2)

	var fase: float = 0.0
	var passo_fase: float = TAU * freq / float(TAXA_AMOSTRAGEM)

	for i: int in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)

		# Envelope retro limpo: subida suave de 6ms, corpo firme, cauda exponencial
		var env: float = 1.0
		if t < 0.006:
			env = t / 0.006
		elif t > 0.090:
			env = exp(-(t - 0.090) / 0.025)
		env *= clampf((duracao - t) / 0.005, 0.0, 1.0)

		fase += passo_fase
		if fase >= TAU:
			fase -= TAU

		# Onda senoidal pura
		var onda_seno: float = sin(fase)

		# Onda triangular normalizada de -1.0 a +1.0
		var norm_fase: float = fase / TAU
		var onda_tri: float = 2.0 * absf(2.0 * (norm_fase - floorf(norm_fase + 0.5))) - 1.0

		# Timbre aeroespacial: mistura senoidal limpa (75%) com toque triangular (25%)
		var sinal: float = (onda_seno * 0.75 + onda_tri * 0.25) * env * 0.80
		sinal = clampf(sinal, -1.0, 1.0)

		var val_s16: int = int(sinal * 32767.0)
		bytes.encode_s16(i * 2, val_s16)

	return _construir_stream_wav(bytes)


## 4. Buzz elétrico seco de sobrecarga / desarme (onda quadrada descendente 120Hz -> 60Hz ~0.25s).
static func sintetizar_erro_disjuntor() -> AudioStreamWAV:
	var duracao: float = 0.25
	var total_amostras: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total_amostras * 2)

	var fase: float = 0.0
	var fase_sub: float = 0.0

	for i: int in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var progresso: float = t / duracao

		# Rampa de frequência descendente de 120Hz para 60Hz (frequência de rede desenergizando)
		var freq_atual: float = lerpf(120.0, 60.0, progresso)
		fase += TAU * freq_atual / float(TAXA_AMOSTRAGEM)
		if fase >= TAU:
			fase -= TAU

		fase_sub += TAU * (freq_atual * 0.5) / float(TAXA_AMOSTRAGEM)
		if fase_sub >= TAU:
			fase_sub -= TAU

		# Onda quadrada com harmônicos ímpares ásperos
		var sq: float = 1.0 if sin(fase) >= 0.0 else -1.0
		var harm3: float = sin(fase * 3.0) * 0.25
		var sub: float = (1.0 if sin(fase_sub) >= 0.0 else -1.0) * 0.20

		# Crepitação de arco elétrico
		var arco: float = (randf() * 2.0 - 1.0) * 0.12

		# Snap mecânico de desarme imediato no início (t < 0.015s)
		var snap_desarme: float = 0.0
		if t < 0.015:
			snap_desarme = ((randf() * 2.0 - 1.0) * 0.5 + sin(TAU * 850.0 * t) * 0.5) * exp(-t / 0.004)

		# Envelope de corte seco de sobrecarga
		var env: float = 1.0
		if t < 0.004:
			env = t / 0.004
		elif t > 0.200:
			env = clampf((duracao - t) / 0.050, 0.0, 1.0)

		var sinal: float = (sq * 0.50 + harm3 + sub + arco + snap_desarme) * env * 0.85
		sinal = clampf(sinal, -1.0, 1.0)

		var val_s16: int = int(sinal * 32767.0)
		bytes.encode_s16(i * 2, val_s16)

	return _construir_stream_wav(bytes)


## 5. Acorde harmônico ascendente de barramento energizado (sucesso final ~0.65s).
static func sintetizar_rearme_geral() -> AudioStreamWAV:
	var duracao: float = 0.65
	var total_amostras: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var bytes := PackedByteArray()
	bytes.resize(total_amostras * 2)

	# Definição das vozes do acorde maior ascendente (C4 -> G4 -> C5 -> E5 -> G5 -> C6 chime)
	# [tempo_inicio, freq_hz, amplitude, rampa_ataque, tau_decaimento]
	var vozes: Array[Array] = [
		[0.00, 261.63, 0.25, 0.015, 0.40], # C4 (barramento primário)
		[0.06, 392.00, 0.22, 0.012, 0.35], # G4
		[0.12, 523.25, 0.25, 0.010, 0.32], # C5
		[0.18, 659.25, 0.25, 0.008, 0.30], # E5
		[0.24, 783.99, 0.28, 0.008, 0.28], # G5
		[0.24, 1046.50, 0.20, 0.005, 0.22], # C6 chime de energização
	]

	var fases: Array[float] = []
	fases.resize(vozes.size())
	for k: int in range(vozes.size()):
		fases[k] = 0.0

	var fase_inversor: float = 0.0

	for i: int in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var acumulador: float = 0.0

		for v_idx: int in range(vozes.size()):
			var v: Array = vozes[v_idx]
			var t_inicio: float = v[0]
			var f_voz: float = v[1]
			var amp_voz: float = v[2]
			var t_att: float = v[3]
			var tau_dec: float = v[4]

			if t >= t_inicio:
				var dt: float = t - t_inicio
				fases[v_idx] += TAU * f_voz / float(TAXA_AMOSTRAGEM)
				if fases[v_idx] >= TAU:
					fases[v_idx] -= TAU

				var env_v: float = (dt / t_att) if dt < t_att else exp(-(dt - t_att) / tau_dec)
				var onda_v: float = sin(fases[v_idx]) * 0.85 + sin(fases[v_idx] * 2.0) * 0.15
				acumulador += onda_v * env_v * amp_voz

		# Zumbido sutil do inversor aeroespacial de 400Hz (padrão NASA Artemis)
		fase_inversor += TAU * 400.0 / float(TAXA_AMOSTRAGEM)
		if fase_inversor >= TAU:
			fase_inversor -= TAU
		var zumbido_400hz: float = sin(fase_inversor) * 0.04 * exp(-t / 0.50)
		acumulador += zumbido_400hz

		# Envelope master anti-estalo
		var env_master: float = clampf((duracao - t) / 0.020, 0.0, 1.0)
		var sinal: float = clampf(acumulador * env_master, -1.0, 1.0)

		var val_s16: int = int(sinal * 32767.0)
		bytes.encode_s16(i * 2, val_s16)

	return _construir_stream_wav(bytes)


# ==============================================================================
# CONSTRUÇÃO DO RECURSO AUDIOSTREAMWAV
# ==============================================================================

static func _construir_stream_wav(pcm_bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TAXA_AMOSTRAGEM
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm_bytes
	return stream


# ==============================================================================
# GERENCIAMENTO DE CACHE E PLAYER POLIFÔNICO
# ==============================================================================

## Pré-sintetiza e armazena todos os sons no cache estático em memória
static func pre_carregar_todos() -> void:
	if _cache_clique == null:
		_cache_clique = sintetizar_clique_disjuntor()
	if _cache_encaixe == null:
		_cache_encaixe = sintetizar_encaixe_sucesso()
	if _cache_bips.is_empty():
		for idx: int in range(FREQS_BIP.size()):
			_cache_bips.append(sintetizar_bip_sequencia(idx))
	if _cache_erro == null:
		_cache_erro = sintetizar_erro_disjuntor()
	if _cache_rearme == null:
		_cache_rearme = sintetizar_rearme_geral()


func _inicializar_pool() -> void:
	_players_pool.clear()
	for i: int in range(_tamanho_pool):
		var p := AudioStreamPlayer.new()
		p.name = "PlayerAudio_%d" % i
		p.bus = "Master"
		add_child(p)
		_players_pool.append(p)


func _obter_proximo_player() -> AudioStreamPlayer:
	if _players_pool.is_empty():
		_inicializar_pool()
	var player: AudioStreamPlayer = _players_pool[_player_idx]
	_player_idx = (_player_idx + 1) % _players_pool.size()
	return player


## Reproduz um AudioStreamWAV em um canal livre do pool
func tocar_stream(stream: AudioStreamWAV, volume_db: float = 0.0) -> AudioStreamPlayer:
	if stream == null:
		return null
	var p: AudioStreamPlayer = _obter_proximo_player()
	p.stop()
	p.stream = stream
	p.volume_db = volume_master_db + volume_db
	p.play()
	return p


## Métodos convenientes de reprodução imediata com volume customizável
func tocar_clique(volume_db: float = 0.0) -> void:
	if _cache_clique == null:
		_cache_clique = sintetizar_clique_disjuntor()
	tocar_stream(_cache_clique, volume_db)


func tocar_encaixe(volume_db: float = 0.0) -> void:
	if _cache_encaixe == null:
		_cache_encaixe = sintetizar_encaixe_sucesso()
	tocar_stream(_cache_encaixe, volume_db)


func tocar_bip(indice: int, volume_db: float = 0.0) -> void:
	if _cache_bips.is_empty():
		pre_carregar_todos()
	var idx: int = clampi(indice, 0, _cache_bips.size() - 1)
	tocar_stream(_cache_bips[idx], volume_db)


func tocar_erro(volume_db: float = 0.0) -> void:
	if _cache_erro == null:
		_cache_erro = sintetizar_erro_disjuntor()
	tocar_stream(_cache_erro, volume_db)


func tocar_rearme(volume_db: float = 0.0) -> void:
	if _cache_rearme == null:
		_cache_rearme = sintetizar_rearme_geral()
	tocar_stream(_cache_rearme, volume_db)


func parar_tudo() -> void:
	for p: AudioStreamPlayer in _players_pool:
		p.stop()


# ==============================================================================
# SUÍTE DE TESTES E VALIDAÇÃO DE GERAÇÃO
# ==============================================================================

## Executa bateria de testes validando geração, integridade dos buffers e metadados
static func testar_geracao_estatico() -> Dictionary:
	var relatorio: Dictionary = {
		"sucesso": true,
		"detalhes": {},
		"erros": []
	}

	# Teste 1: Clique
	var s_clique: AudioStreamWAV = sintetizar_clique_disjuntor()
	_validar_stream("clique_disjuntor", s_clique, 0.08, relatorio)

	# Teste 2: Encaixe
	var s_encaixe: AudioStreamWAV = sintetizar_encaixe_sucesso()
	_validar_stream("encaixe_sucesso", s_encaixe, 0.12, relatorio)

	# Teste 3: Bips (0 a 3)
	for i: int in range(4):
		var s_bip: AudioStreamWAV = sintetizar_bip_sequencia(i)
		_validar_stream("bip_%d" % i, s_bip, 0.15, relatorio)

	# Teste 4: Erro
	var s_erro: AudioStreamWAV = sintetizar_erro_disjuntor()
	_validar_stream("erro_disjuntor", s_erro, 0.25, relatorio)

	# Teste 5: Rearme geral
	var s_rearme: AudioStreamWAV = sintetizar_rearme_geral()
	_validar_stream("rearme_geral", s_rearme, 0.65, relatorio)

	print("[AudioTerminal] Relatório de Teste de Síntese:")
	for chave: String in relatorio["detalhes"]:
		var d: Dictionary = relatorio["detalhes"][chave]
		print("  - %s: %d bytes, %.3fs, taxa=%dHz, formato=%d, ok=%s" % [
			chave, d["bytes"], d["duracao_s"], d["mix_rate"], d["formato"], str(d["valido"])
		])

	if relatorio["erros"].size() > 0:
		relatorio["sucesso"] = false
		printerr("[AudioTerminal] Falhas no teste de síntese: ", relatorio["erros"])

	return relatorio


static func _validar_stream(nome: String, stream: AudioStreamWAV, duracao_esperada: float, relatorio: Dictionary) -> void:
	if stream == null:
		relatorio["erros"].append("%s: Stream é nulo!" % nome)
		return

	var bytes_size: int = stream.data.size()
	var amostras: int = bytes_size / 2 # 16-bit = 2 bytes por amostra
	var duracao_real: float = float(amostras) / float(stream.mix_rate)
	var diferenca_duracao: float = absf(duracao_real - duracao_esperada)

	var valido: bool = (
		bytes_size > 0 and
		stream.format == AudioStreamWAV.FORMAT_16_BITS and
		stream.mix_rate == TAXA_AMOSTRAGEM and
		not stream.stereo and
		diferenca_duracao < 0.01
	)

	if not valido:
		relatorio["erros"].append("%s: Falha na validação de formato/tempo!" % nome)

	relatorio["detalhes"][nome] = {
		"bytes": bytes_size,
		"amostras": amostras,
		"duracao_s": duracao_real,
		"mix_rate": stream.mix_rate,
		"formato": stream.format,
		"valido": valido
	}


## Wrapper de instância para teste
func executar_teste_sintese() -> Dictionary:
	return testar_geracao_estatico()
