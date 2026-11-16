extends Control
## VirtualDPad: D-Pad direcional virtual em pixel art para movimentação em 8 direções.
## Alimenta as Input Actions nativas ("cima", "baixo", "esquerda", "direita", "correr").

const COR_FUNDO := Color("#151d28", 0.65)
const COR_BORDA := Color("#394a50", 0.85)
const COR_BORDA_CLARA := Color("#819796", 0.90)
const COR_NORMAL := Color("#819796", 0.75)
const COR_ATIVO := Color("#f2b134", 1.0) # Amarelo Apolo brilhante
const COR_CENTRO := Color("#202b38", 0.8)

var touch_id := -1
var ativo := false
var vetor_direcao := Vector2.ZERO

var pressionado_cima := false
var pressionado_baixo := false
var pressionado_esquerda := false
var pressionado_direita := false
var pressionado_correr := false

# Dimensões do D-Pad
@export var raio: float = 24.0
@export var zona_morta: float = 5.0


func _ready() -> void:
	custom_minimum_size = Vector2(raio * 2 + 8, raio * 2 + 8)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _exit_tree() -> void:
	_liberar_tudo()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			_liberar_tudo()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed and touch_id == -1:
			touch_id = ev.index
			_atualizar_toque(ev.position)
			accept_event()
		elif not ev.pressed and ev.index == touch_id:
			_liberar_tudo()
			accept_event()
	elif ev is InputEventScreenDrag and ev.index == touch_id:
		_atualizar_toque(ev.position)
		accept_event()
	# Suporte a mouse (para testes e depuração no editor / PC)
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed and touch_id == -1:
				touch_id = 999
				_atualizar_toque(ev.position)
				accept_event()
			elif not ev.pressed and touch_id == 999:
				_liberar_tudo()
				accept_event()
	elif ev is InputEventMouseMotion and touch_id == 999:
		_atualizar_toque(ev.position)
		accept_event()


func _atualizar_toque(pos: Vector2) -> void:
	var centro := size / 2.0
	var offset := pos - centro
	var dist := offset.length()
	
	if dist < zona_morta:
		vetor_direcao = Vector2.ZERO
		_atualizar_acoes(false, false, false, false, false)
		queue_redraw()
		return
	
	# Normaliza e calcula componentes direcionais
	var dir := offset.normalized()
	vetor_direcao = dir
	
	# Verifica se está no limite externo para ativar corrida rápida
	var correr: bool = dist > (raio * 0.85)
	
	var threshold := 0.38
	var c := dir.y < -threshold
	var b := dir.y > threshold
	var e := dir.x < -threshold
	var d := dir.x > threshold
	
	_atualizar_acoes(c, b, e, d, correr)
	queue_redraw()


func _atualizar_acoes(c: bool, b: bool, e: bool, d: bool, correr: bool) -> void:
	if c != pressionado_cima:
		pressionado_cima = c
		_set_action("cima", c)
		
	if b != pressionado_baixo:
		pressionado_baixo = b
		_set_action("baixo", b)
		
	if e != pressionado_esquerda:
		pressionado_esquerda = e
		_set_action("esquerda", e)
		
	if d != pressionado_direita:
		pressionado_direita = d
		_set_action("direita", d)
		
	if correr != pressionado_correr:
		pressionado_correr = correr
		_set_action("correr", correr)


func _set_action(acao: String, pressionar: bool) -> void:
	if not InputMap.has_action(acao):
		InputMap.add_action(acao)
	if pressionar:
		Input.action_press(acao)
	else:
		Input.action_release(acao)


func _liberar_tudo() -> void:
	touch_id = -1
	vetor_direcao = Vector2.ZERO
	_atualizar_acoes(false, false, false, false, false)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	
	# Fundo da base do D-Pad (formato de cruz clássica em pixel art)
	var w := 14.0
	var h := raio * 2.0
	
	# Braço Vertical
	draw_rect(Rect2(c.x - w / 2.0, c.y - raio, w, h), COR_FUNDO)
	draw_rect(Rect2(c.x - w / 2.0, c.y - raio, w, h), COR_BORDA, false, 1.0)
	
	# Braço Horizontal
	draw_rect(Rect2(c.x - raio, c.y - w / 2.0, h, w), COR_FUNDO)
	draw_rect(Rect2(c.x - raio, c.y - w / 2.0, h, w), COR_BORDA, false, 1.0)
	
	# Miolo Central
	draw_rect(Rect2(c.x - w / 2.0, c.y - w / 2.0, w, w), COR_CENTRO)
	
	# Setinhas direcionais
	_desenha_seta_cima(Vector2(c.x, c.y - raio + 5), pressionado_cima)
	_desenha_seta_baixo(Vector2(c.x, c.y + raio - 6), pressionado_baixo)
	_desenha_seta_esquerda(Vector2(c.x - raio + 5, c.y), pressionado_esquerda)
	_desenha_seta_direita(Vector2(c.x + raio - 6, c.y), pressionado_direita)


func _desenha_seta_cima(p: Vector2, ativo: bool) -> void:
	var cor: Color = COR_ATIVO if ativo else COR_NORMAL
	var y_off: float = -1.0 if ativo else 0.0
	draw_rect(Rect2(p.x, p.y + y_off - 2, 1, 1), cor)
	draw_rect(Rect2(p.x - 1, p.y + y_off - 1, 3, 1), cor)
	draw_rect(Rect2(p.x - 2, p.y + y_off, 5, 1), cor)


func _desenha_seta_baixo(p: Vector2, ativo: bool) -> void:
	var cor: Color = COR_ATIVO if ativo else COR_NORMAL
	var y_off: float = 1.0 if ativo else 0.0
	draw_rect(Rect2(p.x - 2, p.y + y_off, 5, 1), cor)
	draw_rect(Rect2(p.x - 1, p.y + y_off + 1, 3, 1), cor)
	draw_rect(Rect2(p.x, p.y + y_off + 2, 1, 1), cor)


func _desenha_seta_esquerda(p: Vector2, ativo: bool) -> void:
	var cor: Color = COR_ATIVO if ativo else COR_NORMAL
	var x_off: float = -1.0 if ativo else 0.0
	draw_rect(Rect2(p.x + x_off - 2, p.y, 1, 1), cor)
	draw_rect(Rect2(p.x + x_off - 1, p.y - 1, 1, 3), cor)
	draw_rect(Rect2(p.x + x_off, p.y - 2, 1, 5), cor)


func _desenha_seta_direita(p: Vector2, ativo: bool) -> void:
	var cor: Color = COR_ATIVO if ativo else COR_NORMAL
	var x_off: float = 1.0 if ativo else 0.0
	draw_rect(Rect2(p.x + x_off, p.y - 2, 1, 5), cor)
	draw_rect(Rect2(p.x + x_off + 1, p.y - 1, 1, 3), cor)
	draw_rect(Rect2(p.x + x_off + 2, p.y, 1, 1), cor)
