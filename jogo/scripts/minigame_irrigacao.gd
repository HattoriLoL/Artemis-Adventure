extends Control

signal terminou

const Fonte = preload("res://scripts/fonte.gd")
const TEXTO := Color("#ebede9")
const CERTO := Color("#a8ca58")
const DESTAQUE := Color("#e8c170")
const ERRO := Color("#cf573c")
const FUNDO_AREA := Color("#394a50")
const CANO_SECO := Color("#9aa5a8")
const AGUA := Color("#5b9bd5")
const CAMA_SECA := Color("#6b4a2e")

const COLUNAS := 5
const LINHAS := 3
const CELULA := 32
const GRADE_X := 80
const GRADE_Y := 40
const LINHA_ENTRADA := 1

const ERROS_MAX := 5
const MINIMO_GIROS := 9
const TEMPO_FIM := 0.5
const PASSO_DEMO := 0.15

const N := 1
const L := 2
const S := 4
const O := 8
const DIRECOES := {1: Vector2i(0, -1), 2: Vector2i(1, 0), 4: Vector2i(0, 1), 8: Vector2i(-1, 0)}

var demo := false

var solucao: Array[int] = []
var masc: Array[int] = []
var molhado: Array[bool] = []
var cursor := Vector2i(0, LINHA_ENTRADA)
var erros := 0
var perdeu := false
var taxa_erro := 0.0
var _e_liberado := false
var _fim := false
var _t_fim := 0.0
var _t_demo := 0.0

@onready var grade: Control = $Grade
@onready var camas: Array = [$Cama1, $Cama2, $Cama3]
@onready var textos: Control = $Textos


func _ready() -> void:
	_criar_teclas()
	for i in COLUNAS * LINHAS:
		molhado.append(false)
	_sortear_tabuleiro()
	grade.draw.connect(_desenhar_grade)
	textos.draw.connect(_desenhar_textos)


func _process(delta: float) -> void:
	if not _e_liberado and not Input.is_action_pressed("usar"):
		_e_liberado = true
	if _fim:
		_t_fim -= delta
		if _t_fim <= 0.0:
			set_process(false)
			terminou.emit()
			return
	elif demo:
		_passo_demo(delta)
	elif _e_liberado:
		_ler_teclado()
	_atualizar_camas()
	grade.queue_redraw()
	textos.queue_redraw()


func _ler_teclado() -> void:
	if Input.is_action_just_pressed("esquerda"):
		cursor.x = maxi(cursor.x - 1, 0)
	if Input.is_action_just_pressed("direita"):
		cursor.x = mini(cursor.x + 1, COLUNAS - 1)
	if Input.is_action_just_pressed("cima"):
		cursor.y = maxi(cursor.y - 1, 0)
	if Input.is_action_just_pressed("baixo"):
		cursor.y = mini(cursor.y + 1, LINHAS - 1)
	if Input.is_action_just_pressed("usar"):
		_girar(cursor)


func _passo_demo(delta: float) -> void:
	_t_demo += delta
	if _t_demo < PASSO_DEMO:
		return
	_t_demo = 0.0
	for r in LINHAS:
		for c in COLUNAS:
			if masc[r * COLUNAS + c] != solucao[r * COLUNAS + c]:
				cursor = Vector2i(c, r)
				_girar(cursor)
				return


func _girar(pos: Vector2i) -> void:
	var i := pos.y * COLUNAS + pos.x
	if masc[i] == 0 or masc[i] == 15:
		return
	var antes := _distancia(i)
	masc[i] = _rodar(masc[i])
	if _distancia(i) >= antes:
		erros += 1
	_calcular_agua()
	if _camas_molhadas() == camas.size():
		taxa_erro = minf(float(erros) / float(ERROS_MAX), 1.0)
		_fim = true
		_t_fim = TEMPO_FIM
	elif erros >= ERROS_MAX:
		perdeu = true
		taxa_erro = 1.0
		_fim = true
		_t_fim = TEMPO_FIM


func _rodar(m: int) -> int:
	return ((m << 1) & 15) | (m >> 3)


func _oposto(d: int) -> int:
	return _rodar(_rodar(d))


func _distancia(i: int) -> int:
	var m := masc[i]
	var k := 0
	while m != solucao[i]:
		m = _rodar(m)
		k += 1
	return k


func _distancia_total() -> int:
	var total := 0
	for i in masc.size():
		total += _distancia(i)
	return total


func _sortear_tabuleiro() -> void:
	for tentativa in 50:
		_gerar_solucao()
		masc.clear()
		for m in solucao:
			masc.append(m)
		for i in masc.size():
			for k in randi() % 4:
				masc[i] = _rodar(masc[i])
		_calcular_agua()
		if _camas_molhadas() < camas.size() and _distancia_total() >= MINIMO_GIROS:
			return
	while _camas_molhadas() == camas.size():
		for i in masc.size():
			if masc[i] != 0 and masc[i] != 15:
				masc[i] = _rodar(masc[i])
				break
		_calcular_agua()


func _gerar_solucao() -> void:
	solucao.clear()
	for i in COLUNAS * LINHAS:
		solucao.append(0)
	solucao[LINHA_ENTRADA * COLUNAS] |= O
	for r in LINHAS:
		var linha := LINHA_ENTRADA
		for c in COLUNAS:
			var alvo := r if c == COLUNAS - 1 else randi() % LINHAS
			while linha != alvo:
				var prox := linha + signi(alvo - linha)
				_ligar(Vector2i(c, linha), Vector2i(c, prox))
				linha = prox
			if c < COLUNAS - 1:
				_ligar(Vector2i(c, linha), Vector2i(c + 1, linha))
		solucao[r * COLUNAS + COLUNAS - 1] |= L


func _ligar(a: Vector2i, b: Vector2i) -> void:
	var d := b - a
	var bit := N
	if d == Vector2i(1, 0):
		bit = L
	elif d == Vector2i(0, 1):
		bit = S
	elif d == Vector2i(-1, 0):
		bit = O
	solucao[a.y * COLUNAS + a.x] |= bit
	solucao[b.y * COLUNAS + b.x] |= _oposto(bit)


func _calcular_agua() -> void:
	for i in molhado.size():
		molhado[i] = false
	var inicio := LINHA_ENTRADA * COLUNAS
	if masc[inicio] & O == 0:
		return
	molhado[inicio] = true
	var fila: Array[int] = [inicio]
	while not fila.is_empty():
		var i: int = fila.pop_back()
		var c := i % COLUNAS
		var r := floori(i / float(COLUNAS))
		for d in DIRECOES:
			if masc[i] & d == 0:
				continue
			var v: Vector2i = Vector2i(c, r) + DIRECOES[d]
			if v.x < 0 or v.x >= COLUNAS or v.y < 0 or v.y >= LINHAS:
				continue
			var j := v.y * COLUNAS + v.x
			var oposto: int = _oposto(d)
			if molhado[j] or masc[j] & oposto == 0:
				continue
			molhado[j] = true
			fila.append(j)


func _cama_molhada(r: int) -> bool:
	var i := r * COLUNAS + COLUNAS - 1
	return molhado[i] and masc[i] & L != 0


func _camas_molhadas() -> int:
	var n := 0
	for r in LINHAS:
		if _cama_molhada(r):
			n += 1
	return n


func _atualizar_camas() -> void:
	for r in LINHAS:
		camas[r].color = CERTO if _cama_molhada(r) else CAMA_SECA


func _desenhar_grade() -> void:
	for r in LINHAS:
		for c in COLUNAS:
			var x := GRADE_X + c * CELULA
			var y := GRADE_Y + r * CELULA
			grade.draw_rect(Rect2(x + 1, y + 1, CELULA - 2, CELULA - 2), FUNDO_AREA)
			var m := masc[r * COLUNAS + c]
			var cor := AGUA if molhado[r * COLUNAS + c] else CANO_SECO
			var cx := x + 16
			var cy := y + 16
			if m & N != 0:
				grade.draw_rect(Rect2(cx - 3, y, 6, 19), cor)
			if m & L != 0:
				grade.draw_rect(Rect2(cx - 3, cy - 3, 19, 6), cor)
			if m & S != 0:
				grade.draw_rect(Rect2(cx - 3, cy - 3, 6, 19), cor)
			if m & O != 0:
				grade.draw_rect(Rect2(x, cy - 3, 19, 6), cor)
	var cur := Vector2(GRADE_X + cursor.x * CELULA, GRADE_Y + cursor.y * CELULA)
	grade.draw_rect(Rect2(cur, Vector2(CELULA, CELULA)), DESTAQUE, false, 2.0)


func _desenhar_textos() -> void:
	if _fim and perdeu:
		Fonte.centralizado(textos, "TOO MANY MISTAKES  LINE FAILED", 160, 150, ERRO)
	elif _fim:
		if erros == 0:
			Fonte.centralizado(textos, "PERFECT REPAIR", 160, 150, CERTO)
		elif erros < ERROS_MAX - 1:
			Fonte.centralizado(textos, "IRRIGATION FIXED", 160, 150, CERTO)
		else:
			Fonte.centralizado(textos, "BARELY FIXED", 160, 150, DESTAQUE)
	else:
		Fonte.centralizado(textos, "CONNECT THE TANK TO ALL 3 BEDS", 160, 14, TEXTO)
		Fonte.centralizado(textos, "ARROWS: MOVE   E: ROTATE", 160, 150, TEXTO)
	var cor_erros := ERRO if erros >= ERROS_MAX - 1 else DESTAQUE
	Fonte.centralizado(textos, "MISTAKES " + str(erros) + " OF " + str(ERROS_MAX), 160, 164, cor_erros)


func _criar_teclas() -> void:
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
