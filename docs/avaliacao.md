# Protocolo de avaliação

Executa `cenas/avaliacao.tscn` com F6. A cena usa a mesma ponte de ações do treino, um carro e um modelo de cada vez. As pistas são recriadas com a mesma seed para PPO, SAC e PPO-LSTM. A política é determinística; a memória da LSTM é reiniciada em cada pista. São lidos PPO/SAC JSON e LSTM ZIP da pasta `ml/pesos/`. A avaliação copia os modelos para a pasta de resultados antes de os usar, evitando que um treino concorrente altere uma política durante a medição.

## Conjuntos

`configuracoes/pistas.json` define 10 pistas de validação e 30 de teste com seeds distintas, acima de 2**30. O treino automático escolhe seeds abaixo de 2**30 e rejeita uma seed inicial reservada. As pistas de validação podem ser usadas para afinar; não usar as de teste até fixar as escolhas. A separação numérica não prova que duas seeds gerem geometrias muito diferentes. Um histórico antigo sem registos completos não permite excluir toda a exposição anterior. Não usar Path2D manual nesta cena.

`Avaliacao limite pistas = 0` usa todas as pistas. Um valor positivo usa apenas as primeiras N para testar a integração; não tratar esses testes curtos como resultados finais. O conjunto efetivamente usado fica no ficheiro de configuração.

## Regras comuns

Um episódio termina na primeira colisão, ao completar uma volta, ou aos 1600 passos. Cada ação corresponde a quatro ticks físicos de 1/60 s. A contagem de colisões é a da regra RL, sem os filtros visuais de velocidade/intervalo do campeonato. Colisões têm prioridade sobre conclusão se ocorrerem no mesmo passo. Não existem outros carros para interferir.

Esta regra mede concluir uma volta sem colisões, não a capacidade de recuperar depois de bater nem uma corrida de cinco voltas. O manual do campeonato não participa. Modelos treinados com outras versões da física/recompensa devem ser identificados ou novamente treinados para uma comparação controlada.

## Saídas

`resultados/<conjunto>/<data-id>/` guarda:

- `configuracao.json`: seeds, estado completo/incompleto, código e modelos identificados por SHA-256.
- `modelos/`: cópia dos três artefactos usados.
- `episodios.csv`: modelo, seed, sucesso, motivo, batidas, passos, progresso, recompensa, tempo simulado e tempo real.
- `resumo.json`: taxas de conclusão/colisão, progresso médio, recompensa média e desvio entre pistas, tempo médio/mediano apenas dos episódios concluídos.

Falhas não recebem tempo de conclusão zero: o campo fica vazio e a média dos concluídos fica null quando não há sucessos. Comparar sempre o tempo juntamente com a taxa de conclusão para não favorecer modelos que só concluem pistas fáceis. O desvio entre pistas não é a variabilidade entre seeds de treino. O tempo real inclui comunicação e inferência e não substitui o tempo simulado de condução.

Precisão de trajetória ainda não tem métrica definida. Não chamamos "precisão" ao progresso. Para estudá-la será preciso definir, por exemplo, erro lateral médio, e decidir se centragem é de facto desejável para o objetivo de rapidez. Não há ainda gráficos automáticos nem intervalos de confiança entre treinos.

## Integridade

Os JSON/ZIP antigos não contêm necessariamente a mesma origem. A avaliação identifica o ficheiro efetivamente usado, mas não reconstrói informação perdida. Os registos históricos foram arquivados, não completados artificialmente. Os checkpoints futuros têm configuração por execução. O gerador tenta até 300 variantes e pode avisar se não encontrar uma pista válida; essas ocorrências devem ser tratadas antes de aceitar um resultado final.
