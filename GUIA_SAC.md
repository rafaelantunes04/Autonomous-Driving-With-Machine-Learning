# SAC no Godot

Abre `cenas/track.tscn` (a cena principal) e executa com F6. No nó Corrida, grupo Treino, escolhe o modelo (`sac_mlp` para SAC, `ppo_mlp` para PPO), o número de passos, seed, dispositivo (`auto`, `cpu`, `cuda`), intervalo de gravação em episódios e se queres continuar um treino. A velocidade de treino está a 10 (`velocidade_treino`; 1 = tempo real). O carro de treino SAC é ciano. `auto` usa CUDA se disponível; é necessário ter testado cálculos na GPU, não apenas a sua deteção.

Nos primeiros 1000 passos, SAC recolhe experiências com ações aleatórias; depois começa a atualizar as redes. Configuração: MLP [256, 256], batch 256, buffer 100000, learning rate 0.0003, gamma 0.99, tau 0.005, entropia automática, uma atualização por passo. Não usa pesos PPO. PPO e SAC partilham observações, ações e recompensa.

## Ficheiros
- `modelos/sac_mlp.zip`: redes e otimizadores SB3.
- `modelos/sac_mlp.replay.pkl`: experiências para retomar treino (apenas carregar ficheiros do próprio projeto em que confies).
- `modelos/sac_mlp.json`: ator determinístico para condução, sem PyTorch.
- `logs/sac_mlp_episodios.csv.monitor.csv`: recompensa, duração em passos, tempo de registo, seed da pista, sucesso e motivo do fim por episódio.

O treino guarda periodicamente e ao concluir normalmente. Fechar à força o processo não garante a gravação final. Para retomar, ativa Treino continuar e mantém ZIP e replay juntos; o número de passos escolhido é adicional. Não é uma reprodução exata da execução interrompida (o estado físico e a sequência de resets não são restaurados). Começar de novo guarda uma cópia `.anterior` dos ficheiros existentes. Não executar dois treinos sobre o mesmo destino. Cada ficheiro é substituído atomicamente, mas os três não formam uma transação única.

## Condução
Executa `cenas/comparacao.tscn`: verde = PPO e ciano = SAC. É uma demonstração visual; o campeonato atual não substitui uma avaliação independente de cada modelo. Para o relatório, usar as mesmas seeds de teste, separadas das de treino, vários treinos e métricas de conclusão, colisões, progresso e tempo. Ainda não há resultados de qualidade do SAC.

A aceleração de treino passa a manter o passo físico de 1/60 s. Resultados PPO antigos obtidos com outro passo físico não constituem uma comparação controlada; repetir os treinos de comparação nesta versão. Seeds explícitas de reset são agora respeitadas. Para testes técnicos, TREINO_PASTA_SAIDA permite guardar num diretório separado; SAC_FICHEIRO_PESOS permite escolher outro JSON na demonstração.

## Validação da implementação

Testes sintéticos: atualizações SAC, equivalência entre SB3 e JSON em 100 observações, gravação, retoma com replay e contagem de passos. No Godot headless foram executados 1020 passos em CPU e 1020 em CUDA; o checkpoint CUDA registou 20 atualizações e 1020 experiências. A cena de comparação carregou ambos os controladores. Estes artefactos estão em `.validation`, não são modelos finais nem evidência de boa condução. Persistem avisos de UID antigo em carro.tscn e recursos em uso ao fechar o engine. A inspeção visual em janela continua a ser necessária.
