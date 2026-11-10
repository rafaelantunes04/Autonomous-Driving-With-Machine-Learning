"""Controlador Python do carro (ligado ao Godot através do py4godot).

Este é o ficheiro onde escreves a "inteligência" do carro. O exemplo abaixo
só demonstra os comandos: acelera (a virar), recua, e depois larga o pedal.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro
(modelo_x.py -> class modelo_x).
"""

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI

# Instantes (em segundos) do programa de demonstração
FIM_ACELERAR = 1.0
FIM_RECUAR = 3.5
INTERVALO_PRINT = 1.0


@gdclass
class modelo_x(Node):
	"""Nó que o Godot anexa ao carro e que o comanda a cada tick de física."""

	def _ready(self) -> None:
		"""Chamado uma vez quando o nó entra na cena: liga-se ao carro (o nó pai)."""
		self.carro = CarroAPI(self.get_parent())
		self.tempo = 0.0
		self.proximo_print = 0.0
		print("[modelo_x] pronto")

	def _physics_process(self, delta: float) -> None:
		"""Chamado a cada tick de física: decide os comandos e mostra o estado."""
		self.tempo += delta

		if self.tempo < FIM_ACELERAR:
			self.carro.acelerar(1.0)    # pedal a fundo para a frente
			self.carro.virar(1.0)       # volante todo à direita
		elif self.tempo < FIM_RECUAR:
			self.carro.recuar(1.0)      # trava, engata e recua
			self.carro.virar(0.0)
		else:
			self.carro.largar_pedal()
			self.carro.virar(0.0)

		if self.tempo >= self.proximo_print:
			self.proximo_print += INTERVALO_PRINT
			print("[modelo_x] velocidade=%.0f km/h | rumo=%.0f° | rodas=%.0f°" % (
				self.carro.velocidade, self.carro.rumo, self.carro.angulo_rodas))
