"""Camada de simplificação: esconde o Godot e dá-te um carro fácil de usar.

    carro = CarroAPI(no_do_carro)

    # Comandos (chama a cada tick)
    carro.acelerar(0.8)            # pedal para a frente: força de 0 a 1
    carro.recuar(0.5)              # pedal para trás (trava / marcha-atrás): força de 0 a 1
    carro.virar(-0.3)              # -1 (esquerda) a +1 (direita)
    carro.largar_pedal()           # força 0

    # Leitura
    carro.velocidade               # km/h (negativo em marcha-atrás)
    carro.rumo                     # graus 0-360, para onde o carro aponta
    carro.angulo_rodas             # graus, positivo = rodas à direita

Este ficheiro não depende do py4godot: só fala com o nó do carro via get/set.
"""

import traceback


def _limitar(valor, minimo=-1.0, maximo=1.0):
    return max(minimo, min(maximo, float(valor)))


class CarroAPI:

    def __init__(self, no_carro):
        self._no = no_carro
        self._erros_mostrados = set()
        # A partir daqui o carro deixa de ler as setas: mandas tu.
        self._escrever("controlo_manual", False)

    # ------------------------------------------------------------ comandos

    def acelerar(self, forca):
        """Pedal para a frente. forca: 0 (solto) a 1 (a fundo)."""
        self._escrever("input_acel", _limitar(forca, 0.0, 1.0))

    def recuar(self, forca):
        """Pedal para trás. forca: 0 (solto) a 1 (a fundo).

        Se o carro ainda vai para a frente, trava; quando está (quase) parado,
        engata a marcha-atrás.
        """
        self._escrever("input_acel", -_limitar(forca, 0.0, 1.0))

    def largar_pedal(self):
        self._escrever("input_acel", 0.0)

    def virar(self, valor):
        self._escrever("input_dir", _limitar(valor))

    def parar(self):
        self.largar_pedal()
        self.virar(0.0)

    # ------------------------------------------------------------ leitura

    @property
    def velocidade(self):
        return self._ler("estado_velocidade_kmh")

    @property
    def rumo(self):
        return self._ler("estado_rumo")

    @property
    def angulo_rodas(self):
        return self._ler("estado_angulo_rodas")

    # ------------------------------------------------------------ interno

    def _escrever(self, propriedade, valor):
        try:
            self._no.set(propriedade, valor)
        except Exception:
            self._avisar("set", propriedade)

    def _ler(self, propriedade):
        try:
            return float(self._no.get(propriedade))
        except Exception:
            self._avisar("get", propriedade)
            return 0.0

    def _avisar(self, operacao, propriedade):
        # Mostra cada erro uma só vez, para não encher a consola a 60 vezes/s.
        chave = (operacao, propriedade)
        if chave not in self._erros_mostrados:
            self._erros_mostrados.add(chave)
            print("[carro_api] %s('%s') falhou:" % (operacao, propriedade))
            traceback.print_exc()