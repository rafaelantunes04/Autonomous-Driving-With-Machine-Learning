"""Controlador Python de exemplo (ligado ao Godot através do py4godot).

Só demonstra os comandos: acelera a virar, recua e depois larga o pedal.
Copia este ficheiro para escreveres o teu controlador.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro
(exemplo_simples.py -> class exemplo_simples).
"""

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI

# Instantes (em segundos) do programa de demonstração
FIM_ACELERAR = 1.0
FIM_RECUAR = 3.5
INTERVALO_PRINT = 1.0


@gdclass
class exemplo_simples(Node):
	"""Nó que o Godot anexa ao carro e que o comanda a cada tick de física."""

	def _ready(self) -> None:
		self.carro = CarroAPI(self.get_parent())
		self.tempo = 0.0
		self.proximo_print = 0.0
		print("[exemplo_simples] pronto")

	def _physics_process(self, delta: float) -> None:
		self.tempo += delta

		if self.tempo < FIM_ACELERAR:
			self.carro.acelerar(1.0)
			self.carro.virar(1.0)
		elif self.tempo < FIM_RECUAR:
			self.carro.recuar(1.0)
			self.carro.virar(0.0)
		else:
			self.carro.parar()

		if self.tempo >= self.proximo_print:
			self.proximo_print += INTERVALO_PRINT
			print("[exemplo_simples] velocidade=%.0f km/h | rumo=%.0f° | rodas=%.0f°" % (
				self.carro.velocidade, self.carro.rumo, self.carro.angulo_rodas))
