extends Node2D
class_name Track

@export var track_width := 120.0
@export var num_points := 12
@export var min_radius := 300.0
@export var max_radius := 600.0
@export var car_scene: PackedScene  # arrasta aqui a cena do carro no Inspetor

var centerline := PackedVector2Array()
var left_border := PackedVector2Array()
var right_border := PackedVector2Array()

var current_seed := 0

var car: CharacterBody2D
var start_position := Vector2.ZERO
var start_rotation := 0.0


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_camera)
	generate(current_seed)


# R = pista nova com uma seed aleatória
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		current_seed = randi() % 100000
		print("Seed: ", current_seed)
		generate(current_seed)


# Mesma seed = mesma pista. Tenta variantes da seed até não haver curvas apertadas demais.
func generate(seed_: int) -> void:
	var rng := RandomNumberGenerator.new()
	for attempt in 200:
		rng.seed = seed_ * 1000 + attempt
		centerline = _random_centerline(rng)
		if _min_turn_radius() > track_width * 0.5 + 15.0:
			_build()
			return
	push_warning("Seed %d: nenhuma variante válida, a pista pode ter curvas apertadas" % seed_)
	_build()


# Pontos aleatórios à volta de um círculo, ligados por uma curva fechada e suave
func _random_centerline(rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for i in num_points:
		var angle := TAU * i / num_points + rng.randf_range(-0.15, 0.15)
		pts.append(Vector2.from_angle(angle) * rng.randf_range(min_radius, max_radius))

	var curve := Curve2D.new()
	for i in num_points + 1:  # o último ponto repete o primeiro para fechar
		var h := (pts[(i + 1) % num_points] - pts[(i - 1 + num_points) % num_points]) / 6.0
		curve.add_point(pts[i % num_points], -h, h)

	var sampled := curve.tessellate_even_length(6, 10.0)
	sampled.remove_at(sampled.size() - 1)  # o último ponto coincide com o primeiro
	return sampled


# Raio de curvatura mínimo estimado ao longo da linha central
func _min_turn_radius() -> float:
	var n := centerline.size()
	var min_r := INF
	for i in n:
		var a := centerline[i] - centerline[(i - 3 + n) % n]
		var b := centerline[(i + 3) % n] - centerline[i]
		var ang := absf(a.angle_to(b))
		if ang > 0.001:
			min_r = minf(min_r, (a.length() + b.length()) * 0.5 / ang)
	return min_r


# Bordas, paredes de colisão, ponto de partida, carro, desenho e câmara
func _build() -> void:
	var n := centerline.size()
	left_border.resize(n)
	right_border.resize(n)
	for i in n:
		var t := (centerline[(i + 1) % n] - centerline[(i - 1 + n) % n]).normalized()
		var offset := Vector2(-t.y, t.x) * track_width * 0.5
		left_border[i] = centerline[i] + offset
		right_border[i] = centerline[i] - offset

	var segs := PackedVector2Array()
	for i in n:
		var j := (i + 1) % n
		segs.append_array(PackedVector2Array([left_border[i], left_border[j], right_border[i], right_border[j]]))
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segs
	$Walls/CollisionShape2D.shape = shape

	_compute_start()
	_spawn_car()
	queue_redraw()
	_fit_camera()


# Ponto de partida = primeiro ponto da linha central, virado para o seguinte
func _compute_start() -> void:
	start_position = centerline[0]
	var next := centerline[1 % centerline.size()]
	start_rotation = (next - start_position).angle()


# Cria o carro na primeira vez; nas seguintes apenas o reposiciona
func _spawn_car() -> void:
	if car_scene == null:
		return
	if car == null:
		car = car_scene.instantiate()
		add_child(car)
	car.global_position = to_global(start_position)
	car.global_rotation = start_rotation
	car.velocity = Vector2.ZERO  # não herda velocidade da pista anterior


# Centra a câmara na pista e ajusta o zoom para caber toda no ecrã
func _fit_camera() -> void:
	if centerline.is_empty():
		return
	var rect := Rect2(centerline[0], Vector2.ZERO)
	for p in centerline:
		rect = rect.expand(p)
	rect = rect.grow(track_width)
	var ratio := get_viewport_rect().size / rect.size
	$Camera2D.position = rect.get_center()
	$Camera2D.zoom = Vector2.ONE * minf(ratio.x, ratio.y)


func _draw() -> void:
	if centerline.is_empty():
		return
	draw_polyline(_closed(centerline), Color(0.25, 0.25, 0.25), track_width)
	draw_polyline(_closed(left_border), Color.WHITE, 3.0)
	draw_polyline(_closed(right_border), Color.WHITE, 3.0)

	# Linha de partida
	var t := Vector2.from_angle(start_rotation)
	var normal := Vector2(-t.y, t.x) * track_width * 0.5
	draw_line(start_position - normal, start_position + normal, Color.YELLOW, 4.0)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	return pts + PackedVector2Array([pts[0]])
