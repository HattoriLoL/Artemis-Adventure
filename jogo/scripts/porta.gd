extends Node2D
## Porta pressurizada entre uma sala e um túnel, como as escotilhas de uma nave de verdade: antes de abrir, a porta
## confere e iguala a pressão dos dois lados. Fechada, ela é parede. Quando o astronauta chega perto:
##   1. EQUALIZANDO: luz âmbar piscando e chiado de ar;
##   2. DESTRAVANDO: as travas soltam (clunk) e a porta dá um tranco;
##   3. ABRINDO: as duas folhas deslizam para dentro da parede; a luz fica verde;
##   4. ABERTA enquanto ele estiver perto ou no vão; depois FECHANDO (motor e batida) e FECHADA de novo.
## A pressão fica igual por um tempo: se ele voltar logo, a porta abre sem o chiado.
## Trancada: luz vermelha piscando, não abre (negar() toca o bipe).

enum {FECHADA, EQUALIZANDO, DESTRAVANDO, ABRINDO, ABERTA, FECHANDO}
const T_EQUALIZAR := 0.6
const T_DESTRAVAR := 0.18
const T_ABRIR := 0.35
const T_FECHAR := 0.3
const ESPERA_FECHAR := 0.7
const PRESSAO_DURA := 6.0          # segundos em que a pressão continua igualada depois de fechar

const VERDE_ESCURO := Color("#468232")
const VERDE := Color("#a8ca58")
const AMBAR := Color("#de9e41")
const VERMELHO := Color("#cf573c")

var dados: Dictionary
var textura: Texture2D
var alvo: Node2D                   # o astronauta
var estado := FECHADA
var t := 0.0
var t_fora := 0.0
var t_desde_fechou := 999.0
var abertura := 0.0                # 0 = fechada, 1 = aberta

var esq: Sprite2D
var dir: Sprite2D
var corpo: StaticBody2D
var forma: CollisionShape2D
var luz: ColorRect
var sons := {}
var painel: Rect2
var reg: Rect2


func _ready() -> void:
	var p: Array = dados["painel"]
	var pt: Array = dados["painel_textura"]
	painel = Rect2(p[0], p[1], p[2], p[3])
	reg = Rect2(pt[0], pt[1], pt[2], pt[3])
	position = painel.position
	z_index = -5
	var vao := Sprite2D.new()                      # o que aparece no vão quando a porta abre
	vao.texture = load("res://assets/mapa/vao_%s.png" % dados["lado"])
	vao.centered = false
	add_child(vao)
	esq = _metade()
	dir = _metade()
	corpo = StaticBody2D.new()
	forma = CollisionShape2D.new()
	var b: Array = dados["bloqueio"]
	var sh := RectangleShape2D.new()
	sh.size = Vector2(b[2], b[3])
	forma.shape = sh
	corpo.position = Vector2(b[0] + b[2] / 2.0, b[1] + b[3] / 2.0) - position
	corpo.add_child(forma)
	add_child(corpo)
	luz = ColorRect.new()
	luz.size = Vector2(8, 2)
	luz.position = Vector2(dados["luz"][0] - 4, dados["luz"][1]) - position
	add_child(luz)
	for nome in ["pressao", "trava", "abrir", "fechar", "trancada"]:
		var s := AudioStreamPlayer2D.new()
		s.stream = load("res://assets/sons/porta_%s.wav" % nome)
		s.max_distance = 260.0
		add_child(s)
		sons[nome] = s
	_desenhar()


func _metade() -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = textura
	s.centered = false
	s.region_enabled = true
	add_child(s)
	return s


func trancada() -> bool:
	return dados.get("trancada", false)


func perto(pos: Vector2) -> bool:
	var g: Array = dados["gatilho"]
	return Rect2(g[0], g[1], g[2], g[3]).has_point(pos)


func negar() -> void:
	if not sons["trancada"].playing:
		sons["trancada"].play()


func _no_vao(pos: Vector2) -> bool:
	var b: Array = dados["bloqueio"]
	return Rect2(b[0] - 7, b[1] - 1, b[2] + 14, b[3] + 8).has_point(pos)


func _process(delta: float) -> void:
	t += delta
	if trancada():
		luz.color = VERMELHO if fmod(t, 1.0) < 0.6 else Color(VERMELHO, 0.25)
		return
	var quer := alvo != null and perto(alvo.global_position)
	match estado:
		FECHADA:
			t_desde_fechou += delta
			if quer:
				if t_desde_fechou < PRESSAO_DURA:
					_mudar(DESTRAVANDO)
				else:
					_mudar(EQUALIZANDO)
		EQUALIZANDO:
			if t >= T_EQUALIZAR:
				_mudar(DESTRAVANDO)
		DESTRAVANDO:
			if t >= T_DESTRAVAR:
				_mudar(ABRINDO)
		ABRINDO:
			abertura = min(1.0, t / T_ABRIR)
			if abertura >= 1.0:
				_mudar(ABERTA)
		ABERTA:
			if quer or (alvo and _no_vao(alvo.global_position)):
				t_fora = 0.0
			else:
				t_fora += delta
				if t_fora > ESPERA_FECHAR:
					_mudar(FECHANDO)
		FECHANDO:
			if quer:                                        # voltou: abre de novo daqui mesmo
				estado = ABRINDO
				t = abertura * T_ABRIR
				sons["abrir"].play()
			else:
				abertura = max(0.0, 1.0 - t / T_FECHAR)
				if abertura <= 0.0:
					_mudar(FECHADA)
	forma.set_deferred("disabled", abertura > 0.6)
	_desenhar()


func _mudar(novo: int) -> void:
	estado = novo
	t = 0.0
	match novo:
		EQUALIZANDO:
			sons["pressao"].play()
		DESTRAVANDO:
			sons["trava"].play()
		ABRINDO:
			sons["abrir"].play()
		FECHANDO:
			sons["fechar"].play()
		FECHADA:
			t_desde_fechou = 0.0
			abertura = 0.0


func _desenhar() -> void:
	# a luz de estado
	match estado:
		FECHADA:
			luz.color = VERDE_ESCURO
		EQUALIZANDO:
			luz.color = AMBAR if fmod(t, 0.16) < 0.08 else Color(AMBAR, 0.3)
		DESTRAVANDO, FECHANDO:
			luz.color = AMBAR
		_:
			luz.color = VERDE
	# as folhas: a da esquerda entra na parede da esquerda e a da direita na da direita
	var w := reg.size.x
	var hw := floorf(w / 2.0)
	var o := roundf(_suave(abertura) * hw)
	var tranco := 0.0
	if estado == DESTRAVANDO:
		tranco = 1.0 if fmod(t, 0.08) < 0.04 else 0.0
	esq.visible = o < hw
	dir.visible = o < w - hw
	esq.region_rect = Rect2(reg.position.x + o, reg.position.y, hw - o, reg.size.y)
	esq.position = Vector2(tranco, 0)
	dir.region_rect = Rect2(reg.position.x + hw, reg.position.y, w - hw - o, reg.size.y)
	dir.position = Vector2(hw + o - tranco, 0)


func _suave(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
