class_name AlarmeSolar
extends Node2D
## Sistema leve de Alarme Solar e Luzes de Emergência para Artemis Outpost.
##
## Projeta um efeito de overlay pulsante sutil (luz âmbar ou vermelha de emergência)
## com opacidade variando entre 0.05 e 0.20 via seno temporal, e gera bipes/tons
## suaves procedurais sintetizados de baixa frequência (via AudioStreamWAV)
## a cada 4 a 6 segundos para proporcionar tensão cinematográfica durante eventos de clima espacial.

signal alarme_ativado(tipo: String)
signal alarme_desativado()
signal pulso_sonoro_emitido()

const LARGURA_TELA: float = 320.0
const ALTURA_TELA: float = 180.0

# Cores de emergência da paleta da base lunar Artemis
const COR_AMBAR := Color(0.92, 0.55, 0.18)      # Alerta CME / Pré-impacto (Dia 3)
const COR_VERMELHO := Color(0.85, 0.22, 0.18)   # Impacto Solar Crítico (Dia 4)
const COR_PADRAO := Color(0.85, 0.22, 0.18)

# Limites estritos de opacidade sutil (sem atrapalhar a visão ou jogabilidade)
const OPACIDADE_MIN: float = 0.05
const OPACIDADE_MAX: float = 0.20

# Velocidades de pulsação suave (radianos por segundo)
const VELOCIDADE_PULSO_CME: float = 2.4
const VELOCIDADE_PULSO_IMPACTO: float = 3.4

# Intervalos de repetição sonora (entre 4 e 6 segundos)
const INTERVALO_BIP_CME: float = 5.5
const INTERVALO_BIP_IMPACTO: float = 4.4

# Parâmetros de síntese de áudio procedural (baixa frequência)
const TAXA_AMOSTRAGEM: int = 22050

@export var sincronizar_com_missao: bool = true
@export var volume_alarme_db: float = -14.0

var _ativo: bool = false
var _tipo_atual: String = ""
var _cor_atual: Color = COR_PADRAO
var _velocidade_pulso: float = VELOCIDADE_PULSO_IMPACTO
var _intervalo_bip: float = INTERVALO_BIP_IMPACTO
var _tempo_acumulado: float = 0.0
var _opacidade_atual: float = 0.0
var _tempo_para_proximo_bip: float = 0.0
var _controle_manual: bool = false

# Nós visuais e de áudio
var _camada_canvas: CanvasLayer = null
var _overlay_rect: ColorRect = null
var _player_audio: AudioStreamPlayer = null

# Amostras de áudio procedural sintetizadas em tempo de execução
var _stream_cme: AudioStreamWAV = null
var _stream_impacto: AudioStreamWAV = null
var _stream_ativo: AudioStreamWAV = null


func _ready() -> void:
	_configurar_audio()
	_configurar_overlay_visual()
	
	if sincronizar_com_missao and not _controle_manual:
		_verificar_missao()


func _process(delta: float) -> void:
	if sincronizar_com_missao and not _controle_manual:
		_verificar_missao()
	
	if _ativo:
		_tempo_acumulado += delta
		
		# Pulsação suave via seno temporal normalizado entre 0.0 e 1.0
		var fator_seno: float = (sin(_tempo_acumulado * _velocidade_pulso) + 1.0) * 0.5
		_opacidade_atual = lerp(OPACIDADE_MIN, OPACIDADE_MAX, fator_seno)
		
		if _overlay_rect:
			_overlay_rect.color = Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, _opacidade_atual)
			_overlay_rect.visible = true
		
		# Cadência dos bipes procedurais
		_tempo_para_proximo_bip -= delta
		if _tempo_para_proximo_bip <= 0.0:
			_tocar_bip()
			_tempo_para_proximo_bip = _intervalo_bip + randf_range(-0.3, 0.4)
	else:
		# Esmaecimento suave ao desativar
		if _opacidade_atual > 0.0:
			_opacidade_atual = maxf(0.0, _opacidade_atual - delta * 0.4)
			if _overlay_rect:
				_overlay_rect.color = Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, _opacidade_atual)
				if _opacidade_atual <= 0.0:
					_overlay_rect.visible = false


## Ativa o alarme solar e o overlay com base no tipo ("cme", "impacto" ou automático)
func ativar_alarme(tipo: String = "") -> void:
	_controle_manual = true
	_aplicar_ativacao(tipo)


## Desativa o alarme e inicia o fade out suave do overlay
func desativar_alarme() -> void:
	_controle_manual = true
	_aplicar_desativacao()


## Retorna se o alarme está atualmente ativo
func esta_ativo() -> bool:
	return _ativo


## Retorna o tipo de emergência em execução ("cme" ou "impacto")
func obter_tipo() -> String:
	return _tipo_atual


## Retorna a cor atualmente configurada para as luzes de emergência
func obter_cor() -> Color:
	return _cor_atual


## Retorna o valor de opacidade atual do overlay
func obter_opacidade() -> float:
	return _opacidade_atual


## Permite reabilitar a sincronização automática com o clima da Missão
func resetar_controle_manual() -> void:
	_controle_manual = false


## Ajusta o volume do player de áudio do alarme em decibéis
func definir_volume(db: float) -> void:
	volume_alarme_db = db
	if _player_audio:
		_player_audio.volume_db = db


func _aplicar_ativacao(tipo: String) -> void:
	var t_low: String = tipo.strip_edges().to_lower()
	
	if t_low.is_empty() or t_low == "auto":
		if has_node("/root/Missao"):
			var m: Node = get_node("/root/Missao")
			if m.has_method("obter_status_clima"):
				var st: Dictionary = m.obter_status_clima()
				var fase: String = str(st.get("fase", ""))
				if fase == "deteccao_cme":
					t_low = "cme"
				else:
					t_low = "impacto"
		else:
			t_low = "impacto"
	
	if t_low in ["cme", "alerta_cme", "alerta", "ambar", "laranja", "sol3", "dia3"]:
		_tipo_atual = "cme"
		_cor_atual = COR_AMBAR
		_velocidade_pulso = VELOCIDADE_PULSO_CME
		_intervalo_bip = INTERVALO_BIP_CME
		_stream_ativo = _stream_cme
	else:
		_tipo_atual = "impacto"
		_cor_atual = COR_VERMELHO
		_velocidade_pulso = VELOCIDADE_PULSO_IMPACTO
		_intervalo_bip = INTERVALO_BIP_IMPACTO
		_stream_ativo = _stream_impacto
	
	_ativo = true
	if _overlay_rect:
		_overlay_rect.visible = true
	
	# Dispara o primeiro bipe cinematográfico suave pouco após ativar
	_tempo_para_proximo_bip = 0.5
	alarme_ativado.emit(_tipo_atual)


func _aplicar_desativacao() -> void:
	_ativo = false
	if _player_audio and _player_audio.playing:
		_player_audio.stop()
	alarme_desativado.emit()


func _verificar_missao() -> void:
	if not has_node("/root/Missao"):
		return
	
	var m: Node = get_node("/root/Missao")
	if not m.has_method("obter_status_clima"):
		return
	
	var st: Dictionary = m.obter_status_clima()
	var fase: String = str(st.get("fase", ""))
	
	if fase == "impacto":
		if not _ativo or _tipo_atual != "impacto":
			_aplicar_ativacao("impacto")
	elif fase == "deteccao_cme":
		if not _ativo or _tipo_atual != "cme":
			_aplicar_ativacao("cme")
	else:
		if _ativo:
			_aplicar_desativacao()


func _configurar_overlay_visual() -> void:
	_overlay_rect = ColorRect.new()
	_overlay_rect.name = "OverlayLuzEmergencia"
	_overlay_rect.size = Vector2(LARGURA_TELA, ALTURA_TELA)
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.visible = false
	_overlay_rect.color = Color(_cor_atual.r, _cor_atual.g, _cor_atual.b, 0.0)
	
	# Se o nó pai já for um CanvasLayer (ex: camada_ui), anexa direto
	if get_parent() is CanvasLayer:
		add_child(_overlay_rect)
	else:
		# Quando instanciado direto em Node2D (ex: mapa.gd com câmera móvel),
		# cria CanvasLayer dedicado para manter o overlay travado em tela cheia 320x180
		_camada_canvas = CanvasLayer.new()
		_camada_canvas.name = "CamadaAlarmeSolar"
		_camada_canvas.layer = 1
		add_child(_camada_canvas)
		_camada_canvas.add_child(_overlay_rect)


func _configurar_audio() -> void:
	_stream_cme = _sintetizar_som_cme()
	_stream_impacto = _sintetizar_som_impacto()
	_stream_ativo = _stream_impacto
	
	_player_audio = AudioStreamPlayer.new()
	_player_audio.name = "PlayerAlarmeSolar"
	_player_audio.bus = "Master"
	_player_audio.volume_db = volume_alarme_db
	add_child(_player_audio)


func _tocar_bip() -> void:
	if not _ativo or _stream_ativo == null or _player_audio == null:
		return
	if not _player_audio.playing:
		_player_audio.stream = _stream_ativo
		_player_audio.play()
		pulso_sonoro_emitido.emit()


func _sintetizar_som_cme() -> AudioStreamWAV:
	# Tom suave senoidal em 240 Hz (Dó central grave / Sol) com fade sem cliques (0.55s)
	return _gerar_amostras_pcm(240.0, 0.55, false)


func _sintetizar_som_impacto() -> AudioStreamWAV:
	# Tom duplo senoidal descendente de emergência (260 Hz -> 200 Hz, 0.70s)
	return _gerar_amostras_pcm(260.0, 0.70, true)


func _gerar_amostras_pcm(frequencia_base: float, duracao: float, duplo_tom: bool) -> AudioStreamWAV:
	var total_amostras: int = int(duracao * float(TAXA_AMOSTRAGEM))
	var dados := PackedByteArray()
	dados.resize(total_amostras * 2)
	
	for i in range(total_amostras):
		var t: float = float(i) / float(TAXA_AMOSTRAGEM)
		var envelope: float = 0.0
		var seno: float = 0.0
		
		if duplo_tom:
			var t1: float = 0.28
			var t_silencio: float = 0.38
			if t < t1:
				envelope = sin(PI * (t / t1))
				seno = sin(2.0 * PI * frequencia_base * t)
			elif t < t_silencio:
				envelope = 0.0
				seno = 0.0
			else:
				var t2_dur: float = duracao - t_silencio
				var t_rel: float = t - t_silencio
				envelope = sin(PI * (t_rel / t2_dur))
				seno = sin(2.0 * PI * (frequencia_base * 0.77) * t_rel)
		else:
			envelope = sin(PI * (float(i) / float(total_amostras)))
			seno = sin(2.0 * PI * frequencia_base * t)
		
		envelope = clampf(envelope, 0.0, 1.0)
		var amostra: float = seno * envelope * 0.40
		var valor_16bit: int = clampi(int(round(amostra * 32767.0)), -32768, 32767)
		if valor_16bit < 0:
			valor_16bit += 65536
		dados[i * 2] = valor_16bit & 0xFF
		dados[i * 2 + 1] = (valor_16bit >> 8) & 0xFF
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA_AMOSTRAGEM
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = dados
	return wav
