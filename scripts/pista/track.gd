extends Node2D
class_name Track

# Configurações da nossa corrida de IA

@export_group("Corrida IA")

@export var numero_carros: int = 3 # quantos carros participarão da corrida.

@export var voltas_para_vencer: int = 5 #  voltas para ganhar.

@export var tempo_maximo: float = 270.0 # duração maxima da corrida em segundos

@export var corridas_avaliacao: int = 10 # Quantidade de corridas para comparar os modelos

@export var colisao_entre_carros: bool = false # Define se haverá colisões entre os veículos

@export var pista_aleatoria_por_corrida: bool = true # uma pista diferentes em cada corrida

# Orquestra a corrida: gera a pista (GeradorPista), cria as paredes de colisão,
# põe o carro na partida e liga as peças (estatísticas, HUD, câmara).

@export var track_width := 120.0
@export var num_points := 12
## Raios para 12 pontos (referência). Escalam sozinhos com num_points.
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

# Lista de carros participantes da corrida
var carros: Array[Carro] = []

# Estatísticas individuais dos carros
var estatisticas_carros: Array[EstatisticasCorrida] = []

# Nomes dos modelos de inteligência artificial
var modelos_ia: Array[String] = [
	"PPO_MLP",
	"PPO_LSTM",
    "SAC_MLP"
]

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
	if carros.is_empty():
		return

	for i in range(carros.size()):
		var novo_carro = carros[i]

		# Distribui os carros ao longo da pista
		var distancia_lateral = (i - 1) * 35.0

		# Pequena diferença longitudinal
		var distancia_frontal = -i * 45.0

		var deslocamento = Vector2(
			distancia_frontal,
			distancia_lateral
		).rotated(start_rotation)

		novo_carro.reiniciar(
			to_global(start_position + deslocamento),
			global_rotation + start_rotation
		)

	# Reinicia as estatísticas de todos os carros
	for stats in estatisticas_carros:
		stats.reiniciar()

	_hud.reiniciar_cronometro()


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
	# Informa a pista para as estatísticas de todos os carros
	for stats in estatisticas_carros:
		stats.definir_pista(centerline)
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
	if not carros.is_empty() or car_scene == null:
		return

	for i in range(numero_carros):
		var novo_carro := car_scene.instantiate() as Carro

		# Identifica cada participante
		novo_carro.name = "Carro_" + str(i + 1)

		# Por enquanto, todos usam controle manual
		novo_carro.controlo_manual = true

		# Carros não colidem entre si,
		# mas continuam colidindo com as paredes
		novo_carro.collision_layer = 2
		novo_carro.collision_mask = 1

		add_child(novo_carro)
		carros.append(novo_carro)

		# Uma cor para cada carro
		var cores = [
			Color.BLUE,
			Color.RED,
			Color.GREEN
		]

		novo_carro.modulate = cores[i % cores.size()]

		# Posições provisórias, próximas à largada
		var deslocamento := Vector2(0, (i - 1) * 30.0)
		novo_carro.reiniciar(
			to_global(start_position + deslocamento.rotated(start_rotation)),
			global_rotation + start_rotation
		)

		print("Criado: ", novo_carro.name)

	# Mantém compatibilidade com o código original
	car = carros[0]

	# Cria estatísticas individuais para cada carro
	for i in range(carros.size()):
		var stats: EstatisticasCorrida

		if i == 0:
		   # Primeiro carro utiliza as estatísticas originais
			stats = _stats
		else:
			# Outros carros recebem estatísticas próprias
			stats = EstatisticasCorrida.new()
			stats.name = "Estatisticas_Carro_" + str(i + 1)
			add_child(stats)

		# Associa as estatísticas ao carro correspondente
		stats.configurar(carros[i])
		estatisticas_carros.append(stats)

	# HUD e câmera continuam acompanhando o primeiro carro
	_hud.configurar_corrida(
		carros,
		estatisticas_carros,
		voltas_para_vencer,
		tempo_maximo,
		corridas_avaliacao
	)

	_camera.alvo = car


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
	# Asfalto: dois triângulos por segmento, entre as duas bordas. draw_primitive não
	# triangula, por isso não falha com quadriláteros torcidos nas curvas apertadas
	# (draw_colored_polygon dava "triangulation failed"), e não deixa buracos.
	var n := centerline.size()
	var cor := Color(0.25, 0.25, 0.25)
	var cores := PackedColorArray([cor, cor, cor])
	var sem_uv := PackedVector2Array()
	for i in n:
		var j := (i + 1) % n
		draw_primitive(PackedVector2Array([left_border[i], left_border[j], right_border[j]]), cores, sem_uv)
		draw_primitive(PackedVector2Array([left_border[i], right_border[j], right_border[i]]), cores, sem_uv)
	draw_polyline(_closed(left_border), Color.WHITE, 3.0, true)
	draw_polyline(_closed(right_border), Color.WHITE, 3.0, true)

	# Linha de partida
	var t := Vector2.from_angle(start_rotation)
	var normal := Vector2(-t.y, t.x) * track_width * 0.5
	draw_line(start_position - normal, start_position + normal, Color.YELLOW, 4.0)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	return pts + PackedVector2Array([pts[0]])
