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
        """Liga a API ao nó do carro e desativa o controlo pelas setas.

        `no_carro` é o nó Godot com o script carro.gd. A partir daqui o carro
        deixa de ler o teclado: quem manda é este código.
        """
        self._no = no_carro
        self._erros_mostrados = set()
        self._escrever("controlo_manual", False)

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
