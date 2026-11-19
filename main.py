"""Controlador Python do carro, com janela de telemetria (via py4godot).

É aqui que escreves a "inteligência" do carro. O exemplo só demonstra os
comandos: acelera, recua e depois larga o pedal. Apaga o conteúdo de
_physics_process e escreve a tua lógica. Põe USAR_TELEMETRIA = False para
não abrir a janela.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro
(main.py -> class main).
"""

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI

USAR_TELEMETRIA = True

# Instantes (em segundos) do programa de demonstração
FIM_ACELERAR = 1.0
FIM_RECUAR = 3.5
INTERVALO_PRINT = 1.0


@gdclass
class main(Node):
	"""Nó que o Godot anexa ao carro e que o comanda a cada tick de física."""

	def _ready(self) -> None:
		self.carro = CarroAPI(self.get_parent())
		self.tempo = 0.0
		self.proximo_print = 0.0
		self.telemetria = None
		if USAR_TELEMETRIA:
			from telemetria_ui import TelemetriaUI
			self.telemetria = TelemetriaUI()
		print("[main] pronto")

	def _physics_process(self, delta: float) -> None:
		self.tempo += delta

		if self.tempo < FIM_ACELERAR:
			self.carro.acelerar(1.0)
		elif self.tempo < FIM_RECUAR:
			self.carro.recuar(1.0)
		else:
			self.carro.largar_pedal()
		self.carro.virar(0.0)

		velocidade, rumo, rodas = self.carro.velocidade, self.carro.rumo, self.carro.angulo_rodas
		if self.telemetria is not None:
			self.telemetria.atualizar(velocidade, rumo, rodas, self.carro.sensores)

		if self.tempo >= self.proximo_print:
			self.proximo_print += INTERVALO_PRINT
			print("[main] velocidade=%.0f km/h | rumo=%.0f° | rodas=%.0f°" % (velocidade, rumo, rodas))
