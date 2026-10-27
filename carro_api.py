"""Camada de simplificação: esconde o Godot e dá-te um carro fácil de usar.

    carro = CarroAPI(no_do_carro)

    # Comandos (chama a cada tick)
    carro.acelerar(1.0)            # -1 (trava/marcha-atrás) a +1 (acelera)
    carro.virar(-0.3)              # -1 (esquerda) a +1 (direita)
    carro.manter_velocidade(60)    # acelera/trava sozinho para ficar nos 60 km/h

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

    def __init__(self, no_carro, ganho_velocidade=0.05):
        self._no = no_carro
        self.ganho_velocidade = ganho_velocidade
        self._erros_mostrados = set()
        # A partir daqui o carro deixa de ler as setas: mandas tu.
        self._escrever("controlo_manual", False)

    # ------------------------------------------------------------ comandos

    def acelerar(self, valor):
        self._escrever("input_acel", _limitar(valor))

    def virar(self, valor):
        self._escrever("input_dir", _limitar(valor))

    def manter_velocidade(self, alvo_kmh):
        """Controlador proporcional simples. Chama a cada tick."""
        erro = alvo_kmh - self.velocidade
        self.acelerar(erro * self.ganho_velocidade)

    def parar(self):
        self.acelerar(0.0)
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
