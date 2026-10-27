extends Node
class_name EstatisticasCorrida

## Conta batidas nas paredes, tempo e voltas. reiniciar() põe tudo a zero.
##
## - O tempo conta em tempo de física (não depende dos FPS nem do time_scale)
##   e só começa a correr quando o carro se mexe pela primeira vez.
## - Só conta batidas em corpos do grupo "paredes" (a Track põe lá as Walls).
## - Uma volta fica completa quando o progresso líquido ao longo da linha
##   central chega a uma volta inteira (marcha-atrás desconta).

signal batida_registada(total: int)
signal volta_concluida(numero: int, tempo: float)

@export var intervalo_min_batidas: float = 0.25  # s; evita contar 2x o mesmo raspão
@export var velocidade_min_batida: float = 3.0   # km/h; encostos mais lentos não contam
@export var janela_procura: int = 25             # pontos da linha central à volta do último

var batidas: int = 0
var tempo: float = 0.0
var voltas: int = 0
var ultima_volta: float = -1.0   # -1 = ainda não há
var melhor_volta: float = -1.0
var a_correr: bool = false

var _carro: Carro
var _linha := PackedVector2Array()
var _indice: int = 0
var _progresso: int = 0
var _inicio_volta: float = 0.0
var _tempo_ultima_batida: float = -INF


## Liga-se ao carro e passa a ouvir as suas colisões.
func configurar(carro: Carro) -> void:
	_carro = carro
	_carro.colidiu.connect(_ao_colidir)


## Linha central em coordenadas da Track (o carro é filho da Track).
func definir_pista(linha: PackedVector2Array) -> void:
	_linha = linha


## Põe batidas, tempo e voltas a zero.
func reiniciar() -> void:
	batidas = 0
	tempo = 0.0
	voltas = 0
	ultima_volta = -1.0
	melhor_volta = -1.0
	a_correr = false
	_indice = 0
	_progresso = 0
	_inicio_volta = 0.0
	_tempo_ultima_batida = -INF


func _physics_process(delta: float) -> void:
	if _carro == null or _linha.is_empty():
		return
	if not a_correr:
		if _carro.velocity.length() <= 1.0:
			return
		a_correr = true
	tempo += delta
	_atualizar_progresso()


## Conta uma batida se for numa parede, rápida o bastante e não repetida demasiado depressa.
func _ao_colidir(colisor: Node, velocidade_kmh: float) -> void:
	if colisor == null or not colisor.is_in_group("paredes"):
		return
	if velocidade_kmh < velocidade_min_batida:
		return
	if tempo - _tempo_ultima_batida < intervalo_min_batidas:
		return
	_tempo_ultima_batida = tempo
	batidas += 1
	print("Batida #%d em %s | %d km/h | t = %.2f s" % [batidas, colisor.name, int(velocidade_kmh), tempo])
	batida_registada.emit(batidas)


## Atualiza o progresso ao longo da linha central e conta a volta quando chega a uma volta inteira.
func _atualizar_progresso() -> void:
	var n := _linha.size()
	var meio := int(n * 0.5)

	# Ponto da linha central mais próximo, procurando só perto do anterior
	var melhor := _indice
	var melhor_d := INF
	for k in range(-janela_procura, janela_procura + 1):
		var i := posmod(_indice + k, n)
		var d := _carro.position.distance_squared_to(_linha[i])
		if d < melhor_d:
			melhor_d = d
			melhor = i

	# Diferença com sinal (em índices), tratando a volta à linha de partida
	var passo := posmod(melhor - _indice + meio, n) - meio
	_indice = melhor
	_progresso = maxi(_progresso + passo, -n)

	if _progresso >= n:
		_progresso -= n
		_concluir_volta()


## Regista a volta terminada e atualiza última/melhor volta.
func _concluir_volta() -> void:
	voltas += 1
	var duracao := tempo - _inicio_volta
	_inicio_volta = tempo
	ultima_volta = duracao
	if melhor_volta < 0.0 or duracao < melhor_volta:
		melhor_volta = duracao
	print("Volta %d concluída em %.2f s (batidas até agora: %d)" % [voltas, duracao, batidas])
	volta_concluida.emit(voltas, duracao)
