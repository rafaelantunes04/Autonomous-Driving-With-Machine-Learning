from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI


@gdclass
class main(Node):

    def _ready(self) -> None:
        self.carro = CarroAPI(self.get_parent())
        self.tempo = 0.0
        self.proximo_print = 0.0
        print("[main] pronto")

    def _physics_process(self, delta: float) -> None:
        self.tempo += delta

        if self.tempo < 1.0:
            self.carro.manter_velocidade(50)     # 1 s para a frente
        elif self.tempo < 3.5:
            self.carro.manter_velocidade(-30)    # trava, engata e recua
        else:
            self.carro.manter_velocidade(0)      # pára
        self.carro.virar(0.0)

        if self.tempo >= self.proximo_print:
            self.proximo_print += 1.0
            print("[main] velocidade=%.0f km/h | rumo=%.0f° | rodas=%.0f°" % (
                self.carro.velocidade, self.carro.rumo, self.carro.angulo_rodas))