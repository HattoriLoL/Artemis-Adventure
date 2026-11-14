extends Control
## Minigame de paineis solares: o joador pressiona E em cima do painel e limpa (move WASD)

signal terminou

var demo := false
var terminado := false

const Fonte = preload("res://scripts/fonte.gd")

const VELOCIDADE := 80.0
const TEMPO:=0.5
const QTD_MANCHAS:=10
const TAM_MANCHA:= 6
const TAM_ESCOVA:=6
const FIM:= 0.5

var resto:= QTD_MANCHAS
var t_fim:= 0.0
const TEXTO := Color("#ebede9")
const MANCHA := Color("#a8b5b2")

const AREA:= Rect2(60,45,200,90)
var pos_escova := Vector2(157, 87)

@onready var placas: Array[ColorRect] = [$Placa1, $Placa2, $Placa3]
@onready var manchas: Control = $Mancha
@onready var escova: ColorRect = $Escova
@onready var textos: Control = $Textos


func _ready() -> void:
	_criar_teclas()
	textos.draw.connect(_desenhar_textos)
	for i in QTD_MANCHAS:
			manchas.add_child(_criar_mancha(_pos()))

func _pos()->Vector2:
	var placa: ColorRect = placas.pick_random()
	var x := randi_range(int(placa.position.x)+2, int(placa.position.x + placa.size.x) - TAM_MANCHA -2)
	var y := randi_range(int(placa.position.y)+2,int(placa.position.y + placa.size.y) - TAM_MANCHA -2)
	return Vector2(x,y)
	
func _criar_mancha(pos: Vector2) -> ColorRect:
	var m:= ColorRect.new()
	m.color = MANCHA
	m.size = Vector2(TAM_MANCHA, TAM_MANCHA)
	m.position = pos
	return m

func _process(delta: float) -> void:
	if not terminado and resto <=0:
		terminado = true
	if terminado:
		t_fim += delta
		if t_fim >= FIM:
			terminou.emit()
			set_process(false)
	if not terminado:
		var dir:= Input.get_vector("esquerda", "direita", "cima", "baixo")
		pos_escova += dir * VELOCIDADE * delta
		pos_escova = pos_escova.clamp(AREA.position, AREA.end - Vector2(TAM_ESCOVA, TAM_ESCOVA))
		_limpar(delta)
			
	escova.position = pos_escova.round()
	textos.queue_redraw()

func _limpar(delta: float) -> void:
	var area_escova := Rect2(pos_escova, Vector2(TAM_ESCOVA, TAM_ESCOVA))
	for m: ColorRect in manchas.get_children():
		if area_escova.intersects(Rect2(m.position, m.size)):
			m.modulate.a -= delta / TEMPO
			if m.modulate.a <= 0.0:
				m.queue_free()
				resto-=1
		

func _desenhar_textos() -> void:
	var msg:= "PANELS ARE CLEAN" if terminado else "CLEAN THE PANELS"
	Fonte.centralizado(textos, msg, 160, 20, TEXTO)


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
