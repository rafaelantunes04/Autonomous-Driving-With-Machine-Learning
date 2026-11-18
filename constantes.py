"""Valores partilhados entre o treino, a condução e o Godot.

Alguns têm de ser iguais aos do GDScript (indicados em cada comentário).
"""

import os

# Ações do modelo por tick de física: escolhe-se uma ação a cada N ticks.
# Tem de ser igual a TreinoRL.FRAMES_POR_ACAO (scripts/rl/treino_rl.gd).
FRAMES_POR_ACAO = 4

# Nº de observações do modelo. Tem de ser igual a ObservacaoRL.TAMANHO.
OBSERVACOES = 7

# Pesos do modelo PPO-MLP (escritos pelo treino, lidos por corrida_ppo.py)
FICHEIRO_PESOS = os.path.join("modelos", "ppo_mlp.json")


def pasta_do_projeto():
	"""Pasta do projeto Godot: a que tem o project.godot, junto a este ficheiro ou na pasta de trabalho."""
	candidatas = [os.path.dirname(os.path.abspath(__file__)), os.getcwd()]
	for pasta in candidatas:
		if os.path.isfile(os.path.join(pasta, "project.godot")):
			return pasta
	return candidatas[0]
