class_name IluminacaoEmergencia
extends CanvasLayer
## Módulo de Iluminação Reativa e Efeitos Ambientais de Mundo Vivo para Artemis Adventure.
##
## Controla dinamicamente a iluminação global da base lunar em pixel art 16-bit nativo (320x180)
## em resposta aos eventos elétricos, tempestades de radiação/surto solar e blecautes parciais.
##
## Estados suportados:
##   - NORMAL: Iluminação neutra/branca padrão da base lunar com micro-instabilidade natural.
##   - SOLAR_SURGE: Efeito estroboscópico de surto elétrico (60Hz/10Hz) seguido de pulso de alerta âmbar/vermelho.
##   - PARTIAL_BLACKOUT: Queda para 60% de escuridão com iluminação de emergência vermelha profunda em meia-fase.
##   - RECUPERACAO: Transição suave de 1.8s onde os circuitos principais reacendem progressivamente com clacks de relé.
##
## Modulação gráfica em Godot 4:
##   - CanvasLayer com camada de sobreposição multiplicativa (BLEND_MODE_MUL) e aditiva (BLEND_MODE_ADD).
##   - Permite vincular opcionalmente um nó CanvasModulate existente do mapa.
##   - Preserva 100% das texturas e sprites de pixel art originais sem lavá-los ou alterá-los.

# ------------------------------------------------------------------------------
# SINAIS
# ------------------------------------------------------------------------------
signal estado_mudou(novo_estado: Estado, estado_anterior: Estado)
signal surto_solar_iniciado(intensidade: float)
signal blecaute_parcial_iniciado
signal recuperacao_iniciada
signal recuperacao_concluida
signal pulso_alerta(fase: float, cor: Color)
signal rele_acionado(estagio: int, nome_circuito: String)

# ------------------------------------------------------------------------------
# ENUMERADORES E CONSTANTES
# ------------------------------------------------------------------------------
enum Estado {
	NORMAL,
	SOLAR_SURGE,
	PARTIAL_BLACKOUT,
	RECUPERACAO
}

# Paleta industrial de iluminação da base lunar (Apollo/Artemis 16-bit)
const COR_NORMAL := Color(1.0, 1.0, 1.0, 1.0)
const COR_NORMAL_FRIA := Color(0.96, 0.98, 1.0, 1.0)
const COR_SURTO_ARCO := Color(0.88, 0.96, 1.0, 1.0)          # Faísca/arco elétrico de alta tensão
const COR_SURTO_AMBAR := Color(1.0, 0.65, 0.18, 1.0)         # Alerta primário de surto solar
const COR_SURTO_VERMELHO := Color(0.94, 0.22, 0.16, 1.0)     # Alerta crítico de sobretensão
const COR_BLECAUTE_BASE := Color(0.38, 0.08, 0.08, 1.0)      # Vermelho profundo de emergência (60% escuridão)
const COR_BLECAUTE_PULSO := Color(0.48, 0.14, 0.12, 1.0)     # Meia-fase de baterias auxiliares

# Tempos e durações regulamentares
const DURACAO_RECUPERACAO_PADRAO: float = 1.8                 # 1.8 segundos obrigatórios de fade-in
const LARGURA_NATIVA: float = 320.0
const ALTURA_NATIVA: float = 180.0

# ------------------------------------------------------------------------------
# PARÂMETROS EXPORTADOS
# ------------------------------------------------------------------------------
@export_group("Configurações Gerais")
@export var habilitado: bool = true
@export var camada_ordem: int = 8                             # Acima do mapa/mundo, abaixo de HUD/menus
@export var micro_ruido_ativo: bool = true                    # Zumbido procedural e micro-ruído elétrico
@export var usar_blend_multiply: bool = true                  # Usa BLEND_MODE_MUL para modulação limpa
@export var canvas_modulate_alvo: CanvasModulate = null        # Nó CanvasModulate externo opcional

@export_group("Surto Solar (Solar Surge)")
@export var freq_strobe_alta: float = 60.0                    # Frequência de surto 60Hz
@export var freq_strobe_baixa: float = 10.0                   # Frequência estroboscópica 10Hz
@export var freq_pulso_alerta: float = 2.0                    # Oscilação senoidal do alerta (2Hz)
@export var duracao_estroboscopio_inicial: float = 1.5        # Segundos de flicker intenso antes do alerta estável

@export_group("Blecaute Parcial (Partial Blackout)")
@export_range(0.0, 1.0) var fator_escuridao: float = 0.60    # 60% de escuridão geral (nível 40% de luz)
@export var freq_meia_fase: float = 0.85                      # Oscilação da meia-fase de bateria auxiliar (0.85Hz)
@export var instabilidade_bateria: float = 0.08               # Micro-quedas de tensão aleatórias

@export_group("Recuperação")
@export var duracao_recuperacao: float = DURACAO_RECUPERACAO_PADRAO

# ------------------------------------------------------------------------------
# VARIÁVEIS INTERNAS DE ESTADO
# ------------------------------------------------------------------------------
var estado_atual: Estado = Estado.NORMAL
var estado_anterior: Estado = Estado.NORMAL

var tempo_total: float = 0.0
var tempo_estado: float = 0.0
var intensidade_surto: float = 1.0

# Cores calculadas no quadro atual
var cor_multiplicativa: Color = COR_NORMAL
var cor_aditiva: Color = Color(0.0, 0.0, 0.0, 0.0)
var cor_inicio_recuperacao: Color = COR_BLECAUTE_BASE

# Estágios do rearme progressivo dos relés na recuperação
var rele_estagio_1_disparado: bool = false
var rele_estagio_2_disparado: bool = false
var rele_estagio_3_disparado: bool = false

# Nós de renderização
var _rect_multiplicativo: ColorRect = null
var _rect_aditivo: ColorRect = null
var _rect_compat_escuro: ColorRect = null
var _rect_compat_cor: ColorRect = null


# ------------------------------------------------------------------------------
# CICLO DE VIDA DO GODOT
# ------------------------------------------------------------------------------
func _ready() -> void:
	layer = camada_ordem
	_construir_camadas_visuais()
	resetar_normal()


func _process(delta: float) -> void:
	if not habilitado:
		_aplicar_cores(COR_NORMAL, Color(0.0, 0.0, 0.0, 0.0))
		return

	tempo_total += delta
	tempo_estado += delta

	match estado_atual:
		Estado.NORMAL:
			_processar_normal(delta)
		Estado.SOLAR_SURGE:
			_processar_surto_solar(delta)
		Estado.PARTIAL_BLACKOUT:
			_processar_blecaute_parcial(delta)
		Estado.RECUPERACAO:
			_processar_recuperacao(delta)

	_aplicar_cores(cor_multiplicativa, cor_aditiva)


# ------------------------------------------------------------------------------
# MÉTODOS PÚBLICOS OBRIGATÓRIOS
# ------------------------------------------------------------------------------

## Ativa o efeito de Surto Solar com flicker estroboscópico 60Hz/10Hz e alerta pulsante.
func ativar_surto_solar(intensidade: float = 1.0) -> void:
	intensidade_surto = clampf(intensidade, 0.1, 3.0)
	_transicionar_para(Estado.SOLAR_SURGE)
	surto_solar_iniciado.emit(intensidade_surto)


## Ativa a queda acentuada de 60% de escuridão com luz vermelha profunda de meia-fase.
func ativar_blecaute_parcial() -> void:
	_transicionar_para(Estado.PARTIAL_BLACKOUT)
	blecaute_parcial_iniciado.emit()


## Inicia a restauração gradual e suave dos circuitos (fade-in progressivo de 1.8 segundos).
func iniciar_recuperacao() -> void:
	cor_inicio_recuperacao = cor_multiplicativa
	rele_estagio_1_disparado = false
	rele_estagio_2_disparado = false
	rele_estagio_3_disparado = false
	_transicionar_para(Estado.RECUPERACAO)
	recuperacao_iniciada.emit()


## Retorna imediatamente à iluminação normal estável da base lunar.
func resetar_normal() -> void:
	tempo_estado = 0.0
	intensidade_surto = 1.0
	rele_estagio_1_disparado = false
	rele_estagio_2_disparado = false
	rele_estagio_3_disparado = false
	_transicionar_para(Estado.NORMAL)
	cor_multiplicativa = COR_NORMAL
	cor_aditiva = Color(0.0, 0.0, 0.0, 0.0)
	_aplicar_cores(cor_multiplicativa, cor_aditiva)


# ------------------------------------------------------------------------------
# MÉTODOS AUXILIARES E INTEGRAÇÃO
# ------------------------------------------------------------------------------

func obter_estado() -> Estado:
	return estado_atual


func obter_estado_nome() -> String:
	match estado_atual:
		Estado.NORMAL:
			return "NORMAL"
		Estado.SOLAR_SURGE:
			return "SOLAR_SURGE"
		Estado.PARTIAL_BLACKOUT:
			return "PARTIAL_BLACKOUT"
		Estado.RECUPERACAO:
			return "RECUPERACAO"
		_:
			return "DESCONHECIDO"


func obter_cor_modulacao() -> Color:
	return cor_multiplicativa


func obter_nivel_luminosidade() -> float:
	return (cor_multiplicativa.r * 0.299 + cor_multiplicativa.g * 0.587 + cor_multiplicativa.b * 0.114)


func definir_habilitado(ativo: bool) -> void:
	habilitado = ativo
	if not habilitado:
		_aplicar_cores(COR_NORMAL, Color(0.0, 0.0, 0.0, 0.0))


func vincular_canvas_modulate(no: CanvasModulate) -> void:
	canvas_modulate_alvo = no


# ------------------------------------------------------------------------------
# PROCESSAMENTO DOS ESTADOS (MATEMÁTICA PROCEDURAL NATIVA 16-BIT)
# ------------------------------------------------------------------------------

## Estado NORMAL: Iluminação limpa da base com micro-hum e variação orgânica imperceptível
func _processar_normal(_delta: float) -> void:
	if micro_ruido_ativo:
		# Zumbido elétrico suave de 60Hz (~0.3% amplitude) + micro-deriva térmica de 0.5Hz
		var zumbido: float = sin(tempo_total * 60.0 * TAU) * 0.003
		var deriva: float = sin(tempo_total * 0.5 * TAU) * 0.004
		var ruido: float = (_ruido_suave(tempo_total * 12.0) - 0.5) * 0.005
		var fator: float = clampf(1.0 + zumbido + deriva + ruido, 0.985, 1.0)
		cor_multiplicativa = Color(COR_NORMAL.r * fator, COR_NORMAL.g * fator, COR_NORMAL.b * fator, 1.0)
	else:
		cor_multiplicativa = COR_NORMAL

	cor_aditiva = Color(0.0, 0.0, 0.0, 0.0)


## Estado SOLAR_SURGE: Arco elétrico estroboscópico de surto (60Hz e 10Hz) seguido de pulso de alerta
func _processar_surto_solar(_delta: float) -> void:
	var s60: float = sin(tempo_total * freq_strobe_alta * TAU)
	var s10: float = sin(tempo_total * freq_strobe_baixa * TAU)
	var jitter_rapido: float = _ruido_suave(tempo_total * 35.0)

	if tempo_estado < duracao_estroboscopio_inicial:
		# Fase 1: Surto inicial violento com arco de alta tensão e instabilidade severa de 60Hz/10Hz
		var corte_luz: float = (s10 * 0.5 + 0.5) * (s60 * 0.4 + 0.6)
		corte_luz = clampf(corte_luz + (jitter_rapido - 0.5) * 0.25, 0.15, 1.0)

		# Interpolação de alerta âmbar para arco elétrico
		var cor_base_surto: Color = COR_SURTO_AMBAR.lerp(COR_SURTO_VERMELHO, (s10 * 0.5 + 0.5))
		cor_multiplicativa = cor_base_surto * corte_luz

		# Arco elétrico e faísca aditiva quando o pico de 60Hz atinge o limiar de tensão
		var chance_arco: float = maxf(0.0, s60) * maxf(0.0, s10) * intensidade_surto
		if chance_arco > 0.45:
			var brilho_arco: float = (chance_arco - 0.45) * 1.8 * intensidade_surto
			cor_aditiva = Color(COR_SURTO_ARCO.r, COR_SURTO_ARCO.g, COR_SURTO_ARCO.b, 1.0) * clampf(brilho_arco, 0.0, 0.7)
		else:
			cor_aditiva = Color(0.0, 0.0, 0.0, 0.0)
	else:
		# Fase 2: Alerta industrial contínuo com pulso senoidal suave e ruído de gerador
		var pulso_seno: float = (sin(tempo_estado * freq_pulso_alerta * TAU) + 1.0) * 0.5
		var micro_instabilidade: float = (_ruido_suave(tempo_total * 16.0) - 0.5) * 0.14 * intensidade_surto
		var onda_final: float = clampf(pulso_seno + micro_instabilidade, 0.0, 1.0)

		# Transição pulsante entre âmbar de alerta e vermelho de perigo
		var cor_alerta: Color = COR_SURTO_AMBAR.lerp(COR_SURTO_VERMELHO, onda_final)
		var fator_brilho: float = lerpf(0.55, 1.0, onda_final)
		cor_multiplicativa = cor_alerta * fator_brilho

		# Leve glow aditivo pulsante no pico da sirene visual
		var glow: float = maxf(0.0, onda_final - 0.5) * 0.35 * intensidade_surto
		cor_aditiva = Color(COR_SURTO_AMBAR.r * 0.8, COR_SURTO_AMBAR.g * 0.4, 0.0, 1.0) * glow

		pulso_alerta.emit(onda_final, cor_multiplicativa)


## Estado PARTIAL_BLACKOUT: Queda para 60% de escuridão com luz vermelha em meia-fase
func _processar_blecaute_parcial(_delta: float) -> void:
	# Nível base luminoso: 1.0 - 0.60 = 0.40 (40% de luz restante)
	var nivel_luz_base: float = 1.0 - clampf(fator_escuridao, 0.1, 0.95)

	# Oscilação lenta de meia-fase das baterias auxiliares (0.85 Hz)
	var seno_fase: float = (sin(tempo_estado * freq_meia_fase * TAU) + 1.0) * 0.5

	# Micro-ruído aleatório simulando instabilidade de carga dos capacitores
	var flutuacao_bateria: float = (_ruido_suave(tempo_total * 6.5) - 0.5) * instabilidade_bateria

	# Respiração profunda de emergência entre COR_BLECAUTE_BASE e COR_BLECAUTE_PULSO
	var cor_fase: Color = COR_BLECAUTE_BASE.lerp(COR_BLECAUTE_PULSO, seno_fase)

	var fator_tensão: float = clampf(1.0 + flutuacao_bateria + (seno_fase - 0.5) * 0.15, 0.75, 1.25)
	cor_multiplicativa = Color(
		cor_fase.r * (nivel_luz_base / 0.40) * fator_tensão,
		cor_fase.g * (nivel_luz_base / 0.40) * fator_tensão,
		cor_fase.b * (nivel_luz_base / 0.40) * fator_tensão,
		1.0
	)

	# Brilho aditivo nulo ou muito tímido nos LEDs de emergência
	cor_aditiva = Color(0.04, 0.005, 0.005, 1.0) * seno_fase


## Estado RECUPERACAO: Fade-in progressivo de 1.8 segundos com clacks mecânicos de relé
func _processar_recuperacao(_delta: float) -> void:
	var progresso: float = clampf(tempo_estado / maxf(0.001, duracao_recuperacao), 0.0, 1.0)

	# Curva cúbica suave (Smoothstep) para alívio gratificante
	var curva_suave: float = progresso * progresso * (3.0 - 2.0 * progresso)

	# Disparo de relés progressivos (clacks de circuito reacendendo)
	var flash_rele: float = 0.0

	# Relé 1 (25% do tempo, ~0.45s): Barramento auxiliar secundário online
	if progresso >= 0.25 and not rele_estagio_1_disparado:
		rele_estagio_1_disparado = true
		rele_acionado.emit(1, "BARRAMENTO_AUXILIAR")
		flash_rele = 0.25

	# Relé 2 (58% do tempo, ~1.05s): Circuitos vitais e subestações de habitat
	if progresso >= 0.58 and not rele_estagio_2_disparado:
		rele_estagio_2_disparado = true
		rele_acionado.emit(2, "SUBESTACAO_HABITAT")
		flash_rele = 0.35

	# Relé 3 (86% do tempo, ~1.55s): Rede primária estabilizada
	if progresso >= 0.86 and not rele_estagio_3_disparado:
		rele_estagio_3_disparado = true
		rele_acionado.emit(3, "REDE_PRIMARIA_ESTABILIZADA")
		flash_rele = 0.45

	# Micro-flicker residual decrescente de lâmpadas fluorescentes/xenon reacendendo
	var flicker_reativacao: float = (_ruido_suave(tempo_total * 25.0) - 0.5) * (1.0 - progresso) * 0.08

	# Interpolação da cor inicial do blecaute até a cor branca neutra normal
	var cor_transicao: Color = cor_inicio_recuperacao.lerp(COR_NORMAL, curva_suave)
	var ganho_brilho: float = clampf(1.0 + flicker_reativacao, 0.5, 1.1)

	cor_multiplicativa = Color(
		clampf(cor_transicao.r * ganho_brilho, 0.0, 1.0),
		clampf(cor_transicao.g * ganho_brilho, 0.0, 1.0),
		clampf(cor_transicao.b * ganho_brilho, 0.0, 1.0),
		1.0
	)

	# Flash momentâneo do relé acionado
	if flash_rele > 0.0:
		cor_aditiva = Color(0.5, 0.6, 0.7, 1.0) * flash_rele
	else:
		cor_aditiva = cor_aditiva.lerp(Color(0.0, 0.0, 0.0, 0.0), 0.2)

	# Fim da recuperação: restaura estado NORMAL
	if progresso >= 1.0:
		estado_atual = Estado.NORMAL
		tempo_estado = 0.0
		cor_multiplicativa = COR_NORMAL
		cor_aditiva = Color(0.0, 0.0, 0.0, 0.0)
		recuperacao_concluida.emit()
		estado_mudou.emit(Estado.NORMAL, Estado.RECUPERACAO)


# ------------------------------------------------------------------------------
# CONTROLE DE RENDERIZAÇÃO E HIERARQUIA VISUAL
# ------------------------------------------------------------------------------

func _transicionar_para(novo: Estado) -> void:
	if estado_atual == novo:
		tempo_estado = 0.0
		return
	estado_anterior = estado_atual
	estado_atual = novo
	tempo_estado = 0.0
	estado_mudou.emit(estado_atual, estado_anterior)


func _construir_camadas_visuais() -> void:
	# Camada 1: Retângulo Multiplicativo (modula cor e escuridão sem alterar sprites)
	_rect_multiplicativo = ColorRect.new()
	_rect_multiplicativo.name = "OverlayMultiplicativo"
	_rect_multiplicativo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect_multiplicativo.size = Vector2(LARGURA_NATIVA, ALTURA_NATIVA)
	_rect_multiplicativo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat_mul: CanvasItemMaterial = CanvasItemMaterial.new()
	mat_mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_rect_multiplicativo.material = mat_mul
	_rect_multiplicativo.color = COR_NORMAL
	add_child(_rect_multiplicativo)

	# Camada 2: Retângulo Aditivo (arcos elétricos, faíscas e flashes de alta tensão)
	_rect_aditivo = ColorRect.new()
	_rect_aditivo.name = "OverlayAditivo"
	_rect_aditivo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect_aditivo.size = Vector2(LARGURA_NATIVA, ALTURA_NATIVA)
	_rect_aditivo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat_add: CanvasItemMaterial = CanvasItemMaterial.new()
	mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_rect_aditivo.material = mat_add
	_rect_aditivo.color = Color(0.0, 0.0, 0.0, 0.0)
	add_child(_rect_aditivo)

	# Camada 3 e 4: Modo de compatibilidade alfa (fallback automático caso desative multiply)
	_rect_compat_escuro = ColorRect.new()
	_rect_compat_escuro.name = "OverlayCompatEscuro"
	_rect_compat_escuro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect_compat_escuro.size = Vector2(LARGURA_NATIVA, ALTURA_NATIVA)
	_rect_compat_escuro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect_compat_escuro.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect_compat_escuro.visible = not usar_blend_multiply
	add_child(_rect_compat_escuro)

	_rect_compat_cor = ColorRect.new()
	_rect_compat_cor.name = "OverlayCompatCor"
	_rect_compat_cor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect_compat_cor.size = Vector2(LARGURA_NATIVA, ALTURA_NATIVA)
	_rect_compat_cor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect_compat_cor.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect_compat_cor.visible = not usar_blend_multiply
	add_child(_rect_compat_cor)


func _aplicar_cores(c_mul: Color, c_add: Color) -> void:
	if usar_blend_multiply:
		if _rect_multiplicativo != null:
			_rect_multiplicativo.visible = true
			_rect_multiplicativo.color = c_mul
		if _rect_aditivo != null:
			_rect_aditivo.visible = true
			_rect_aditivo.color = c_add
		if _rect_compat_escuro != null:
			_rect_compat_escuro.visible = false
		if _rect_compat_cor != null:
			_rect_compat_cor.visible = false
	else:
		# Fallback de cor alfa controlada
		if _rect_multiplicativo != null:
			_rect_multiplicativo.visible = false
		if _rect_aditivo != null:
			_rect_aditivo.visible = false

		var brilho_medio: float = (c_mul.r * 0.299 + c_mul.g * 0.587 + c_mul.b * 0.114)
		var alfa_escuro: float = clampf(1.0 - brilho_medio, 0.0, 0.95)
		if _rect_compat_escuro != null:
			_rect_compat_escuro.visible = true
			_rect_compat_escuro.color = Color(0.02, 0.03, 0.06, alfa_escuro)

		if _rect_compat_cor != null:
			_rect_compat_cor.visible = true
			_rect_compat_cor.color = Color(c_mul.r, c_mul.g, c_mul.b, 0.35)

	# Atualiza o CanvasModulate externo se vinculado
	if canvas_modulate_alvo != null and is_instance_valid(canvas_modulate_alvo):
		canvas_modulate_alvo.color = c_mul


# ------------------------------------------------------------------------------
# GERADORES DE RUÍDO E HASH PROCEDURAL (DETERMINÍSTICO E SEM DISCONTINUIDADE)
# ------------------------------------------------------------------------------

static func _fract(v: float) -> float:
	return v - floorf(v)


static func _hash_ruido(x: float) -> float:
	return _fract(sin(x * 127.1 + 311.7) * 43758.5453123)


static func _ruido_suave(x: float) -> float:
	var i: float = floorf(x)
	var f: float = _fract(x)
	# Curva cúbica Hermite de interpolação suave
	var u: float = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash_ruido(i), _hash_ruido(i + 1.0), u)


# ------------------------------------------------------------------------------
# BATERIA DE TESTES UNITÁRIOS E INTEGRIDADE
# ------------------------------------------------------------------------------

## Executa uma bateria completa de validação das fórmulas, transições e constantes.
static func executar_testes() -> Dictionary:
	var relatorio: Dictionary = {
		"sucesso": true,
		"detalhes": {},
		"erros": []
	}

	# Teste 1: Fórmulas matemáticas de ruído
	var r0: float = _ruido_suave(0.0)
	var r1: float = _ruido_suave(1.5)
	var r2: float = _ruido_suave(2.7)
	if is_nan(r0) or is_nan(r1) or is_nan(r2) or is_inf(r0) or is_inf(r1) or is_inf(r2):
		relatorio["erros"].append("Ruído procedural gerou NaN ou Infinito!")
	else:
		relatorio["detalhes"]["ruido_procedural"] = {
			"r0": r0, "r1": r1, "r2": r2, "status": "OK"
		}

	# Teste 2: Validação de durações e fatores obrigatórios
	if absf(DURACAO_RECUPERACAO_PADRAO - 1.8) > 0.0001:
		relatorio["erros"].append("Duração de recuperação deve ser exatamente 1.8 segundos!")
	else:
		relatorio["detalhes"]["duracao_recuperacao"] = "1.8s (OK)"

	# Teste 3: Simulação de máquina de estados
	var instancia: IluminacaoEmergencia = IluminacaoEmergencia.new()
	instancia._ready()

	# Normal
	if instancia.obter_estado() != Estado.NORMAL:
		relatorio["erros"].append("Estado inicial deve ser NORMAL!")

	# Surto Solar
	instancia.ativar_surto_solar(1.5)
	if instancia.obter_estado() != Estado.SOLAR_SURGE:
		relatorio["erros"].append("Falha ao ativar SOLAR_SURGE!")

	# Blecaute Parcial
	instancia.ativar_blecaute_parcial()
	if instancia.obter_estado() != Estado.PARTIAL_BLACKOUT:
		relatorio["erros"].append("Falha ao ativar PARTIAL_BLACKOUT!")

	# Recuperação
	instancia.iniciar_recuperacao()
	if instancia.obter_estado() != Estado.RECUPERACAO:
		relatorio["erros"].append("Falha ao iniciar RECUPERACAO!")

	# Reset
	instancia.resetar_normal()
	if instancia.obter_estado() != Estado.NORMAL:
		relatorio["erros"].append("Falha ao resetar para NORMAL!")

	# Processamento simulado de 1 segundo de Blecaute
	instancia.ativar_blecaute_parcial()
	instancia._process(0.5)
	var cor_blecaute: Color = instancia.obter_cor_modulacao()
	var lum_blecaute: float = instancia.obter_nivel_luminosidade()

	# Verifica se a luminosidade caiu significativamente (ficou em torno de 40% de luz = 60% de escuridão)
	if lum_blecaute > 0.55:
		relatorio["erros"].append("Luminosidade no blecaute não atingiu ~60% de escuridão: %.2f" % lum_blecaute)
	else:
		relatorio["detalhes"]["teste_blecaute"] = {
			"cor": str(cor_blecaute),
			"luminosidade": lum_blecaute,
			"status": "OK"
		}

	# Simulação da recuperação completa (1.8s)
	instancia.iniciar_recuperacao()
	instancia._process(0.9)  # Metade
	if instancia.obter_estado() != Estado.RECUPERACAO:
		relatorio["erros"].append("Estado deveria continuar em RECUPERACAO aos 0.9s!")
	instancia._process(1.0)  # Total 1.9s -> Deve concluir
	if instancia.obter_estado() != Estado.NORMAL:
		relatorio["erros"].append("Estado deveria ter voltado para NORMAL após 1.8s!")
	else:
		relatorio["detalhes"]["teste_recuperacao_fade"] = "Concluído com transição para NORMAL (OK)"

	instancia.free()

	if relatorio["erros"].size() > 0:
		relatorio["sucesso"] = false

	return relatorio
