extends RefCounted
class_name TreinoRL
## Regras do treino por reforço (recompensa e fim de episódio) para UM carro.
## Não fala com o Python: o Carro expõe estes valores como propriedades simples
## (rl_*) e quem treina (treino_ppo.py, via py4godot) lê-as com get().

## A ordem faz parte da interface com o Python (MOTIVOS em carro_treino_api.py).
enum Motivo { NENHUM, BATIDA, VOLTA, TEMPO }

## Ticks de física por ação. Tem de ser igual a FRAMES_POR_ACAO em constantes.py.
const FRAMES_POR_ACAO: int = 4
const LIMITE_PASSOS: int = 1600

# Recompensa
const PESO_PROGRESSO: float = 1.0 / 25.0   # por px avançado ao longo da pista
const PESO_VELOCIDADE: float = 0.02        # por passo, a velocidade para a frente de 0 a 1
const PENALIZACAO_BATIDA: float = 5.0
const BONUS_VOLTA: float = 20.0
const MARGEM_PROGRESSO: float = 1.8        # progresso máximo por passo = margem x o que a velocidade máxima permite

var recompensa: float = 0.0
var terminado: bool = false
var motivo: int = Motivo.NENHUM
var progresso_total: float = 0.0
var batidas: int = 0
var passos: int = 0

var _carro: Carro
var _corrida: Corrida
var _obs: ObservacaoRL
var _ultimo_progresso: float = 0.0


func _init(carro: Carro, corrida: Corrida, obs: ObservacaoRL) -> void:
	_carro = carro
	_corrida = corrida
	_obs = obs
	_carro.colidiu.connect(_ao_colidir)


func _ao_colidir(_colisor: Node, _velocidade_kmh: float) -> void:
	batidas += 1


## Nova pista e carro na partida, parado (a física fica congelada até ao 1.º passo).
func reiniciar(seed_: int) -> void:
	_corrida.gerar_pista(seed_)
	_corrida.set_physics_process(false)   # sem relógio nem fim automático da Corrida
	_obs.invalidar()
	_carro.invalidar_observacao()
	passos = 0
	batidas = 0
	progresso_total = 0.0
	recompensa = 0.0
	terminado = false
	motivo = Motivo.NENHUM
	_carro.aplicar_comandos(0.0, 0.0)
	_carro.set_physics_process(false)
	_ultimo_progresso = _obs.localizar(_carro.global_position)["progresso"]


## Chamado depois de FRAMES_POR_ACAO ticks de física com a ação aplicada.
func avaliar() -> void:
	passos += 1
	if terminado:
		recompensa = 0.0
		return

	var comprimento := _obs.comprimento_pista()
	var avanco := _avanco_desde_ultimo_passo(comprimento)
	progresso_total += avanco

	# Velocidade para a frente, de 0 a 1 (a mesma que a rede vê em obs[0]).
	var v_frente: float = clampf(
		_carro.velocity.dot(_carro.transform.x) / maxf(_carro.velocidade_max, 1.0), 0.0, 1.0)

	# Recompensa: avançar na pista + um pouco de velocidade. Não há termo de centragem:
	# a rede aprende a evitar paredes só pela penalização da batida.
	recompensa = avanco * PESO_PROGRESSO + PESO_VELOCIDADE * v_frente

	if batidas > 0:
		recompensa -= PENALIZACAO_BATIDA
		motivo = Motivo.BATIDA
	elif progresso_total >= comprimento:
		recompensa += BONUS_VOLTA
		motivo = Motivo.VOLTA
	elif passos >= LIMITE_PASSOS:
		motivo = Motivo.TEMPO
	terminado = motivo != Motivo.NENHUM
	if terminado:
		_carro.aplicar_comandos(0.0, 0.0)


## Px avançados ao longo da pista desde o último passo (corrige a passagem pela linha de partida
## e limita saltos impossíveis).
func _avanco_desde_ultimo_passo(comprimento: float) -> float:
	var atual: float = _obs.localizar(_carro.global_position)["progresso"]
	var avanco: float = atual - _ultimo_progresso
	if avanco > comprimento * 0.5:
		avanco -= comprimento
	elif avanco < -comprimento * 0.5:
		avanco += comprimento
	_ultimo_progresso = atual
	var limite: float = _carro.velocidade_max * FRAMES_POR_ACAO / 60.0 * MARGEM_PROGRESSO
	return clampf(avanco, -limite, limite)
