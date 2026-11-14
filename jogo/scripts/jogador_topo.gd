extends CharacterBody2D
## Astronauta da versão vista de cima (três quartos): anda em 8 direções; a animação segue a direção dominante
## (baixo, cima, esquerda, direita). Origem do nó = pés (os quadros de 48x48 têm os pés na linha 46).
## Segurando Shift (ação `correr`) corre, com a animação run_<dir> e mais poeira.
## Na Lua, levanta um pouco de poeira ao andar. Modo demonstração: anda até `bot_alvo` (a próxima tarefa).

const VEL_ANDAR := 70.0
const VEL_CORRER := 115.0
const ACEL := 850.0

var frames_res := ""
var poeira_cores: Array = []
var demo := false
var sem_desvio := false            # no mapa o robô segue um caminho calculado: preso (porta fechando), só espera
var com_poeira := false
var bot_alvo := Vector2.INF
var bot_espera := 0.0
var t_usar := 0.0
var lanterna_energia := 0.0        # (a versão de plataforma usa; aqui fica parada)
var mult_vel := 1.0                # multiplicador da velocidade (aba DEV do menu de pausa)

var spr: AnimatedSprite2D
var poeira: CPUParticles2D
var dir := "down"
var t_passo := 0.0
var t_preso := 0.0
var desvio := Vector2.ZERO
var t_desvio := 0.0
var pos_antes := Vector2.ZERO


func _ready() -> void:
	spr = AnimatedSprite2D.new()
	spr.sprite_frames = load(frames_res)
	spr.position = Vector2(0, -22)
	add_child(spr)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(12, 6)
	cs.shape = sh
	cs.position = Vector2(0, -3)
	add_child(cs)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	poeira = CPUParticles2D.new()
	poeira.emitting = false
	poeira.one_shot = true
	poeira.amount = 4
	poeira.explosiveness = 0.9
	poeira.lifetime = 0.7
	poeira.direction = Vector2(0, -1)
	poeira.spread = 70.0
	poeira.initial_velocity_min = 10.0
	poeira.initial_velocity_max = 24.0
	poeira.gravity = Vector2(0, 60)
	poeira.scale_amount_min = 1.0
	poeira.scale_amount_max = 2.0
	var g := Gradient.new()
	g.set_color(0, Color(poeira_cores[1] if poeira_cores.size() > 1 else "#a8b5b2"))
	g.set_color(1, Color(Color(poeira_cores[0] if poeira_cores.size() > 0 else "#819796"), 0.0))
	poeira.color_ramp = g
	poeira.local_coords = false
	add_child(poeira)
	pos_antes = global_position


func usar() -> void:
	t_usar = 0.45
	spr.play("use_" + dir)


func bot_quer_usar(_t: Dictionary) -> bool:
	return demo and bot_alvo != Vector2.INF and global_position.distance_to(bot_alvo) < 20.0 and bot_espera > 0.25


func _entrada(delta: float) -> Vector2:
	if not demo:
		return Input.get_vector("esquerda", "direita", "cima", "baixo")
	if bot_alvo == Vector2.INF:
		return Vector2.ZERO
	var d := bot_alvo - global_position
	if d.length() < 14.0 or (d.length() < 20.0 and t_preso > 0.2):
		bot_espera += delta
		return Vector2.ZERO
	bot_espera = 0.0
	# preso numa parede ou objeto: desvia de lado por um instante
	if global_position.distance_to(pos_antes) < 0.3:
		t_preso += delta
	else:
		t_preso = 0.0
	pos_antes = global_position
	if t_preso > 0.25 and t_desvio <= 0.0 and not sem_desvio:
		desvio = Vector2(-d.y, d.x).normalized() * (1 if randf() < 0.5 else -1)
		t_desvio = 0.6
	if t_desvio > 0.0:
		t_desvio -= delta
		return desvio
	return d.normalized()


func _physics_process(delta: float) -> void:
	var ent := Vector2.ZERO if t_usar > 0.0 else _entrada(delta)
	var correndo := not demo and Input.is_action_pressed("correr")
	var vmax := (VEL_CORRER if correndo else VEL_ANDAR) * mult_vel
	velocity = velocity.move_toward(ent * vmax, ACEL * mult_vel * delta)
	move_and_slide()
	t_usar = max(0.0, t_usar - delta)
	if t_usar > 0.0:
		return
	if ent.length() > 0.1:
		if abs(ent.x) > abs(ent.y):
			dir = "right" if ent.x > 0 else "left"
		else:
			dir = "down" if ent.y > 0 else "up"
	var anim := "idle_"
	if velocity.length() > 8.0:
		anim = "run_" if correndo and spr.sprite_frames.has_animation("run_" + dir) else "walk_"
	anim += dir
	if spr.animation != anim:
		spr.play(anim)
	if com_poeira and velocity.length() > 8.0:
		t_passo -= delta
		if t_passo <= 0.0:
			t_passo = 0.20 if correndo else 0.32
			poeira.restart()
