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

## true = cada corrida do campeonato usa uma pista nova.
@export var pista_aleatoria_por_corrida: bool = true

## Modo treino: um só carro, conduzido por treino_ppo.py, sem regras de corrida.
## Usa a cena cenas/treino.tscn.
@export var modo_treino: bool = false
## Velocidade da simulação no modo treino (1 = tempo real).
@export var velocidade_treino: float = 20.0

# Lista de carros participantes da corrida
var carros: Array[Carro] = []

# Estado do campeonato
var corrida_ativa: bool = false
var tempo_corrida: float = 0.0
var vencedor: int = -1
var corrida_atual: int = 1
var pontuacoes: Array[int] = []

@onready var _pista: Pista = $Pista
@onready var _camera: CamaraPista = $Camera2D
@onready var _hud: HudCorrida = $HUD


func _ready() -> void:
	seed(Time.get_ticks_usec())
	get_viewport().size_changed.connect(_fit_camera)
	_pista.pista_alterada.connect(_ao_pista_alterada)
	_hud.continuar_clicado.connect(_iniciar_proxima_corrida)

	if modo_treino:
		_iniciar_treino()
		return

	# Um carro por linha: cor + script que o conduz (ControladorTeclado, ou load("res://main.py"))
	Carro.instanciate(Color.YELLOW, ControladorTeclado, "Amarelo")
	Carro.instanciate(Color(0.95, 0.27, 0.30), load("res://modelo_x.py"), "Vermelho")
	Carro.instanciate(Color(0.20, 0.83, 0.49), load("res://corrida_ppo.py"), "Verde")

	_ligar_carros()
	_ao_pista_alterada()



func _iniciar_treino() -> void:
	set_physics_process(false)   # sem relógio nem fim automático da corrida
	Engine.time_scale = velocidade_treino
	Engine.max_physics_steps_per_frame = 64
	Engine.max_fps = 0
	Carro.instanciate(Color(0.20, 0.83, 0.49), load("res://treino_ppo.py"), "Treino")
	_ligar_carros()
	_ao_pista_alterada()
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if modo_treino:
		return
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


func _physics_process(delta: float) -> void:
	if not corrida_ativa:
		return

	tempo_corrida += delta
	if tempo_corrida >= tempo_maximo:
		print("Tempo limite atingido.")
		_finalizar_corrida()


## Volta a pôr os carros na partida e põe batidas, tempo e voltas a zero.
func reiniciar_corrida() -> void:
	if carros.is_empty():
		return

	corrida_ativa = true
	tempo_corrida = 0.0
	vencedor = -1

	for i in carros.size():
		carros[i].ativar(true)
		carros[i].reiniciar(
			_pista.to_global(_pista.start_position + _deslocamento_partida(i)),
			_pista.global_rotation + _pista.start_rotation)

	_hud.reiniciar_cronometro()
	_hud.ocultar_resultado()


## Gera uma pista nova já (a pista é reconstruída e os carros voltam à partida
## antes de a função devolver). Com pista_aleatoria_por_corrida a seed é sorteada.
func gerar_pista(seed_: int) -> void:
	if pista_aleatoria_por_corrida:
		seed_ = randi() % 100000
	if _pista.usa_path_manual():
		reiniciar_corrida()   # a pista vem de um Path2D: não há pista nova, só recomeça
		return
	_pista.gerar_agora(seed_)


func definir_numero_corrida(numero: int) -> void:
	corrida_atual = numero
	_hud.atualizar_numero_corrida(corrida_atual)


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
	carros.assign(get_tree().get_nodes_in_group(Carro.GRUPO))
	pontuacoes.resize(carros.size())
	pontuacoes.fill(0)

	for i in carros.size():
		carros[i].permitir_colisao_entre_carros(colisao_entre_carros)
		carros[i].estatisticas.volta_concluida.connect(_ao_concluir_volta.bind(i))

	_hud.configurar_corrida(
		carros,
		voltas_para_vencer,
		tempo_maximo,
		corridas_avaliacao
	)

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


# ------------------------------------------------------------------ Campeonato

func _ao_concluir_volta(numero: int, _duracao: float, indice_carro: int) -> void:
	if not corrida_ativa or numero < voltas_para_vencer:
		return
	print("Vencedor: %s" % carros[indice_carro].nome)
	_finalizar_corrida(indice_carro)


## Botão "Continuar" do painel de resultado: próxima corrida, ou fecha no fim do teste.
func _iniciar_proxima_corrida() -> void:
	if corrida_atual >= corridas_avaliacao:
		get_tree().quit()
		return

	corrida_atual += 1
	_hud.atualizar_numero_corrida(corrida_atual)
	gerar_pista(_pista.semente)   # reinicia a corrida e esconde o painel


func _finalizar_corrida(indice_vencedor: int = -1) -> void:
	if not corrida_ativa:
		return

	corrida_ativa = false
	vencedor = indice_vencedor

	for carro in carros:
		carro.ativar(false)

	_hud.parar_cronometro()

	# Pontos: 1.º = N, 2.º = N-1, ... (mínimo 1) + 1 ponto pela melhor volta
	var ordem := _calcular_classificacao()
	var pontos_corrida: Array[int] = []
	pontos_corrida.resize(carros.size())
	pontos_corrida.fill(0)
	for posicao in ordem.size():
		pontos_corrida[ordem[posicao]] = maxi(carros.size() - posicao, 1)

	var melhor_carro := _melhor_volta_carro()
	if melhor_carro >= 0:
		pontos_corrida[melhor_carro] += 1

	for i in carros.size():
		pontuacoes[i] += pontos_corrida[i]

	var resumo := "Tempo da corrida: %s\n" % _formatar_tempo(tempo_corrida)
	if melhor_carro >= 0:
		resumo += "Melhor volta: %s (+1 ponto)\n" % carros[melhor_carro].nome
	resumo += "CLASSIFICAÇÃO DA CORRIDA %d/%d\n" % [corrida_atual, corridas_avaliacao]

	for posicao in ordem.size():
		var indice := ordem[posicao]
		var stats := carros[indice].estatisticas
		resumo += "%d.º %s | +%d pontos | Total: %d | Melhor: %s | Batidas: %d\n" % [
			posicao + 1,
			carros[indice].nome,
			pontos_corrida[indice],
			pontuacoes[indice],
			_formatar_tempo(stats.melhor_volta),
			stats.batidas
		]

	var teste_final := corrida_atual >= corridas_avaliacao
	if teste_final:
		var ordem_pontos := _calcular_classificacao_pontos()
		resumo += "\nCLASSIFICAÇÃO FINAL DO TESTE\n"
		for posicao in ordem_pontos.size():
			var indice := ordem_pontos[posicao]
			resumo += "%d.º %s | %d pontos\n" % [
				posicao + 1,
				carros[indice].nome,
				pontuacoes[indice]
			]

	_hud.mostrar_painel_resultado(
		"RESULTADO FINAL" if teste_final else "RESULTADO DA CORRIDA",
		"Teste concluído" if teste_final else "Corrida %d concluída" % corrida_atual,
		resumo,
		teste_final
	)


## Índices dos carros por ordem: mais voltas primeiro, depois melhor volta.
func _calcular_classificacao() -> Array[int]:
	var ordem: Array[int] = []
	for i in carros.size():
		ordem.append(i)

	ordem.sort_custom(
		func(a: int, b: int) -> bool:
			var stats_a := carros[a].estatisticas
			var stats_b := carros[b].estatisticas
			if stats_a.voltas != stats_b.voltas:
				return stats_a.voltas > stats_b.voltas
			if stats_a.melhor_volta < 0.0:
				return false
			if stats_b.melhor_volta < 0.0:
				return true
			if stats_a.melhor_volta == stats_b.melhor_volta:
				return a < b
			return stats_a.melhor_volta < stats_b.melhor_volta
	)
	return ordem


## Índices dos carros por ordem de pontos acumulados no campeonato.
func _calcular_classificacao_pontos() -> Array[int]:
	var ordem: Array[int] = []
	for i in carros.size():
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
	for i in carros.size():
		var tempo := carros[i].estatisticas.melhor_volta
		if tempo >= 0.0 and tempo < melhor_tempo:
			melhor_tempo = tempo
			melhor_carro = i
	return melhor_carro


func _formatar_tempo(tempo: float) -> String:
	if tempo < 0.0:
		return "--:--.---"
	return "%02d:%06.3f" % [int(tempo / 60.0), fmod(tempo, 60.0)]
