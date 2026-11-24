extends Node2D
class_name Corrida


@export_group("Regras")
@export var voltas_para_vencer: int = 5
@export var tempo_maximo: float = 270.0
@export var corridas_avaliacao: int = 10


@export_group("Carros e pista")

## Colisões entre carros. Requer partida_sobreposta = false.
@export var colisao_entre_carros: bool = false

## Todos os carros partem do mesmo ponto.
@export var partida_sobreposta: bool = true

## Cada corrida do campeonato usa uma pista nova.
@export var pista_aleatoria_por_corrida: bool = true


@export_group("Modelos na corrida")

## Acrescenta um carro SAC à corrida.
@export var demonstrar_sac: bool = false

## Acrescenta um carro PPO-LSTM à corrida.
@export var demonstrar_ppo_lstm: bool = false


@export_group("Avaliação automática")
@export var modo_avaliacao: bool = false
## Zero usa todas as pistas; um valor positivo permite um teste rápido.
@export var avaliacao_limite_pistas: int = 0
@export_enum("validacao", "teste") var conjunto_avaliacao: String = "validacao"

@export_group("Treino")

## Um único carro, controlado pela ponte Python de treino.
## Também pode ser ativado pelo argumento -- --treino.
@export var modo_treino: bool = false

@export_enum("ppo_mlp", "sac_mlp", "ppo_lstm")
var modelo_treino: String = "ppo_mlp"

@export var treino_passos: int = 100000
@export var treino_continuar: bool = false
@export var treino_seed: int = 42

## Guarda a cada N episódios. Zero guarda apenas no fim.
@export var treino_guardar_cada: int = 100

@export_enum("auto", "cpu", "cuda")
var treino_dispositivo: String = "auto"

## Velocidade da simulação: 1 = tempo real.
@export var velocidade_treino: float = 20.0


const ESPACO_LATERAL_GRELHA := 35.0
const ESPACO_FRONTAL_GRELHA := 45.0

var carros: Array[Carro] = []

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

	if "--treino" in OS.get_cmdline_user_args():
		modo_treino = true

	if modo_treino or modo_avaliacao:
		_iniciar_treino()
		return

	# Carro manual.
	Carro.instanciate(
		Color.YELLOW,
		ControladorTeclado,
		"Manual"
	)

	# PPO sem memória.
	Carro.instanciate(
		Color(0.20, 0.83, 0.49),
		load("res://ml/controladores/corrida_ppo.py"),
		"PPO"
	)

	# SAC: apenas um carro.
	if demonstrar_sac:
		Carro.instanciate(
			Color.CYAN,
			load("res://ml/controladores/corrida_sac.py"),
			"SAC"
		)

	# PPO com memória LSTM.
	if demonstrar_ppo_lstm:
		Carro.instanciate(
			Color.MAGENTA,
			load("res://ml/controladores/corrida_ppo_lstm.py"),
			"PPO-LSTM"
		)

	_arrancar()


func _iniciar_treino() -> void:
	if modo_avaliacao and _pista.usa_path_manual():
		push_error("Avaliação automática requer pistas geradas pelas seeds reservadas.")
		get_tree().quit(1)
		return
	set_physics_process(false)

	# Mantém o passo físico de 1/60 s ao acelerar a simulação.
	var escala := maxf(1.0, velocidade_treino)
	Engine.physics_ticks_per_second = int(round(60.0 * escala))
	Engine.time_scale = Engine.physics_ticks_per_second / 60.0
	Engine.max_physics_steps_per_frame = 64
	Engine.max_fps = 0

	var cor_treino: Color = Color(0.20, 0.83, 0.49)

	match modelo_treino:
		"sac_mlp":
			cor_treino = Color.CYAN
		"ppo_lstm":
			cor_treino = Color.MAGENTA

	# treino_ppo.py é a ponte comum aos três algoritmos.
	Carro.instanciate(
		cor_treino,
		load("res://ml/controladores/treino_ppo.py"),
		"Avaliação " + conjunto_avaliacao if modo_avaliacao else "Treino " + modelo_treino
	)

	_arrancar()

	# reiniciar_corrida() volta a ligar este processamento.
	# Durante o treino, os episódios são geridos pelo TreinoRL.
	set_physics_process(false)


## Liga os carros à corrida e coloca-os na partida.
func _arrancar() -> void:
	_ligar_carros()
	_ao_pista_alterada()


func _unhandled_input(event: InputEvent) -> void:
	if modo_treino or modo_avaliacao:
		return

	# R: gerar uma pista nova.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if _pista.usa_path_manual():
			print("A pista vem de um Path2D: a tecla R não gera pista nova.")
			return

		var seed_ := randi() % 100000
		print("Seed: ", seed_)
		_pista.gerar(seed_)

	# Enter / Espaço: reiniciar na mesma pista.
	elif event.is_action_pressed("ui_accept"):
		reiniciar_corrida()


func _physics_process(delta: float) -> void:
	if not corrida_ativa:
		return

	tempo_corrida += delta

	if tempo_corrida >= tempo_maximo:
		print("Tempo limite atingido.")
		_finalizar_corrida()


## Reinicia os carros e as estatísticas da corrida atual.
func reiniciar_corrida() -> void:
	if carros.is_empty():
		return

	corrida_ativa = true
	tempo_corrida = 0.0
	vencedor = -1

	for i in carros.size():
		carros[i].ativar(true)
		carros[i].reiniciar(
			_pista.to_global(
				_pista.posicao_partida + _deslocamento_partida(i)
			),
			_pista.global_rotation + _pista.rotacao_partida
		)

	_hud.reiniciar_cronometro()
	_hud.ocultar_resultado()


## Uma seed explícita é respeitada; um valor negativo sorteia uma seed.
func gerar_pista(seed_: int = -1) -> void:
	if seed_ < 0:
		seed_ = randi() % 100000

	if _pista.usa_path_manual():
		reiniciar_corrida()
		return

	_pista.gerar(seed_, true)


func definir_numero_corrida(numero: int) -> void:
	corrida_atual = numero
	_hud.atualizar_numero_corrida(corrida_atual)


# ------------------------------------------------------------------ Pista


## Atualiza as estatísticas e reinicia quando a pista muda.
func _ao_pista_alterada() -> void:
	for carro in carros:
		carro.estatisticas.definir_pista(
			_pista.linha_central,
			_pista
		)

	reiniciar_corrida()
	_fit_camera()


## Deslocamento do carro na grelha de partida.
func _deslocamento_partida(i: int) -> Vector2:
	if partida_sobreposta:
		return Vector2.ZERO

	var lateral := (
		(i - (carros.size() - 1) * 0.5)
		* ESPACO_LATERAL_GRELHA
	)
	var frontal := -i * ESPACO_FRONTAL_GRELHA

	return Vector2(frontal, lateral).rotated(
		_pista.rotacao_partida
	)


## Liga os carros às regras, ao HUD e à câmara.
func _ligar_carros() -> void:
	carros.assign(get_tree().get_nodes_in_group(Carro.GRUPO))

	pontuacoes.resize(carros.size())
	pontuacoes.fill(0)

	for i in carros.size():
		carros[i].permitir_colisao_entre_carros(
			colisao_entre_carros
		)
		carros[i].estatisticas.volta_concluida.connect(
			_ao_concluir_volta.bind(i)
		)

	_hud.configurar_corrida(
		carros,
		voltas_para_vencer,
		tempo_maximo,
		corridas_avaliacao
	)

	if not carros.is_empty():
		_camera.alvo = carros[0]


## Ajusta a câmara para mostrar toda a pista.
func _fit_camera() -> void:
	var linha := _pista.linha_central

	if linha.is_empty():
		return

	var rect := Rect2(linha[0], Vector2.ZERO)

	for p in linha:
		rect = rect.expand(p)

	rect = rect.grow(_pista.largura)

	var ratio := get_viewport_rect().size / rect.size

	_camera.definir_vista_geral(
		_pista.to_global(rect.get_center()),
		Vector2.ONE * minf(ratio.x, ratio.y)
	)


# ------------------------------------------------------------------ Campeonato


func _ao_concluir_volta(
	numero: int,
	_duracao: float,
	indice_carro: int
) -> void:
	if not corrida_ativa or numero < voltas_para_vencer:
		return

	print("Vencedor: %s" % carros[indice_carro].nome)
	_finalizar_corrida(indice_carro)


## Avança para a corrida seguinte ou fecha no fim do campeonato.
func _iniciar_proxima_corrida() -> void:
	if corrida_atual >= corridas_avaliacao:
		get_tree().quit()
		return

	corrida_atual += 1
	_hud.atualizar_numero_corrida(corrida_atual)

	gerar_pista(
		-1 if pista_aleatoria_por_corrida else _pista.semente
	)


func _finalizar_corrida(indice_vencedor: int = -1) -> void:
	if not corrida_ativa:
		return

	corrida_ativa = false
	vencedor = indice_vencedor

	for carro in carros:
		carro.ativar(false)

	_hud.parar_cronometro()

	var ordem := _indices_ordenados(_vem_antes_na_corrida)
	var melhor_carro := _melhor_volta_carro()
	var pontos_corrida := _pontos_da_corrida(
		ordem,
		melhor_carro
	)

	for i in carros.size():
		pontuacoes[i] += pontos_corrida[i]

	var teste_final := corrida_atual >= corridas_avaliacao

	_hud.mostrar_painel_resultado(
		"RESULTADO FINAL" if teste_final else "RESULTADO DA CORRIDA",
		"Teste concluído" if teste_final else "Corrida %d concluída" % corrida_atual,
		_resumo_da_corrida(
			ordem,
			pontos_corrida,
			melhor_carro,
			teste_final
		),
		teste_final
	)


## Pontos: N para o primeiro, até 1 para o último.
## Acrescenta um ponto pela melhor volta.
func _pontos_da_corrida(
	ordem: Array[int],
	melhor_carro: int
) -> Array[int]:
	var pontos: Array[int] = []
	pontos.resize(carros.size())
	pontos.fill(0)

	for posicao in ordem.size():
		pontos[ordem[posicao]] = maxi(
			carros.size() - posicao,
			1
		)

	if melhor_carro >= 0:
		pontos[melhor_carro] += 1

	return pontos


## Texto apresentado no painel de resultados.
func _resumo_da_corrida(
	ordem: Array[int],
	pontos_corrida: Array[int],
	melhor_carro: int,
	teste_final: bool
) -> String:
	var resumo := "Tempo da corrida: %s\n" % (
		EstatisticasCorrida.formatar_tempo(tempo_corrida)
	)

	if melhor_carro >= 0:
		resumo += "Melhor volta: %s (+1 ponto)\n" % (
			carros[melhor_carro].nome
		)

	resumo += "CLASSIFICAÇÃO DA CORRIDA %d/%d\n" % [
		corrida_atual,
		corridas_avaliacao
	]

	for posicao in ordem.size():
		var indice := ordem[posicao]
		var stats := carros[indice].estatisticas

		resumo += "%d.º %s | +%d pontos | Total: %d | Melhor: %s | Batidas: %d\n" % [
			posicao + 1,
			carros[indice].nome,
			pontos_corrida[indice],
			pontuacoes[indice],
			EstatisticasCorrida.formatar_tempo(stats.melhor_volta),
			stats.batidas
		]

	if teste_final:
		resumo += "\nCLASSIFICAÇÃO FINAL DO TESTE\n"

		var ordem_pontos := _indices_ordenados(
			_vem_antes_nos_pontos
		)

		for posicao in ordem_pontos.size():
			var indice := ordem_pontos[posicao]

			resumo += "%d.º %s | %d pontos\n" % [
				posicao + 1,
				carros[indice].nome,
				pontuacoes[indice]
			]

	return resumo


## Ordena os índices dos carros com a função recebida.
func _indices_ordenados(vem_antes: Callable) -> Array[int]:
	var ordem: Array[int] = []

	for i in carros.size():
		ordem.append(i)

	ordem.sort_custom(vem_antes)
	return ordem


## Mais voltas primeiro; em empate, melhor tempo de volta.
func _vem_antes_na_corrida(a: int, b: int) -> bool:
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


## Classificação do campeonato por pontos acumulados.
func _vem_antes_nos_pontos(a: int, b: int) -> bool:
	if pontuacoes[a] == pontuacoes[b]:
		return a < b

	return pontuacoes[a] > pontuacoes[b]


## Devolve o índice do carro com a melhor volta válida.
func _melhor_volta_carro() -> int:
	var melhor_tempo := INF
	var melhor_carro := -1

	for i in carros.size():
		var tempo := carros[i].estatisticas.melhor_volta

		if tempo >= 0.0 and tempo < melhor_tempo:
			melhor_tempo = tempo
			melhor_carro = i

	return melhor_carro
