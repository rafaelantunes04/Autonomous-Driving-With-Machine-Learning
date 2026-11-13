extends RefCounted
class_name TreinoRL
## Regras do treino por reforço (recompensa e fim de episódio) para UM carro.
## Não fala com o Python: o Carro expõe estes valores como propriedades simples
## (rl_*) e quem treina (treino_ppo.py, via py4godot) lê-as com get().

enum Motivo { NENHUM, BATIDA, FORA_DA_PISTA, VOLTA, TEMPO }

const FRAMES_POR_ACAO: int = 1
const LIMITE_PASSOS: int = 1600

var recompensa: float = 0.0
var terminado: bool = false
var motivo: int = Motivo.NENHUM
var progresso_total: float = 0.0
var batidas: int = 0
var passos: int = 0

var _carro: Carro
var _corrida: Corrida
var _pista: Pista
var _obs: ObservacaoRL
var _ultimo_progresso: float = 0.0


func _init(carro: Carro, corrida: Corrida, pista: Pista, obs: ObservacaoRL) -> void:
	_carro = carro
	_corrida = corrida
	_pista = pista
	_obs = obs
	_carro.colidiu.connect(_ao_colidir)


func comprimento() -> float:
	_obs.localizar(Vector2.ZERO)   # garante que o comprimento está calculado
	return _obs.comprimento


func _ao_colidir(_colisor: Node, _velocidade_kmh: float) -> void:
	batidas += 1


## Nova pista e carro na partida, parado (a física fica congelada até ao 1.º passo).
func reiniciar(seed_: int) -> void:
	_corrida.gerar_pista(seed_)
	_corrida.set_physics_process(false)   # sem relógio nem fim automático da Corrida
	_obs.invalidar()
	_carro._obs_tick = -1
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

	var comp := comprimento()
	var atual: float = _obs.localizar(_carro.global_position)["progresso"]
	var delta: float = atual - _ultimo_progresso
	if delta > comp * 0.5:
		delta -= comp
	elif delta < -comp * 0.5:
		delta += comp
	_ultimo_progresso = atual
	var limite: float = _carro.velocidade_max * FRAMES_POR_ACAO / 60.0 * 1.8
	delta = clampf(delta, -limite, limite)
	progresso_total += delta

	# Velocidade para a frente, de 0 a 1 (a mesma que a rede vê em obs[0]).
	var v_frente: float = clampf(
		_carro.velocity.dot(_carro.transform.x) / maxf(_carro.velocidade_max, 1.0), 0.0, 1.0)

	# Recompensa: avançar na pista (menos distância até ao fim) + um pouco de velocidade.
	# Não há termo de centragem: a rede aprende a evitar paredes só pela penalização da batida.
	recompensa = delta / 25.0 + 0.02 * v_frente

	if batidas > 0:
		recompensa -= 5.0
		motivo = Motivo.BATIDA
	elif progresso_total >= comp:
		recompensa += 20.0
		motivo = Motivo.VOLTA
	elif passos >= LIMITE_PASSOS:
		motivo = Motivo.TEMPO
	terminado = motivo != Motivo.NENHUM
	if terminado:
		_carro.aplicar_comandos(0.0, 0.0)