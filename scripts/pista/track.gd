extends Node2D
class_name Track

# Orquestra a corrida: gera a pista (GeradorPista), cria as paredes de colisão,
# põe o carro na partida e liga as peças (estatísticas, HUD, câmara).

@export var track_width := 120.0
@export var num_points := 12
@export var min_radius := 300.0
@export var max_radius := 600.0
@export var car_scene: PackedScene  # arrasta aqui a cena do carro no Inspetor

## Nome do ficheiro Python na raiz do projeto (sem .py) que controla o carro.
## Se não existir, o carro continua a usar as setas (GDScript).
@export var classe_controlador_python := "main"

var centerline := PackedVector2Array()
var left_border := PackedVector2Array()
var right_border := PackedVector2Array()

var current_seed := 0

var car: Carro
var start_position := Vector2.ZERO
var start_rotation := 0.0

var _gerador: GeradorPista

@onready var _walls_shape: CollisionShape2D = $Walls/CollisionShape2D
@onready var _camera: CamaraPista = $Camera2D
@onready var _stats: EstatisticasCorrida = $Estatisticas
@onready var _hud: HudCorrida = $HUD


func _ready() -> void:
	_gerador = GeradorPista.new(track_width, num_points, min_radius, max_radius)
	get_viewport().size_changed.connect(_fit_camera)
	generate(current_seed)


func _unhandled_input(event: InputEvent) -> void:
	# R = pista nova com uma seed aleatória
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		current_seed = randi() % 100000
		print("Seed: ", current_seed)
		generate(current_seed)
	# Enter / Espaço = recomeça na mesma pista
	elif event.is_action_pressed("ui_accept"):
		reiniciar_corrida()


func generate(seed_: int) -> void:
	centerline = _gerador.gerar(seed_)
	_build()


## Volta a pôr o carro na partida e põe batidas, tempo e voltas a zero.
func reiniciar_corrida() -> void:
	if car == null:
		return
	car.reiniciar(to_global(start_position), global_rotation + start_rotation)
	_stats.reiniciar()


# Bordas, paredes de colisão, ponto de partida, carro, desenho e câmara
func _build() -> void:
	var bordas := _gerador.calcular_bordas(centerline)
	left_border = bordas["esquerda"]
	right_border = bordas["direita"]

	var n := centerline.size()
	var segs := PackedVector2Array()
	for i in n:
		var j := (i + 1) % n
		segs.append_array(PackedVector2Array([left_border[i], left_border[j], right_border[i], right_border[j]]))
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segs
	_walls_shape.shape = shape

	_compute_start()
	_garantir_carro()
	_stats.definir_pista(centerline)
	reiniciar_corrida()
	queue_redraw()
	_fit_camera()


# Ponto de partida = primeiro ponto da linha central, virado para o seguinte
func _compute_start() -> void:
	start_position = centerline[0]
	var next := centerline[1 % centerline.size()]
	start_rotation = (next - start_position).angle()


# Cria o carro na primeira vez e liga-o às estatísticas, HUD e câmara
func _garantir_carro() -> void:
	if car != null or car_scene == null:
		return
	car = car_scene.instantiate() as Carro
	add_child(car)
	_stats.configurar(car)
	_hud.configurar(car, _stats)
	_camera.alvo = car
	#_adicionar_controlador_python()   #descomentar para o script python


func _adicionar_controlador_python() -> void:
	var caminho := "res://%s.py" % classe_controlador_python
	if classe_controlador_python.is_empty() or not ResourceLoader.exists(caminho):
		print("Script Python não encontrado em %s: a usar as setas (GDScript)." % caminho)
		return

	var script := load(caminho) as Script
	if script == null:
		print("Não consegui carregar %s: a usar as setas (GDScript)." % caminho)
		return

	var controlador := Node.new()
	controlador.name = "ControladorPython"
	controlador.set_script(script)
	car.add_child(controlador)
	print("Script Python adicionado ao carro: ", caminho)


# Centra a câmara na pista e ajusta o zoom para caber toda no ecrã
func _fit_camera() -> void:
	if centerline.is_empty():
		return
	var rect := Rect2(centerline[0], Vector2.ZERO)
	for p in centerline:
		rect = rect.expand(p)
	rect = rect.grow(track_width)
	var ratio := get_viewport_rect().size / rect.size
	_camera.definir_vista_geral(to_global(rect.get_center()), Vector2.ONE * minf(ratio.x, ratio.y))


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
