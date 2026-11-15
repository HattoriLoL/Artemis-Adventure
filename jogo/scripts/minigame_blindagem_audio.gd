class_name AudioBlindagem
extends Node
## Sintetizador de Áudio Procedural para o Minigame de Blindagem (Artemis Adventure).
## Geração PCM 100% matemática em memória (AudioStreamWAV mono 16-bit @ 22.050 Hz).
## Zero dependência de arquivos externos no disco.

const TAXA_AMOSTRAGEM: int = 22050
const NUM_PLAYERS_POOL: int = 6

# Cache estático de ondas sintetizadas (geradas apenas UMA VEZ na execução)
static var _stream_servo: AudioStreamWAV = null
static var _stream_snap: AudioStreamWAV = null
static var _stream_parafusadeira: AudioStreamWAV = null
static var _stream_alarme: AudioStreamWAV = null
static var _stream_sucesso: AudioStreamWAV = null
static var _stream_erro: AudioStreamWAV = null
static var _streams_gerados: bool = false

# Player dedicado ao servo (suporta burst ou loop contínuo suave)
var _servo_player: AudioStreamPlayer = null
var _tempo_servo_restante: float = 0.0

# Pool polifônico pré-alocado para tocar múltiplos efeitos simultaneamente
var _players: Array[AudioStreamPlayer] = []
var _indice_pool: int = 0


func _init() -> void:
	garantir_streams()


func _ready() -> void:
	# 1. Configurar player dedicado do servo motor
	_servo_player = AudioStreamPlayer.new()
	_servo_player.name = "ServoPlayer"
	_servo_player.stream = _stream_servo
	_servo_player.volume_db = -12.0
	add_child(_servo_player)

	# 2. Configurar pool polifônico de 6 AudioStreamPlayers
	_players.clear()
	for i in range(NUM_PLAYERS_POOL):
		var p := AudioStreamPlayer.new()
		p.name = "AudioPool_%d" % i
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	# Gerencia o tempo de vida do burst do servo se chamado intermitentemente
	if _tempo_servo_restante > 0.0:
		_tempo_servo_restante -= delta
		if _tempo_servo_restante <= 0.0:
			if _servo_player != null and _servo_player.playing:
				_servo_player.stop()


# ==============================================================================
# MÉTODOS PÚBLICOS DE REPRODUÇÃO
# ==============================================================================

## Toca micro-ruído senoidal suave de servomotor hidráulico (80Hz modulado).
## Se chamado repetidamente durante movimentação, mantém o som ativo sem estalos.
func tocar_servo(volume_db: float = -12.0) -> void:
	if _servo_player == null:
		return
	_servo_player.volume_db = volume_db
	_tempo_servo_restante = 0.16 # Burst suave para cobrir frames de movimento
	if not _servo_player.playing:
		_servo_player.play()


## Interrompe o som do servo imediatamente.
func parar_servo() -> void:
	_tempo_servo_restante = 0.0
	if _servo_player != null and _servo_player.playing:
		_servo_player.stop()


## Retorna se o servo está ativo no momento.
func esta_tocando_servo() -> bool:
	return _servo_player != null and _servo_player.playing


## Bip tático cristalino de 950Hz com decaimento rápido (travamento magnético da mira).
func tocar_snap() -> void:
	_tocar_stream(_stream_snap, -2.0)


## Som mecânico de parafusadeira pneumática aeroespacial:
## dente-de-serra modulado em alta rotação (drrr!) seguido por impacto de torque seco (CLANK!).
func tocar_parafusadeira() -> void:
	_tocar_stream(_stream_parafusadeira, 0.0)


## Pulso duplo Master Warning da NASA (880Hz / 700Hz intermitente).
func tocar_alarme() -> void:
	_tocar_stream(_stream_alarme, -2.0)


## Alias para manter total conformidade com a especificação da missão.
func tocar_alarme_emergencia() -> void:
	tocar_alarme()


## Acorde triunfal harmônico de pressurização estanque do abrigo
## (C5 523Hz -> E5 659Hz -> G5 784Hz -> C6 1046Hz) com decaimento exponencial.
func tocar_sucesso() -> void:
	_tocar_stream(_stream_sucesso, -1.0)


## Zumbido áspero de tentativa de fixação desalinhada (130Hz -> 65Hz descendente).
func tocar_erro() -> void:
	_tocar_stream(_stream_erro, -2.0)


## Interrompe todos os sons atualmente em reprodução (servo e pool).
func parar_tudo() -> void:
	parar_servo()
	for p in _players:
		if p != null and p.playing:
			p.stop()


# ==============================================================================
# GESTÃO DO POOL POLIFÔNICO
# ==============================================================================

func _tocar_stream(stream: AudioStreamWAV, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	if stream == null or _players.is_empty():
		return null

	# Procura o primeiro player desocupado
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale
			p.play()
			return p

	# Se todos os 6 estiverem ocupados, usa round-robin substituindo a voz mais antiga
	var player_antigo := _players[_indice_pool]
	_indice_pool = (_indice_pool + 1) % _players.size()
	player_antigo.stop()
	player_antigo.stream = stream
	player_antigo.volume_db = volume_db
	player_antigo.pitch_scale = pitch_scale
	player_antigo.play()
	return player_antigo


# ==============================================================================
# SÍNTESE PROCEDURAL MATEMÁTICA (EXECUÇÃO ÚNICA EM CACHE ESTÁTICO)
# ==============================================================================

## Garante a geração de todos os streams na memória caso ainda não existam.
static func garantir_streams() -> void:
	if _streams_gerados:
		return

	_stream_servo = _gerar_onda_servo()
	_stream_snap = _gerar_onda_snap()
	_stream_parafusadeira = _gerar_onda_parafusadeira()
	_stream_alarme = _gerar_onda_alarme()
	_stream_sucesso = _gerar_onda_sucesso()
	_stream_erro = _gerar_onda_erro()

	_streams_gerados = true


## Converte amplitude normalizada (-1.0 a 1.0) para PCM 16-bit com sinal (-32768 a 32767).
static func _s16(valor: float) -> int:
	return clampi(int(round(valor * 32760.0)), -32768, 32767)


## 1. Servomotor hidráulico: 80Hz com harmônicos e modulação contínua seamless.
## Buffer com número exato de ciclos para loop contínuo sem cliques (0.2s = 4410 amostras).
static func _gerar_onda_servo() -> AudioStreamWAV:
	var total_amostras: int = 4410 # 0.2 segundos a 22050 Hz (16 ciclos exatos de 80Hz)
	var buffer := PackedByteArray()
	buffer.resize(total_amostras * 2)

	for i in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		# Portadora de 80 Hz + harmônicos de engrenagem
		var portadora: float = sin(TAU * 80.0 * t)
		var harm1: float = 0.28 * sin(TAU * 160.0 * t)
		var harm2: float = 0.12 * sin(TAU * 240.0 * t)
		# Textura de fluido hidráulico (múltiplos exatos de 5Hz para loop periódico perfeito)
		var textura: float = (
			0.05 * sin(TAU * 400.0 * t) +
			0.03 * sin(TAU * 650.0 * t) +
			0.02 * sin(TAU * 950.0 * t)
		)
		# Modulação de fluxo (15 Hz = 3 ciclos exatos em 0.2s)
		var lfo: float = 0.82 + 0.18 * sin(TAU * 15.0 * t)

		var sinal: float = (portadora + harm1 + harm2 + textura) * lfo * 0.75
		buffer.encode_s16(i * 2, _s16(sinal))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA_AMOSTRAGEM
	wav.stereo = false
	wav.data = buffer
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_amostras
	return wav


## 2. Bip tático de 950Hz com decaimento rápido (pip de travamento magnético).
static func _gerar_onda_snap() -> AudioStreamWAV:
	var duracao: float = 0.075 # 75 ms
	var total_amostras: int = int(duracao * TAXA_AMOSTRAGEM)
	var buffer := PackedByteArray()
	buffer.resize(total_amostras * 2)

	var fase: float = 0.0
	for i in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		
		# Micro-chirp nos primeiros 6ms para simular travamento mecânico-magnético tático
		var freq: float = 950.0
		if t < 0.006:
			freq = lerpf(1250.0, 950.0, t / 0.006)
		
		fase += (TAU * freq) / float(TAXA_AMOSTRAGEM)

		# Harmônicos cristalinos (brilho e definição tática)
		var s: float = sin(fase) + 0.28 * sin(fase * 2.0) + 0.12 * sin(fase * 3.0)

		# Envelope: ataque em 1.5ms para não ter clique DC, seguido de decaimento exponencial
		var env: float = 0.0
		if t < 0.0015:
			env = t / 0.0015
		else:
			env = exp(-(t - 0.0015) * 55.0)

		var sinal: float = s * env * 0.82
		buffer.encode_s16(i * 2, _s16(sinal))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA_AMOSTRAGEM
	wav.stereo = false
	wav.data = buffer
	return wav


## 3. Parafusadeira pneumática aeroespacial:
## dente-de-serra modulado em alta rotação (drrr!) seguido por impacto seco de torque (CLANK!).
static func _gerar_onda_parafusadeira() -> AudioStreamWAV:
	var duracao: float = 0.58 # 580 ms
	var total_amostras: int = int(duracao * TAXA_AMOSTRAGEM)
	var buffer := PackedByteArray()
	buffer.resize(total_amostras * 2)

	var corte_impacto: float = 0.35 # Momento do impacto em segundos
	var fase_motor: float = 0.0

	for i in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var sinal: float = 0.0

		if t < corte_impacto:
			# FASE 1: Rotação pneumática de alta pressão (drrr!)
			# Aceleração de rotação de 230Hz para 360Hz
			var prog: float = t / corte_impacto
			var freq_rotacao: float = lerpf(230.0, 360.0, prog)
			fase_motor += (TAU * freq_rotacao) / float(TAXA_AMOSTRAGEM)

			# Onda dente-de-serra modulada
			var saw: float = (fmod(fase_motor / TAU, 1.0) * 2.0 - 1.0)
			# Adiciona harmônico e corpo senoidal
			var corpo: float = sin(fase_motor) * 0.4

			# Batimento pneumático rápido (38 Hz = martelamento de alta pressão)
			var batimento: float = pow(abs(sin(TAU * 38.0 * t)), 1.8) * 0.65 + 0.35

			# Ruído de ar pressurizado (pseudo-ruído determinístico)
			var ar: float = sin(float(i * 12345 + 6789)) * 0.16

			# Envelope do motor
			var env_motor: float = 1.0
			if t < 0.02:
				env_motor = t / 0.02
			elif t > (corte_impacto - 0.03):
				env_motor = (corte_impacto - t) / 0.03

			sinal = ((saw * 0.5 + corpo + ar) * batimento) * env_motor * 0.8
		else:
			# FASE 2: Impacto seco de aperto de torque (CLANK!)
			var ti: float = t - corte_impacto

			# Pulso percussivo transitório (primeiros 15ms)
			var transient_noise: float = sin(float(i * 54321 + 9876)) * exp(-ti * 220.0)

			# Ressonâncias de liga metálica de titânio (frequências inarmônicas)
			var m1: float = sin(TAU * 480.0 * ti) * exp(-ti * 20.0)
			var m2: float = sin(TAU * 860.0 * ti) * exp(-ti * 30.0) * 0.75
			var m3: float = sin(TAU * 1480.0 * ti) * exp(-ti * 48.0) * 0.5
			var m4: float = sin(TAU * 2420.0 * ti) * exp(-ti * 75.0) * 0.3

			var metal: float = m1 + m2 + m3 + m4
			sinal = (transient_noise * 0.55 + metal * 0.7) * 0.85

		buffer.encode_s16(i * 2, _s16(sinal))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA_AMOSTRAGEM
	wav.stereo = false
	wav.data = buffer
	return wav


## 4. Pulso duplo Master Warning da NASA (880Hz / 700Hz intermitente).
static func _gerar_onda_alarme() -> AudioStreamWAV:
	var duracao: float = 0.66
	var total_amostras: int = int(duracao * TAXA_AMOSTRAGEM)
	var buffer := PackedByteArray()
	buffer.resize(total_amostras * 2)

	# Cronograma do Master Warning (dois pares de bips duplos):
	# [880Hz: 0.00-0.12] [pausa: 0.12-0.15] [700Hz: 0.15-0.29] [pausa: 0.29-0.35]
	# [880Hz: 0.35-0.47] [pausa: 0.47-0.50] [700Hz: 0.50-0.64]
	for i in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var freq: float = 0.0
		var ativo: bool = false
		var t_inicio_pulso: float = 0.0
		var dur_pulso: float = 0.0

		if t >= 0.00 and t < 0.12:
			freq = 880.0
			ativo = true
			t_inicio_pulso = 0.00
			dur_pulso = 0.12
		elif t >= 0.15 and t < 0.29:
			freq = 700.0
			ativo = true
			t_inicio_pulso = 0.15
			dur_pulso = 0.14
		elif t >= 0.35 and t < 0.47:
			freq = 880.0
			ativo = true
			t_inicio_pulso = 0.35
			dur_pulso = 0.12
		elif t >= 0.50 and t < 0.64:
			freq = 700.0
			ativo = true
			t_inicio_pulso = 0.50
			dur_pulso = 0.14

		var sinal: float = 0.0
		if ativo:
			var tp: float = t - t_inicio_pulso
			# Envelope anti-clique de 3ms no início e fim de cada pulso
			var env: float = 1.0
			var ramp: float = 0.003
			if tp < ramp:
				env = tp / ramp
			elif tp > (dur_pulso - ramp):
				env = (dur_pulso - tp) / ramp

			# Tom puro com 14% de 3º harmônico (característico dos alertas espaciais)
			var tom: float = sin(TAU * freq * t) + 0.14 * sin(TAU * freq * 3.0 * t)
			sinal = tom * env * 0.78

		buffer.encode_s16(i * 2, _s16(sinal))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA_AMOSTRAGEM
	wav.stereo = false
	wav.data = buffer
	return wav


## 5. Acorde triunfal harmônico de pressurização estanque do abrigo
## (C5 523Hz -> E5 659Hz -> G5 784Hz -> C6 1046Hz) com decaimento exponencial.
static func _gerar_onda_sucesso() -> AudioStreamWAV:
	var duracao: float = 1.35
	var total_amostras: int = int(duracao * TAXA_AMOSTRAGEM)
	var buffer := PackedByteArray()
	buffer.resize(total_amostras * 2)

	# Frequências musicais exatas
	var freq_c5: float = 523.25
	var freq_e5: float = 659.25
	var freq_g5: float = 783.99
	var freq_c6: float = 1046.50

	for i in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)

		# 1. Hiss aerodinâmico suave de equalização de pressão da cabine
		var hiss_env: float = 0.0
		if t < 0.45:
			hiss_env = pow(1.0 - (t / 0.45), 2.0)
		var hiss: float = sin(float(i * 31415 + 9265)) * hiss_env * 0.14

		# 2. Sub-grave de ancoragem e pressurização estanque (65.4 Hz = C2)
		var sub_env: float = exp(-t * 3.2)
		var sub: float = sin(TAU * 65.4 * t) * sub_env * 0.28

		# 3. Arpeggio harmônico triunfal
		var acorde: float = 0.0

		# C5 entra em t = 0.00
		if t >= 0.00:
			var t1: float = t - 0.00
			var env1: float = exp(-t1 * 2.2) * (t1 / 0.01 if t1 < 0.01 else 1.0)
			acorde += (sin(TAU * freq_c5 * t) + 0.25 * sin(TAU * freq_c5 * 2.0 * t)) * env1 * 0.35

		# E5 entra em t = 0.08
		if t >= 0.08:
			var t2: float = t - 0.08
			var env2: float = exp(-t2 * 2.2) * (t2 / 0.01 if t2 < 0.01 else 1.0)
			acorde += (sin(TAU * freq_e5 * t) + 0.22 * sin(TAU * freq_e5 * 2.0 * t)) * env2 * 0.35

		# G5 entra em t = 0.16
		if t >= 0.16:
			var t3: float = t - 0.16
			var env3: float = exp(-t3 * 2.0) * (t3 / 0.01 if t3 < 0.01 else 1.0)
			acorde += (sin(TAU * freq_g5 * t) + 0.18 * sin(TAU * freq_g5 * 2.0 * t)) * env3 * 0.38

		# C6 entra em t = 0.24 (topo triunfal cristalino)
		if t >= 0.24:
			var t4: float = t - 0.24
			var env4: float = exp(-t4 * 1.8) * (t4 / 0.01 if t4 < 0.01 else 1.0)
			acorde += (sin(TAU * freq_c6 * t) + 0.15 * sin(TAU * freq_c6 * 2.0 * t)) * env4 * 0.42

		var sinal: float = (acorde + hiss + sub) * 0.75
		buffer.encode_s16(i * 2, _s16(sinal))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA_AMOSTRAGEM
	wav.stereo = false
	wav.data = buffer
	return wav


## 6. Zumbido áspero de tentativa de fixação desalinhada (130Hz -> 65Hz descendente).
static func _gerar_onda_erro() -> AudioStreamWAV:
	var duracao: float = 0.34
	var total_amostras: int = int(duracao * TAXA_AMOSTRAGEM)
	var buffer := PackedByteArray()
	buffer.resize(total_amostras * 2)

	for i in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)

		# Variação de pitch descendente (130Hz -> 65Hz)
		# Integral analítica da frequência: fase = TAU * (130*t - (65 / (2*duracao)) * t^2)
		var fase: float = TAU * (130.0 * t - (65.0 / (2.0 * duracao)) * (t * t))

		# Síntese dente-de-serra + harmônicos ímpares ásperos (buzz elétrico e atrito mecânico)
		var saw: float = (fmod(fase / TAU, 1.0) * 2.0 - 1.0)
		var harm: float = sin(fase) + 0.5 * sin(fase * 3.0) + 0.3 * sin(fase * 5.0)

		# Modulação áspera de fricção (45 Hz)
		var atrito: float = 0.78 + 0.22 * sin(TAU * 45.0 * t)

		# Envelope: ataque rápido e fade-out suave nos últimos 50ms
		var env: float = 1.0
		if t < 0.005:
			env = t / 0.005
		elif t > (duracao - 0.05):
			env = (duracao - t) / 0.05

		var sinal: float = ((harm * 0.55 + saw * 0.45) * atrito) * env * 0.8
		buffer.encode_s16(i * 2, _s16(sinal))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA_AMOSTRAGEM
	wav.stereo = false
	wav.data = buffer
	return wav
