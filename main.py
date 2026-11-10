"""Controlador Python do carro (ligado ao Godot através do py4godot).

Este é o ficheiro onde escreves a "inteligência" do carro. O exemplo abaixo
só demonstra os comandos: acelera, recua, e depois larga o pedal.
"""

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI

# Força usada pelo controlador de teste
FORCA_ACELERACAO = 0.8
INTERVALO_PRINT = 1.0


@gdclass
class main(Node):
    """Nó que o Godot anexa ao carro e que o comanda a cada tick de física."""

    def _ready(self) -> None:
        """Chamado uma vez quando o nó entra na cena: liga-se ao carro (o nó pai)."""
        self.carro = CarroAPI(self.get_parent())
        self.tempo = 0.0
        self.proximo_print = 0.0
        print("[main] pronto")

    def _physics_process(self, delta: float) -> None:
        """Controlador de teste contínuo para o carro conseguir correr."""
        self.tempo += delta

        self.carro.acelerar(FORCA_ACELERACAO)
        self.carro.virar(0.0)

        if self.tempo >= self.proximo_print:
            self.proximo_print += INTERVALO_PRINT
            print("[main] velocidade=%.0f km/h | rumo=%.0f° | rodas=%.0f°" % (
                self.carro.velocidade, self.carro.rumo, self.carro.angulo_rodas))
