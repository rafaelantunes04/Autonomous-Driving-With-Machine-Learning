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
	carro.sensores                 # {"frente": 0-1, "esquerda": ..., ...} (1 = livre, 0 = parede)
	carro.observacao               # as 7 observações do modelo

Este ficheiro não depende do py4godot: só fala com o nó do carro via get/set.
O que é só para o treino está em carro_treino_api.py.
"""

import traceback

from ml.constantes import OBSERVACOES

# Nome do sensor -> propriedade do carro (scripts/carro/carro.gd)
SENSORES = {
	"esquerda_2": "estado_sensor_left_2",
	"esquerda": "estado_sensor_left",
	"frente": "estado_sensor_front",
	"direita": "estado_sensor_right",
	"direita_2": "estado_sensor_right_2",
}


def _limitar(valor, minimo=-1.0, maximo=1.0):
	"""Converte `valor` para float e prende-o ao intervalo [minimo, maximo]."""
	return max(minimo, min(maximo, float(valor)))


class CarroAPI:
	"""Interface simples para controlar o carro (um nó Carro do Godot)."""

	def __init__(self, no_carro):
		"""`no_carro` é o nó Godot com o script carro.gd (o pai do controlador)."""
		self._no = no_carro
		self._erros_mostrados = set()

	# ------------------------------------------------------------ comandos

	def acelerar(self, forca):
		"""Pedal para a frente. `forca`: 0 (solto) a 1 (a fundo)."""
		self._escrever("input_acel", _limitar(forca, 0.0, 1.0))

	def recuar(self, forca):
		"""Pedal para trás. `forca`: 0 a 1. Trava se ainda vai para a frente; engata a marcha-atrás quando está quase parado."""
		self._escrever("input_acel", -_limitar(forca, 0.0, 1.0))

	def largar_pedal(self):
		"""Larga o pedal: o carro deixa de acelerar e vai abrandando."""
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
		self.comando(0.0, 0.0)

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

	@property
	def sensores(self):
		"""Leitura dos 5 raycasts, de 0.0 (parede encostada) a 1.0 (livre)."""
		return {nome: self._ler(propriedade) for nome, propriedade in SENSORES.items()}

	@property
	def observacao(self):
		"""As observações do modelo (lista de floats), ver scripts/rl/observacao_rl.gd.

		0: velocidade longitudinal; 1: ângulo das rodas; 2-6: raycasts (esq_2, esq, frente, dir, dir_2).
		"""
		return [self._ler("estado_obs_%d" % i) for i in range(OBSERVACOES)]

	# ------------------------------------------------------------ interno

	def _escrever(self, propriedade, valor):
		"""Escreve `valor` numa propriedade do nó do carro. Se falhar, avisa uma vez e continua."""
		try:
			self._no.set(propriedade, valor)
		except Exception:
			self._avisar("set", propriedade)

	def _ler(self, propriedade):
		"""Lê uma propriedade numérica do nó do carro como float. Se falhar, avisa uma vez e devolve 0.0."""
		try:
			return float(self._no.get(propriedade))
		except Exception:
			self._avisar("get", propriedade)
			return 0.0

	def _avisar(self, operacao, propriedade):
		"""Imprime o erro atual só da primeira vez, para não encher a consola 60x por segundo."""
		chave = (operacao, propriedade)
		if chave in self._erros_mostrados:
			return
		self._erros_mostrados.add(chave)
		print("[carro_api] %s('%s') falhou:" % (operacao, propriedade))
		traceback.print_exc()
