"""Condução SAC determinística, com os pesos JSON e sem PyTorch."""
import os
import sys
from pathlib import Path
try:
    _RAIZ = str(Path(__file__).resolve().parents[2])
except NameError:
    _RAIZ = os.getcwd()
if _RAIZ not in sys.path:
    sys.path.insert(0, _RAIZ)
from py4godot.classes import gdclass
from py4godot.classes.Node import Node
from ml.ambiente.carro_api import CarroAPI
from ml.constantes import FRAMES_POR_ACAO, OBSERVACOES, pasta_ml
from ml.modelos.sac_modelo import prever
import json

@gdclass
class corrida_sac(Node):
    def _ready(self) -> None:
        self.carro = CarroAPI(self.get_parent())
        self.rede = None
        self.frames = 0
        self.episodio = -1
        self.acao = [0.0, 0.0]
        caminho = os.environ.get("SAC_FICHEIRO_PESOS", os.path.join(pasta_ml(), "pesos", "sac_mlp.json"))
        if not os.path.isfile(caminho):
            print("[SAC] Falta sac_mlp.json. Executa primeiro cenas/treino_sac.tscn.", flush=True)
            self.carro.parar()
            return
        with open(caminho, encoding="utf-8") as f:
            rede = json.load(f)
        if rede.get("algoritmo") != "SAC" or rede.get("observacoes") != OBSERVACOES:
            raise ValueError("Modelo SAC incompatível com as observações do carro")
        if rede["low"] != [-1.0, -1.0] or rede["high"] != [1.0, 1.0]:
            raise ValueError("Modelo SAC incompatível com as ações do carro")
        self.rede = rede
        print("[SAC] Modelo carregado: " + caminho, flush=True)

    def _physics_process(self, delta: float) -> None:
        if self.rede is None:
            return
        episodio = int(self.get_parent().get("episodio_id"))
        if episodio != self.episodio:
            self.episodio = episodio
            self.frames = 0
        if self.frames % FRAMES_POR_ACAO == 0:
            self.acao = prever(self.rede, self.carro.observacao)
        self.frames += 1
        self.carro.comando(*self.acao)
