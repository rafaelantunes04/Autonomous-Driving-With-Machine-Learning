extends Node2D
class_name Track

const GeometriaCircuito = preload("res://scripts/pista/geometria_pista.gd")

# ============================================================
# CONFIGURAÇÕES DA CORRIDA
# ============================================================

@export_group("Corrida IA")

@export var numero_carros: int = 3 # quantos carros participarão da corrida.

@export var voltas_para_vencer: int = 5 #  voltas para ganhar.

@export var tempo_maximo: float = 270.0 # duração maxima da corrida em segundos

@export var corridas_avaliacao: int = 5 # Quantidade de corridas para comparar os modelos

@export var colisao_entre_carros: bool = false # Define se haverá colisões entre os veículos

@export var pista_aleatoria_por_corrida: bool = true # uma pista diferentes em cada corrida

# ============================================================
# CONFIGURAÇÕES DA PISTA
# ============================================================

@export var track_width := 120.0
@export var num_points := 12
## Raios para 12 pontos (referência). Escalam sozinhos com num_points.
@export var min_radius := 300.0
@export var max_radius := 600.0
@export var car_scene: PackedScene  # arrasta aqui a cena do carro no Inspetor
## Opcional: atribui um Path2D da cena para usar um traçado desenhado no editor.
@export var circuito_manual: Path2D

## Nome do ficheiro Python na raiz do projeto (sem .py) que controla o carro.
## Se não existir, o carro continua a usar as setas (GDScript).
@export var classe_controlador_python := "main"
## Inicia o PPO-MLP ao executar a cena diretamente pelo Godot.
@export var iniciar_ppo_automaticamente: bool = true

# ============================================================
# ESTADO DA PISTA E DA CORRIDA
# ============================================================

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

var corrida_ativa: bool = false
var tempo_corrida: float = 0.0
var vencedor: int = -1

var corrida_atual: int = 1
var pontuacoes: Array[int] = [0, 0, 0]

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
@onready var _ponte_rl = get_node_or_null("PonteRL")

# ============================================================
# INICIALIZAÇÃO E INPUT
# ============================================================

func _ready() -> void:
	seed(Time.get_ticks_usec())
	_gerador = GeradorPista.new(track_width, num_points, min_radius, max_radius)
	get_viewport().size_changed.connect(_fit_camera)
	_hud.continuar_clicado.connect(_iniciar_proxima_corrida)
	if iniciar_ppo_automaticamente and _ponte_rl != null:
		_ponte_rl.iniciar_piloto_local()
	if pista_aleatoria_por_corrida:
		current_seed = randi() % 100000
	generate(current_seed)
	if _ponte_rl != null and _ponte_rl.piloto_local_ativo():
		corrida_ativa = false
		_hud.parar_cronometro()
		for veiculo in carros:
			veiculo.controlo_manual = false


func _unhandled_input(event: InputEvent) -> void:
	if _ponte_rl != null and _ponte_rl.piloto_local_ativo():
		return
	# R = pista nova com uma seed aleatória
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if circuito_manual != null:
			return
		current_seed = randi() % 100000
		print("Seed: ", current_seed)
		generate(current_seed)
	# Enter / Espaço = recomeça na mesma pista
	elif event.is_action_pressed("ui_accept"):
		reiniciar_corrida()



func generate(seed_: int) -> void:
	if pista_aleatoria_por_corrida:
		seed_ = randi() % 100000
	current_seed = seed_

	var linha := PackedVector2Array()
	if circuito_manual != null:
		var curva := circuito_manual.curve
		if curva != null and curva.point_count >= 3:
			for ponto in GeometriaCircuito.amostrar(curva):
				linha.append(to_local(circuito_manual.to_global(ponto)))
		if linha.size() < 3:
			push_warning("O circuito manual precisa de um traçado válido. A usar pista aleatória.")

	centerline = linha if linha.size() >= 3 else _gerador.gerar(seed_)
	if centerline.size() < 3:
		push_error("Erro ao gerar pista!")
		return

	_build()


func definir_numero_corrida(numero: int) -> void:
	corrida_atual = numero
	_hud.atualizar_numero_corrida(corrida_atual)


# ============================================================
# CONTROLE DA CORRIDA
# ============================================================

## Volta a pôr o carro na partida e põe batidas, tempo e voltas a zero.
func reiniciar_corrida() -> void:
	if carros.is_empty():
		return

	corrida_ativa = true
	tempo_corrida = 0.0
	vencedor = -1

	for i in range(carros.size()):
		var novo_carro = carros[i]

		# Distribui os carros ao longo da pista
		var distancia_lateral = 0.0 if i == 0 else (i - 1) * 35.0

		# Pequena diferença longitudinal
		var distancia_frontal = -i * 45.0

		var deslocamento = Vector2(
			distancia_frontal,
			distancia_lateral
		).rotated(start_rotation)

		novo_carro.set_process(true)
		novo_carro.set_physics_process(true)
		for controlador in novo_carro.get_children():
			controlador.set_process(true)
			controlador.set_physics_process(true)

		novo_carro.reiniciar(
			to_global(start_position + deslocamento),
			global_rotation + start_rotation
		)

	# Reinicia as estatísticas de todos os carros
	for stats in estatisticas_carros:
		stats.reiniciar()

	_hud.reiniciar_cronometro()
	_hud.ocultar_resultado()


# ============================================================
# CONSTRUÇÃO DA PISTA
# ============================================================

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
		stats.definir_pista(centerline, self)
	reiniciar_corrida()
	queue_redraw()
	_fit_camera()


# Ponto de partida = primeiro ponto da linha central, virado para o seguinte
func _compute_start() -> void:
	start_position = centerline[0]
	var next := centerline[1 % centerline.size()]
	start_rotation = (next - start_position).angle()


# ============================================================
# CRIAÇÃO E CONFIGURAÇÃO DOS CARROS
# ============================================================

# Cria o carro na primeira vez e liga-o às estatísticas, HUD e câmara
func _garantir_carro() -> void:
	if not carros.is_empty() or car_scene == null:
		return

	# ------------------------------------------------------------
	# 1. INSTANCIAÇÃO DOS CARROS
	# ------------------------------------------------------------

	for i in range(numero_carros):
		var novo_carro := car_scene.instantiate() as Carro

		# Identifica cada participante
		novo_carro.name = "Carro_" + str(i + 1)

		# O controlador externo assume o primeiro carro quando estiver disponível.
		# Os restantes continuam controlados pelas setas.
		novo_carro.controlo_manual = true

		# Carros não colidem entre si,
		# mas continuam colidindo com as paredes

		# Colisão com as paredes e, opcionalmente, entre carros
		novo_carro.collision_layer = 2

		if colisao_entre_carros:
			novo_carro.collision_mask = 1 | 2
		else:
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

	# ------------------------------------------------------------
	# 2. CONFIGURAÇÃO DAS ESTATÍSTICAS
	# ------------------------------------------------------------

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
		stats.volta_concluida.connect(
			_ao_concluir_volta.bind(i)
		)
		estatisticas_carros.append(stats)

	# ------------------------------------------------------------
	# 3. CONFIGURAÇÃO DO HUD E DA CÂMARA
	# ------------------------------------------------------------

	# HUD e câmera continuam acompanhando o primeiro carro
	_hud.configurar_corrida(
		carros,
		estatisticas_carros,
		voltas_para_vencer,
		tempo_maximo,
		corridas_avaliacao
	)

	_camera.alvo = car

	# Liga o controlador Python ao primeiro carro.
	# Se o Python não estiver disponível, o carro continua em modo manual.
	_adicionar_controlador_python()


func _adicionar_controlador_python() -> void:
	if _ponte_rl != null and _ponte_rl.piloto_local_ativo():
		return

	var argumentos := OS.get_cmdline_user_args()
	if argumentos.has("--rl-train") \
			or argumentos.has("--rl-eval") \
			or argumentos.has("--rl-race"):
		return

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
	car.controlo_manual = false
	car.add_child(controlador)
	print("Script Python adicionado ao carro: ", caminho)


# ============================================================
# CÂMARA E DESENHO
# ============================================================

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

# ============================================================
# FIM DA CORRIDA E PRÓXIMA CORRIDA
# ============================================================



func _physics_process(delta: float) -> void:
	if not corrida_ativa:
		return

	tempo_corrida += delta

	# Mostra as observações da IA a cada 60 frames
	if Engine.get_physics_frames() % 60 == 0:
		if not carros.is_empty():
			print("Observacao IA: ", obter_observacao(0))

	if tempo_corrida >= tempo_maximo:
		print("Tempo limite atingido.")
		_finalizar_corrida()


func _ao_concluir_volta(
	numero: int,
	_duracao: float,
	indice_carro: int
) -> void:
	if not corrida_ativa:
		return

	if numero < voltas_para_vencer:
		return

	_finalizar_corrida(indice_carro)

	print(
		"Vencedor: %s" %
		carros[indice_carro].name
	)


func _iniciar_proxima_corrida() -> void:
	if corrida_atual >= corridas_avaliacao:
		get_tree().quit()
		return

	corrida_atual += 1

	if pista_aleatoria_por_corrida:
		current_seed = randi() % 100000

	_hud.ocultar_resultado()
	_hud.atualizar_numero_corrida(corrida_atual)
	generate(current_seed)


func _finalizar_corrida(indice_vencedor: int = -1) -> void:
	if not corrida_ativa:
		return

	corrida_ativa = false
	vencedor = indice_vencedor

	for carro_corrida in carros:
		carro_corrida.set_physics_process(false)

	_hud.parar_cronometro()

	var ordem := _calcular_classificacao()
	var pontos_corrida: Array[int] = [0, 0, 0]
	for posicao in range(ordem.size()):
		pontos_corrida[ordem[posicao]] = maxi(3 - posicao, 1)

	var melhor_carro := _melhor_volta_carro()
	if melhor_carro >= 0:
		pontos_corrida[melhor_carro] += 1

	for i in range(mini(pontuacoes.size(), pontos_corrida.size())):
		pontuacoes[i] += pontos_corrida[i]

	var resumo := "Tempo da corrida: %s\n" % _formatar_tempo(tempo_corrida)
	if melhor_carro >= 0:
		resumo += "Melhor volta: %s (+1 ponto)\n" % carros[melhor_carro].name
	resumo += "CLASSIFICAÇÃO DA CORRIDA %d/%d\n" % [
		corrida_atual, corridas_avaliacao
	]

	for posicao in range(ordem.size()):
		var indice := ordem[posicao]
		resumo += "%d.º %s | +%d pontos | Total: %d | Melhor: %s | Batidas: %d\n" % [
			posicao + 1,
			carros[indice].name,
			pontos_corrida[indice],
			pontuacoes[indice],
			_formatar_tempo(estatisticas_carros[indice].melhor_volta),
			estatisticas_carros[indice].batidas
		]

	var teste_final := corrida_atual >= corridas_avaliacao
	if teste_final:
		var ordem_pontos := _calcular_classificacao_pontos()
		resumo += "\nCLASSIFICAÇÃO FINAL DO TESTE\n"
		for posicao in range(ordem_pontos.size()):
			var indice := ordem_pontos[posicao]
			resumo += "%d.º %s | %d pontos\n" % [
				posicao + 1,
				carros[indice].name,
				pontuacoes[indice]
			]

	_hud.mostrar_painel_resultado(
		"RESULTADO FINAL" if teste_final else "RESULTADO DA CORRIDA",
		"Teste concluído" if teste_final else "Corrida %d concluída" % corrida_atual,
		resumo,
		teste_final
	)


func _calcular_classificacao() -> Array[int]:
	var ordem: Array[int] = []
	for i in range(estatisticas_carros.size()):
		ordem.append(i)

	ordem.sort_custom(
		func(a: int, b: int) -> bool:
			if estatisticas_carros[a].voltas != estatisticas_carros[b].voltas:
				return estatisticas_carros[a].voltas > estatisticas_carros[b].voltas
			var melhor_a := estatisticas_carros[a].melhor_volta
			var melhor_b := estatisticas_carros[b].melhor_volta
			if melhor_a < 0.0:
				return false
			if melhor_b < 0.0:
				return true
			if melhor_a == melhor_b:
				return a < b
			return melhor_a < melhor_b
	)
	return ordem


func _calcular_classificacao_pontos() -> Array[int]:
	var ordem: Array[int] = []
	for i in range(pontuacoes.size()):
		ordem.append(i)
	ordem.sort_custom(
		func(a: int, b: int) -> bool:
			if pontuacoes[a] == pontuacoes[b]:
				return a < b
			return pontuacoes[a] > pontuacoes[b]
	)
	return ordem


func _melhor_volta_carro() -> int:
	var melhor_tempo := INF
	var melhor_carro := -1
	for i in range(estatisticas_carros.size()):
		var tempo := estatisticas_carros[i].melhor_volta
		if tempo >= 0.0 and tempo < melhor_tempo:
			melhor_tempo = tempo
			melhor_carro = i
	return melhor_carro


func _formatar_tempo(tempo: float) -> String:
	if tempo < 0.0:
		return "--:--.---"
	return "%02d:%06.3f" % [int(tempo / 60.0), fmod(tempo, 60.0)]

func finalizar_corrida() -> void:
	if not corrida_ativa:
		return

	corrida_ativa = false

	for carro_corrida in carros:
		carro_corrida.set_physics_process(false)

	_hud.parar_cronometro()

	print("Corrida ", corrida_atual, " encerrada")
	print("Tempo: ", tempo_corrida)

	if vencedor >= 0:
		print("Vencedor: ", carros[vencedor].name)
	else:
		print("Corrida encerrada sem vencedor")


func obter_observacao(indice_carro: int) -> PackedFloat32Array:
	var obs := PackedFloat32Array()

	if indice_carro < 0 or indice_carro >= carros.size():
		return obs

	if centerline.size() < 3:
		return obs

	var veiculo: Carro = carros[indice_carro]
	var posicao: Vector2 = veiculo.position

	var menor_distancia := INF
	var indice_proximo := 0

	# Encontra o ponto central mais próximo
	for i in range(centerline.size()):
		var distancia := posicao.distance_squared_to(centerline[i])

		if distancia < menor_distancia:
			menor_distancia = distancia
			indice_proximo = i

	var n := centerline.size()

	var anterior: Vector2 = centerline[
		(indice_proximo - 1 + n) % n
	]

	var seguinte: Vector2 = centerline[
		(indice_proximo + 1) % n
	]

	var tangente: Vector2 = (seguinte - anterior).normalized()
	var normal: Vector2 = Vector2(-tangente.y, tangente.x)

	var deslocamento: Vector2 = posicao - centerline[indice_proximo]

	# Distância lateral com sinal
	var desvio: float = deslocamento.dot(normal)

	# Diferença de orientação entre carro e pista
	var erro_angulo: float = wrapf(
		veiculo.rotation - tangente.angle(),
		-PI,
		PI
	)

	# Direção de um ponto mais à frente
	var indice_futuro: int = (indice_proximo + 12) % n
	var alvo: Vector2 = centerline[indice_futuro] - posicao

	var angulo_alvo: float = wrapf(
		alvo.angle() - veiculo.rotation,
		-PI,
		PI
	)

	# Seis valores numéricos para a IA
	obs.append(clampf(
		veiculo.velocity.dot(veiculo.transform.x) / veiculo.config.velocidade_max,
		-1.0, 1.0
	))

	obs.append(clampf(desvio / (track_width * 0.5), -3.0, 3.0))
	obs.append(sin(erro_angulo))
	obs.append(cos(erro_angulo))
	obs.append(sin(angulo_alvo))
	obs.append(cos(angulo_alvo))

	return obs
