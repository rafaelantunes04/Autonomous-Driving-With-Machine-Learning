## Orquestra a corrida: cria os carros (Carro.instanciate), liga o HUD e a
## câmara a eles, e trata de reiniciar.
## A geometria da pista vive na Pista (filha desta cena).

extends Node2D
class_name Corrida

@export_group("Corrida IA")

@export var voltas_para_vencer: int = 5 # voltas para ganhar.

@export var tempo_maximo: float = 270.0 # duração máxima da corrida em segundos

@export var corridas_avaliacao: int = 10 # quantidade de corridas para comparar os modelos

## Se os carros se empurram uns aos outros. Precisa de partida_sobreposta = false.
@export var colisao_entre_carros: bool = false

## true = todos partem do mesmo ponto, uns em cima dos outros.
## false = partem em grelha, ligeiramente desfasados.
@export var partida_sobreposta: bool = true

@export var pista_aleatoria_por_corrida: bool = true # ainda não usado: uma pista diferente em cada corrida

# Lista de carros participantes da corrida
var carros: Array[Carro] = []

@onready var _pista: Pista = $Pista
@onready var _camera: CamaraPista = $Camera2D
@onready var _hud: HudCorrida = $HUD


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_camera)
	_pista.pista_alterada.connect(_ao_pista_alterada)

	# Um carro por linha: cor + script que o conduz (ControladorTeclado, ou load("res://main.py"))
	Carro.instanciate(Carro.criar_config(Color.YELLOW, ControladorTeclado, "Amarelo"))
	Carro.instanciate(Carro.criar_config(Color(0.95, 0.27, 0.30), _carregar_controlador("res://main.py"), "Vermelho"))
	Carro.instanciate(Carro.criar_config(Color(0.20, 0.83, 0.49), _carregar_controlador("res://modelo_x.py"), "Verde"))

	_ligar_carros()
	_ao_pista_alterada()


func _carregar_controlador(caminho: String) -> Script:
	if ResourceLoader.exists(caminho):
		return load(caminho) as Script
	return ControladorTeclado


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

	_hud.reiniciar_cronometro()


# ------------------------------------------------------------------ Interno

## A pista mudou (nova seed, Path2D editado): atualiza as estatísticas e recomeça.
func _ao_pista_alterada() -> void:
	for carro in carros:
		carro.estatisticas.definir_pista(_pista.centerline, _pista)
	reiniciar_corrida()
	_fit_camera()


## Posição do carro i na partida, relativa ao ponto de partida da Pista.
func _deslocamento_partida(i: int) -> Vector2:
	if partida_sobreposta:
		return Vector2.ZERO
	var lateral := (i - (carros.size() - 1) * 0.5) * 35.0
	var frontal := -i * 45.0
	return Vector2(frontal, lateral).rotated(_pista.start_rotation)


## Regras da corrida que se aplicam a todos os carros, mais HUD e câmara.
func _ligar_carros() -> void:
	if colisao_entre_carros and partida_sobreposta:
		push_warning("Corrida: com colisao_entre_carros ligado, desliga partida_sobreposta (os carros sobrepostos seriam empurrados).")

	carros.assign(get_tree().get_nodes_in_group(Carro.GRUPO))
	if carros.is_empty():
		push_error("Corrida: não há carros. Cria-os no _ready com Carro.instanciate().")
		return

	var nomes: Array[String] = []
	var cores: Array[Color] = []
	var estatisticas: Array[EstatisticasCorrida] = []

	for carro in carros:
		carro.permitir_colisao_entre_carros(colisao_entre_carros)
		nomes.append(carro.nome_exibicao)
		cores.append(carro.cor)
		estatisticas.append(carro.estatisticas)

	_hud.configurar_corrida(carros, estatisticas, voltas_para_vencer,
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
