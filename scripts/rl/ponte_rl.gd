extends Node
## Anexe este nó como filho direto de Track.
## Modos: --rl-train para treino, --rl-eval para avaliação e --rl-race para corrida.
## O modelo escolhe as ações no Python. A ponte aplica-as e devolve o resultado.

const FRAMES_POR_ACAO: int = 4
const LIMITE_PASSOS: int = 1600

var pista: Track
var conexao: StreamPeerTCP = StreamPeerTCP.new()
var buffer: String = ""
var porta: int = 8765
var modo: String = ""
var conectado: bool = false
var aguardando_frames: int = 0
var passos: int = 0
var colisoes: Array[int] = [0, 0, 0]
var ultimo_progresso: Array[float] = [0.0, 0.0, 0.0]
var progresso_total: Array[float] = [0.0, 0.0, 0.0]
var terminado: Array[bool] = [false, false, false]
var comprimento: float = 0.0
var distancias: PackedFloat32Array = PackedFloat32Array()
var premios: Array[float] = [0.0, 0.0, 0.0]
var motivo: Array[String] = ["", "", ""]
var aguardando_proxima_corrida: bool = false
var corrida_aguardada: int = 0
var _servidor_local := TCPServer.new()
var _pid_piloto := -1
var _prazo_piloto_ms := 0

# Ligação TCP e comandos enviados pelo Python

func _ready() -> void:
	pista = get_parent() as Track
	process_priority = 100
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--rl-train" in args:
		modo = "train"
	elif "--rl-eval" in args:
		modo = "eval"
	elif "--rl-race" in args:
		modo = "race"
	else:
		set_process(false)
		set_physics_process(false)
		return
	var pos := args.find("--rl-port")
	if pos >= 0 and pos + 1 < args.size():
		porta = int(args[pos + 1])
	print("RL ", modo, " conectando a 127.0.0.1:", porta)
	conexao.connect_to_host("127.0.0.1", porta)


func iniciar_piloto_local() -> void:
	if not modo.is_empty():
		return

	var pasta := ProjectSettings.globalize_path("res://")
	var python := pasta.path_join(".venv/Scripts/python.exe" if OS.has_feature("windows") else ".venv/bin/python")
	if not FileAccess.file_exists(python) or not FileAccess.file_exists("res://modelos/ppo_mlp.zip"):
		push_warning("PPO automático: é preciso ter o Python da .venv e o modelo modelos/ppo_mlp.zip.")
		return

	# O sistema escolhe uma porta livre, mesmo com mais de uma corrida aberta.
	if _servidor_local.listen(0, "127.0.0.1") != OK:
		push_warning("PPO automático: não foi possível abrir a ligação local.")
		return

	var script := pasta.path_join("corrida_ppo.py")
	_pid_piloto = OS.create_process(python, [
		script, "--conectar", "--projeto", pasta,
		"--porta", str(_servidor_local.get_local_port())
	])
	if _pid_piloto <= 0:
		_servidor_local.stop()
		push_warning("PPO automático: não foi possível iniciar o Python.")
		return

	_prazo_piloto_ms = Time.get_ticks_msec() + 60_000
	modo = "race"
	set_process(true)
	set_physics_process(true)


func piloto_local_ativo() -> bool:
	return _pid_piloto > 0


func _encerrar_piloto_local() -> void:
	if not piloto_local_ativo():
		return
	_servidor_local.stop()
	conexao.disconnect_from_host()
	if OS.is_process_running(_pid_piloto):
		OS.kill(_pid_piloto)
	_pid_piloto = -1


func _exit_tree() -> void:
	_encerrar_piloto_local()


func _process(_delta: float) -> void:
	if modo.is_empty():
		return

	if piloto_local_ativo():
		if not OS.is_process_running(_pid_piloto) or (not conectado and Time.get_ticks_msec() >= _prazo_piloto_ms):
			_encerrar_piloto_local()
			modo = ""
			aguardando_frames = 0
			push_warning("PPO automático: o Python desligou ou não respondeu. A usar as setas.")
			for carro in pista.carros:
				carro.controlo_manual = true
			pista.reiniciar_corrida()
			return
		if _servidor_local.is_connection_available():
			conexao = _servidor_local.take_connection()
			_servidor_local.stop()

	conexao.poll()
	if conexao.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	if aguardando_proxima_corrida \
			and pista.corrida_ativa \
			and pista.corrida_atual > corrida_aguardada:
		aguardando_proxima_corrida = false
		_preparar_estado_corrida()
		_enviar(_resposta("aguardar_proxima_corrida"))
		return
	if not conectado:
		conectado = true
		_enviar({"type": "hello", "mode": modo, "observations": 8, "actions": 2})
	var disponivel := conexao.get_available_bytes()
	if disponivel > 0:
		buffer += conexao.get_utf8_string(disponivel)
	while buffer.contains("\n"):
		var fim := buffer.find("\n")
		var linha := buffer.substr(0, fim)
		buffer = buffer.substr(fim + 1)
		if linha.strip_edges().is_empty():
			continue
		var msg = JSON.parse_string(linha)
		if msg is Dictionary:
			_receber(msg)

func _receber(msg: Dictionary) -> void:
	var cmd := str(msg.get("cmd", ""))
	if cmd == "reset":
		if aguardando_frames > 0:
			return
		_reiniciar(
			int(msg.get("seed", 0)),
			int(msg.get("corrida", 1))
		)
		_enviar(_resposta("reset"))
	elif cmd == "step":
		if aguardando_frames > 0:
			return
		var lista: Array = msg.get("actions", [])
		var quantidade := 3 if modo == "eval" else 1
		if lista.size() < quantidade:
			_enviar({"type": "error", "message": "Acoes insuficientes"})
			return
		for i in range(quantidade):
			var carro = pista.carros[i]
			var acao: Array = lista[i]
			if terminado[i]:
				carro.aplicar_comandos(0.0, 0.0)
			else:
				carro.aplicar_comandos(float(acao[0]), float(acao[1]))
		aguardando_frames = FRAMES_POR_ACAO
	elif cmd == "aguardar_proxima_corrida":
		corrida_aguardada = int(msg.get("corrida", pista.corrida_atual))
		if pista.corrida_ativa and pista.corrida_atual > corrida_aguardada:
			_preparar_estado_corrida()
			_enviar(_resposta("aguardar_proxima_corrida"))
		else:
			aguardando_proxima_corrida = true
	elif cmd == "close":
		get_tree().quit()

# Preparação da corrida e avanço da física por ação

func _reiniciar(seed_: int, corrida_: int = 1) -> void:
	pista.current_seed = seed_
	pista.definir_numero_corrida(corrida_)
	pista.generate(seed_)
	_preparar_estado_corrida()


func _preparar_estado_corrida() -> void:
	passos = 0
	colisoes = [0, 0, 0]
	progresso_total = [0.0, 0.0, 0.0]
	terminado = [false, false, false]
	premios = [0.0, 0.0, 0.0]
	motivo = ["", "", ""]
	_calcular_distancias()
	for i in range(pista.carros.size()):
		var carro = pista.carros[i]
		carro.controlo_manual = false
		carro.aplicar_comandos(0.0, 0.0)
		carro.set_physics_process(i == 0 or modo == "eval")
		if not carro.colidiu.is_connected(_bateu.bind(i)):
			carro.colidiu.connect(_bateu.bind(i))
		if i < 3:
			ultimo_progresso[i] = _localizar(carro.global_position)["progresso"]
	# Durante treino não rodar o relógio/encerramento automático do Track.
	if modo == "train":
		pista.set_physics_process(false)
	else:
		pista.set_physics_process(true)

func _bateu(_colisor: Node, _velocidade: float, indice: int) -> void:
	if indice >= 0 and indice < 3:
		colisoes[indice] += 1

func _physics_process(_delta: float) -> void:
	if aguardando_frames <= 0:
		return
	aguardando_frames -= 1
	if aguardando_frames == 0:
		passos += 1
		_atualizar_recompensas()
		_enviar(_resposta("step"))

# Posição do carro na pista e observações do modelo

func _calcular_distancias() -> void:
	distancias = PackedFloat32Array()
	comprimento = 0.0
	var n: int = pista.centerline.size()
	for i in range(n):
		distancias.append(comprimento)
		comprimento += pista.centerline[i].distance_to(pista.centerline[(i + 1) % n])

func _localizar(pos_global: Vector2) -> Dictionary:
	var pos: Vector2 = pista.to_local(pos_global)
	var linha: PackedVector2Array = pista.centerline
	if linha.is_empty():
		return {"progresso": 0.0, "lateral": 0.0, "tangente": Vector2.RIGHT, "alvo": Vector2.RIGHT}
	if distancias.size() != linha.size():
		_calcular_distancias()
	var melhor_d: float = INF
	var melhor_i: int = 0
	var melhor_t: float = 0.0
	var melhor_p := Vector2.ZERO
	var n := linha.size()
	for i in range(n):
		var a: Vector2 = linha[i]
		var b: Vector2 = linha[(i + 1) % n]
		var ab: Vector2 = b - a
		var t: float = clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var p: Vector2 = a + ab * t
		var d: float = pos.distance_squared_to(p)
		if d < melhor_d:
			melhor_d = d
			melhor_i = i
			melhor_t = t
			melhor_p = p
	var tangente: Vector2 = (linha[(melhor_i + 1) % n] - linha[melhor_i]).normalized()
	var normal: Vector2 = Vector2(-tangente.y, tangente.x)
	var lateral: float = (pos - melhor_p).dot(normal)
	var progresso: float = distancias[mini(melhor_i, distancias.size() - 1)] + linha[melhor_i].distance_to(linha[(melhor_i + 1) % n]) * melhor_t
	var futuro_i: int = (melhor_i + 15) % n
	var alvo: Vector2 = linha[futuro_i] - pos
	return {"progresso": progresso, "lateral": lateral, "tangente": tangente, "alvo": alvo}

## A ordem destes oito valores faz parte da interface com o modelo treinado.
func _observacao(i: int) -> Array:
	var carro = pista.carros[i]
	var loc: Dictionary = _localizar(carro.global_position)
	var tangente: Vector2 = loc["tangente"]
	var angulo: float = wrapf(carro.global_rotation - (tangente.rotated(pista.global_rotation)).angle(), -PI, PI)
	var alvo: Vector2 = loc["alvo"]
	var alvo_angulo: float = wrapf((alvo.rotated(pista.global_rotation)).angle() - carro.global_rotation, -PI, PI)
	return [
		clampf(carro.velocity.dot(carro.transform.x) / maxf(carro.velocidade_max, 1.0), -1.0, 1.0),
		clampf(float(loc["lateral"]) / maxf(pista.track_width * 0.5, 1.0), -3.0, 3.0),
		sin(angulo), cos(angulo), sin(alvo_angulo), cos(alvo_angulo),
		clampf(carro.direcao_rodas / deg_to_rad(30.0), -1.0, 1.0),
		clampf(carro.velocity.length() / maxf(carro.velocidade_max, 1.0), 0.0, 1.0)
	]

# Recompensa e condições de fim do episódio

func _atualizar_recompensas() -> void:
	var quantidade := 3 if modo == "eval" else 1
	for i in range(quantidade):
		if terminado[i]:
			premios[i] = 0.0
			continue
		if modo == "race" and not pista.corrida_ativa:
			terminado[i] = true
			motivo[i] = "vitoria"
			premios[i] = 0.0
			continue
		var carro = pista.carros[i]
		var loc: Dictionary = _localizar(carro.global_position)
		var atual: float = loc["progresso"]
		var delta: float = atual - ultimo_progresso[i]
		if delta > comprimento * 0.5:
			delta -= comprimento
		elif delta < -comprimento * 0.5:
			delta += comprimento
		ultimo_progresso[i] = atual
		var limite_movimento: float = carro.velocidade_max * FRAMES_POR_ACAO / 60.0 * 1.8
		delta = clampf(delta, -limite_movimento, limite_movimento)
		progresso_total[i] += delta
		var lateral: float = absf(float(loc["lateral"]))
		premios[i] = clampf(delta / 35.0, -2.0, 2.0) - 0.01 - 0.02 * lateral / maxf(pista.track_width * 0.5, 1.0)
		if modo == "race":
			continue
		if colisoes[i] > 0:
			premios[i] -= 5.0
			terminado[i] = true
			motivo[i] = "batida"
		elif lateral > pista.track_width * 0.52:
			premios[i] -= 8.0
			terminado[i] = true
			motivo[i] = "fora_da_pista"
		elif progresso_total[i] >= comprimento:
			premios[i] += 20.0
			terminado[i] = true
			motivo[i] = "volta"
		elif passos >= LIMITE_PASSOS:
			terminado[i] = true
			motivo[i] = "tempo"
		if terminado[i]:
			carro.aplicar_comandos(0.0, 0.0)
			carro.set_physics_process(false)

# Resposta devolvida ao Python

func _resposta(tipo: String) -> Dictionary:
	var quantidade := 3 if modo == "eval" else 1
	var obs: Array = []
	var rewards: Array = []
	var dones: Array = []
	var infos: Array = []
	for i in range(quantidade):
		if terminado[i]:
			obs.append([0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0])
		else:
			obs.append(_observacao(i))
		rewards.append(premios[i])
		dones.append(terminado[i])
		infos.append({"progresso": progresso_total[i], "comprimento": comprimento, "batidas": colisoes[i], "motivo": motivo[i], "passos": passos, "seed": pista.current_seed})
	return {"type": tipo, "observations": obs, "rewards": rewards, "dones": dones, "infos": infos}

func _enviar(obj: Dictionary) -> void:
	if conexao.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		conexao.put_data((JSON.stringify(obj) + "\n").to_utf8_buffer())
