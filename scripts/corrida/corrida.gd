
## Orquestra a corrida: cria os carros a partir dos participantes, liga-lhes os
## controladores, as estatísticas, o HUD e a câmara, e trata de reiniciar.
## A geometria da pista vive na Pista (filha desta cena).

extends Node2D
class_name Corrida

const CAMADA_PAREDES := 1
const CAMADA_CARROS := 2

@export_group("Corrida IA")

## Quem corre. Vazio = 3 carros controlados pelo teclado (para testar).
@export var participantes: Array[ParticipanteConfig] = []

@export var voltas_para_vencer: int = 5 # voltas para ganhar.

@export var tempo_maximo: float = 270.0 # duração máxima da corrida em segundos

@export var corridas_avaliacao: int = 10 # quantidade de corridas para comparar os modelos

## Se os carros se empurram uns aos outros. Precisa de partida_sobreposta = false.
@export var colisao_entre_carros: bool = false

## true = todos partem do mesmo ponto, uns em cima dos outros.
## false = partem em grelha, ligeiramente desfasados.
@export var partida_sobreposta: bool = true

@export var pista_aleatoria_por_corrida: bool = true # ainda não usado: uma pista diferente em cada corrida

@export var car_scene: PackedScene  # arrasta aqui a cena do carro no Inspetor

# Lista de carros participantes da corrida
var carros: Array[Carro] = []

# Estatísticas individuais dos carros
var estatisticas_carros: Array[EstatisticasCorrida] = []

@onready var _pista: Pista = $Pista
@onready var _camera: CamaraPista = $Camera2D
@onready var _stats: EstatisticasCorrida = $Estatisticas
@onready var _hud: HudCorrida = $HUD


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_camera)
	_pista.pista_alterada.connect(_ao_pista_alterada)
	_criar_carros()
	_ao_pista_alterada()


func _unhandled_input(event: InputEvent) -> void:
	# R = pista nova com uma seed aleatória
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if _pista.usa_path_manual():
			print("A pista vem de um Path2D: a tecla R não gera pista nova.")
			return
		var seed_ := randi() % 100000
		print("Seed: ", seed_)
		_pista.gerar(seed_)
	# Enter / Espaço = recomeça na mesma pista
	elif event.is_action_pressed("ui_accept"):
		reiniciar_corrida()


## Volta a pôr os carros na partida e põe batidas, tempo e voltas a zero.
func reiniciar_corrida() -> void:
	if carros.is_empty():
		return

	for i in carros.size():
		carros[i].reiniciar(
			_pista.to_global(_pista.start_position + _deslocamento_partida(i)),
			_pista.global_rotation + _pista.start_rotation)

	for stats in estatisticas_carros:
		stats.reiniciar()

	_hud.reiniciar_cronometro()


# ------------------------------------------------------------------ Interno

## A pista mudou (nova seed, Path2D editado): atualiza as estatísticas e recomeça.
func _ao_pista_alterada() -> void:
	for stats in estatisticas_carros:
		stats.definir_pista(_pista.centerline, _pista)
	reiniciar_corrida()
	_fit_camera()


## Posição do carro i na partida, relativa ao ponto de partida da Pista.
func _deslocamento_partida(i: int) -> Vector2:
	if partida_sobreposta:
		return Vector2.ZERO
	var lateral := (i - (carros.size() - 1) * 0.5) * 35.0
	var frontal := -i * 45.0
	return Vector2(frontal, lateral).rotated(_pista.start_rotation)


func _participantes_por_omissao() -> Array[ParticipanteConfig]:
	var cores: Array[Color] = [
		Color(0.25, 0.59, 1.0),
		Color(0.95, 0.27, 0.30),
		Color(0.20, 0.83, 0.49),
	]
	var lista: Array[ParticipanteConfig] = []
	for i in cores.size():
		var p := ParticipanteConfig.new()
		p.nome = "Carro %d" % (i + 1)
		p.cor = cores[i]
		p.controlador = preload("res://scripts/carro/controlador_teclado.gd")
		lista.append(p)
	return lista


## Cria um carro por participante e liga-o às estatísticas, HUD e câmara.
func _criar_carros() -> void:
	if car_scene == null:
		push_error("Corrida: falta atribuir car_scene.")
		return
	if colisao_entre_carros and partida_sobreposta:
		push_warning("Corrida: com colisao_entre_carros ligado, desliga partida_sobreposta (os carros sobrepostos seriam empurrados).")

	var lista: Array[ParticipanteConfig] = participantes if not participantes.is_empty() else _participantes_por_omissao()
	var nomes: Array[String] = []
	var cores: Array[Color] = []

	for i in lista.size():
		var p := lista[i]
		var carro := car_scene.instantiate() as Carro
		carro.name = "Carro_%d" % (i + 1)
		if p.config != null:
			carro.config = p.config.duplicate() as CarroConfig   # cópia própria de cada carro

		# Por omissão os carros só colidem com as paredes
		carro.collision_layer = CAMADA_CARROS
		carro.collision_mask = CAMADA_PAREDES | (CAMADA_CARROS if colisao_entre_carros else 0)
		carro.modulate = p.cor
		carro.z_index = lista.size() - i   # o primeiro (o que a câmara segue) fica por cima
		add_child(carro)
		carros.append(carro)

		var modelo := ""
		if p.controlador != null:
			var controlador := Node.new()
			controlador.name = "Controlador"
			controlador.set_script(p.controlador)
			carro.add_child(controlador)
			var nome_modelo = controlador.get("nome_modelo")   # null se o script não tiver
			if nome_modelo is String:
				modelo = nome_modelo

		var nome: String = p.nome if not p.nome.is_empty() else String(carro.name)
		nomes.append(nome if modelo.is_empty() else "%s (%s)" % [nome, modelo])
		cores.append(p.cor)
		print("Criado: ", carro.name)

	# Estatísticas individuais: o primeiro carro usa o nó da cena, os outros ganham um novo
	for i in carros.size():
		var stats: EstatisticasCorrida
		if i == 0:
			stats = _stats
		else:
			stats = EstatisticasCorrida.new()
			stats.name = "Estatisticas_Carro_%d" % (i + 1)
			add_child(stats)
		stats.configurar(carros[i])
		estatisticas_carros.append(stats)

	_hud.configurar_corrida(carros, estatisticas_carros, voltas_para_vencer,
			tempo_maximo, corridas_avaliacao, nomes, cores)

	# A câmara acompanha o primeiro carro
	_camera.alvo = carros[0]


# Centra a câmara na pista e ajusta o zoom para caber toda no ecrã
func _fit_camera() -> void:
	var linha := _pista.centerline
	if linha.is_empty():
		return
	var rect := Rect2(linha[0], Vector2.ZERO)
	for p in linha:
		rect = rect.expand(p)
	rect = rect.grow(_pista.largura)
	var ratio := get_viewport_rect().size / rect.size
	_camera.definir_vista_geral(_pista.to_global(rect.get_center()), Vector2.ONE * minf(ratio.x, ratio.y))
