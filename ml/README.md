# ml/ — tudo o que é Machine Learning

```
ml/
├── constantes.py          valores partilhados com o GDScript + caminhos (pesos, logs)
├── controladores/         scripts py4godot carregados pelo Godot (res://ml/controladores/...)
│   ├── treino_ppo.py        treina (PPO, SAC ou PPO-LSTM) dentro do Godot
│   ├── corrida_ppo.py       conduz com ml/pesos/ppo_mlp.json
│   └── corrida_sac.py       conduz com ml/pesos/sac_mlp.json
├── ambiente/              ligação carro ↔ Python
│   ├── carro_api.py         comandos e observações do carro
│   ├── carro_treino_api.py  extensão só para treino
│   └── ambiente_interno.py  ambiente Gymnasium
├── modelos/               definição e I/O dos modelos (sem Godot)
│   ├── ppo_modelo.py        PPO-MLP ↔ JSON
│   ├── sac_modelo.py        SAC → ator JSON e inferência sem torch
│   └── modelos_io.py        guardar / carregar
├── treino/
│   └── treinador.py         lógica de treino comum (SB3), checkpoints, retoma
├── testes/
│   └── test_sac.py
├── pesos/                 modelos treinados (ppo_mlp.json, sac_mlp.zip/.json/.replay.pkl)
├── logs/                  CSV de episódios e tensorboard (ignorado pelo git)
└── GUIA_SAC.md
```

Regras: o código novo de treino/modelos vai para `treino/` e `modelos/`; o que o Godot carrega vai para `controladores/` (o nome da classe tem de ser igual ao nome do ficheiro). Os imports usam sempre `from ml.<pasta>.<ficheiro> import ...`.

Testes (a partir da pasta do projeto): `python -m unittest ml.testes.test_sac`
