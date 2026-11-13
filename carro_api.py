"""Camada de simplificação: esconde o Godot e dá-te um carro fácil de usar.

	carro = CarroAPI(no_do_carro)

	# Comandos (chama a cada tick de física)
	carro.acelerar(0.8)            # pedal para a frente: força de 0 a 1
	carro.recuar(0.5)              # pedal para trás (trava / marcha-atrás): força de 0 a 1
	carro.virar(-0.3)              # -1 (esquerda) a +1 (direita)
	carro.largar_pedal()           # força 0
	carro.parar()                  # larga o pedal e endireita o volante

	# Leitura
	carro.velocidade               # km/h (negativo em marcha-atrás)
	carro.rumo                     # graus 0-360, para onde o carro aponta
	carro.angulo_rodas             # graus, positivo = rodas à direita

Este ficheiro não depende do py4godot: só fala com o nó do carro via get/set.
"""

import traceback


def _limitar(valor, minimo=-1.0, maximo=1.0):
	"""Converte `valor` para float e prende-o ao intervalo [minimo, maximo].

	Garante que nunca enviamos ao carro um comando fora do que ele aceita.
	"""
	return max(minimo, min(maximo, float(valor)))


class CarroAPI:
	"""Interface simples para controlar o carro (um nó Carro do Godot)."""

	def __init__(self, no_carro):
		"""Liga a API ao nó do carro.

		`no_carro` é o nó Godot com o script carro.gd (o pai do controlador).
		O carro já não lê o teclado por si: só obedece a quem for o seu
		controlador, que aqui é este código.
		"""
		self._no = no_carro
		self._erros_mostrados = set()

	# ------------------------------------------------------------ comandos

	def acelerar(self, forca):
		"""Pedal para a frente. `forca`: 0 (solto) a 1 (a fundo)."""
		self._escrever("input_acel", _limitar(forca, 0.0, 1.0))

	def recuar(self, forca):
		"""Pedal para trás. `forca`: 0 (solto) a 1 (a fundo).

		Se o carro ainda vai para a frente, trava; quando está (quase) parado,
		engata a marcha-atrás.
		"""
		self._escrever("input_acel", -_limitar(forca, 0.0, 1.0))

	def largar_pedal(self):
		"""Larga o pedal (força 0): o carro deixa de acelerar e vai abrandando."""
		self._escrever("input_acel", 0.0)

	def virar(self, valor):
		"""Roda o volante. `valor`: -1 (todo à esquerda) a +1 (todo à direita)."""
		self._escrever("input_dir", _limitar(valor))

	def comando(self, acelerar, virar):
		"""Pedal e volante de uma vez, ambos em [-1, 1] (negativo no pedal = travar/marcha-atrás)."""
		self._escrever("input_acel", _limitar(acelerar))
		self._escrever("input_dir", _limitar(virar))

	def parar(self):
		"""Larga o pedal e põe o volante a direito."""
		self.largar_pedal()
		self.virar(0.0)

	# ------------------------------------------------------------ leitura

	@property
	def velocidade(self):
		"""Velocidade na direção da frente, em km/h (negativa em marcha-atrás)."""
		return self._ler("estado_velocidade_kmh")

	@property
	def rumo(self):
		"""Direção para onde o carro aponta, em graus de 0 a 360 (0 = eixo +X)."""
		return self._ler("estado_rumo")

	@property
	def angulo_rodas(self):
		"""Ângulo das rodas da frente, em graus (positivo = rodas à direita)."""
		return self._ler("estado_angulo_rodas")

	# --- Sensores (RayCasts) ---
	@property
	def sensor_front(self):
		"""Leitura do Front_Sensor (0.0 a 1.0)."""
		return self._ler("estado_sensor_front")

	@property
	def sensor_right(self):
		"""Leitura do Right_Sensor (0.0 a 1.0)."""
		return self._ler("estado_sensor_right")

	@property
	def sensor_right_2(self):
		"""Leitura do Right_Sensor_2 (0.0 a 1.0)."""
		return self._ler("estado_sensor_right_2")

	@property
	def sensor_left(self):
		"""Leitura do Left_Sensor (0.0 a 1.0)."""
		return self._ler("estado_sensor_left")

	@property
	def sensor_left_2(self):
		"""Leitura do Left_Sensor_2 (0.0 a 1.0)."""
		return self._ler("estado_sensor_left_2")

	@property
	def observacao(self):
		"""As 8 observações do modelo PPO (lista de floats), ver scripts/rl/observacao_rl.gd."""
		return [self._ler("estado_obs_%d" % i) for i in range(8)]

	# --- Treino por reforço (ver scripts/rl/treino_rl.gd) ---
	MOTIVOS = ("", "batida", "fora_da_pista", "volta", "tempo")

	def rl_reiniciar(self, seed):
		"""Pista nova e carro na partida, parado e congelado até ao primeiro passo."""
		self._escrever("rl_reset", int(seed))

	def rl_congelar(self, congelado):
		"""True pára a física do carro (entre ações); False deixa-a correr."""
		self._escrever("rl_congelado", bool(congelado))

	def rl_avaliar(self):
		"""Fecha um passo: calcula a recompensa e se o episódio acabou."""
		self._escrever("rl_avaliar", True)

	def rl_sair(self):
		"""Fecha o jogo."""
		self._escrever("rl_sair", True)

	def rl_resultado(self):
		"""Observação, recompensa e estado do episódio, num dicionário simples."""
		motivo = int(self._ler("rl_motivo"))
		return {
			"obs": self.observacao,
			"recompensa": self._ler("rl_recompensa"),
			"terminado": bool(self._ler("rl_terminado")),
			"motivo": self.MOTIVOS[motivo] if 0 <= motivo < len(self.MOTIVOS) else "",
			"progresso": self._ler("rl_progresso"),
			"comprimento": self._ler("rl_comprimento"),
			"batidas": int(self._ler("rl_batidas")),
			"passos": int(self._ler("rl_passos")),
		}

	# ------------------------------------------------------------ interno

	def _escrever(self, propriedade, valor):
		"""Escreve `valor` numa propriedade do nó do carro (ex.: "input_acel").

		Se falhar, avisa uma vez e continua, para não rebentar o jogo.
		"""
		try:
			self._no.set(propriedade, valor)
		except Exception:
			self._avisar("set", propriedade)

	def _ler(self, propriedade):
		"""Lê uma propriedade numérica do nó do carro e devolve-a como float.

		Se falhar, avisa uma vez e devolve 0.0.
		"""
		try:
			return float(self._no.get(propriedade))
		except Exception:
			self._avisar("get", propriedade)
			return 0.0

	def _avisar(self, operacao, propriedade):
		"""Imprime o erro atual na consola, mas só da primeira vez que acontece.

		Evita encher a consola com a mesma mensagem 60 vezes por segundo.
		"""
		chave = (operacao, propriedade)
		if chave in self._erros_mostrados:
			return
		self._erros_mostrados.add(chave)
		print("[carro_api] %s('%s') falhou:" % (operacao, propriedade))
		traceback.print_exc()
