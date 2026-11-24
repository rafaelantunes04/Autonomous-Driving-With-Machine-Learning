# Condução Autónoma com Machine Learning

Projeto Godot 2D com PPO, SAC e PPO-LSTM. Python corre dentro do engine através do py4godot. A física e a recompensa são comuns aos três modelos.

## Começar

Abre `project.godot`. No painel de ficheiros abre a cena pretendida e usa **F6**:

| Cena | Função |
|---|---|
| `cenas/track.tscn` | Corrida principal: manual, PPO, SAC e PPO-LSTM (F5) |
| `cenas/treino_ppo.tscn` | Treino PPO |
| `cenas/treino_sac.tscn` | Treino SAC |
| `cenas/treino_ppo_lstm.tscn` | Treino PPO-LSTM |
| `cenas/comparacao.tscn` | Demonstração com manual, PPO verde, SAC ciano e LSTM magenta |
| `cenas/avaliacao.tscn` | Avaliação sequencial dos três modelos em pistas reservadas |

**F5 executa track.tscn**, não a cena que tens aberta. Um script Python não é uma cena executável.

## Instalação

O ambiente local verificado está descrito em `docs/ambiente_local.json`: Godot 4.7.2, py4godot identificado localmente como 4.7-alpha-21 e Python embutido 3.14.4. Compatibilidade do addon e engine deve ser mantida. O instalador ainda permite `--url` para escolher o ZIP; o endereço `latest` não garante a mesma release no futuro.

Na raiz do projeto, em PowerShell (uma linha por comando):

```powershell
python -m pip install tqdm
```

Para a configuração NVIDIA CUDA 13.0 testada neste computador:

```powershell
python download_addon.py --torch-index cu130
```

Para CPU:

```powershell
python download_addon.py --torch-index cpu
```

Para instalar apenas as dependências no addon existente, preservando a distribuição torch compatível já instalada:

```powershell
& ".\addons\py4godot\cpython-3.14.4-windows64\python\python.exe" -s -m pip install -r requirements.txt
```

Verificação:

```powershell
& ".\addons\py4godot\cpython-3.14.4-windows64\python\python.exe" -s -m pip check
```

O requirements principal fixa as versões observadas e não força cu126. `requirements-cu130.txt` especifica a distribuição usada na RTX 5070 Ti local. CPU/CUDA e o controlador NVIDIA têm de ser adequados ao computador; não reinstalar a cada pull. O parâmetro `-s` evita misturar bibliotecas do utilizador com as do addon.

## Treinar e continuar

Seleciona o nó `Corrida` na cena de treino. Define passos, seed, dispositivo, velocidade e intervalo de gravação. `auto` usa CPU para PPO-MLP e CUDA, se disponível, para SAC/LSTM. CUDA detetada não substitui um teste de operação na GPU. Todas as cenas começam com 100000 passos, seed 42, velocidade 10 e gravação a cada 10 episódios. A velocidade mantém o passo físico de 1/60 s.

No primeiro treino deixa **Treino continuar desativado**. Para continuar, ativa-o: o número de passos é adicional. PPO pode ultrapassar ligeiramente o pedido para terminar o bloco de recolha. SAC começa as atualizações depois de 1000 passos. PPO/LSTM alternam recolha e atualizações, podendo haver pausas visíveis.

Cada arranque cria `experiencias/<algoritmo>/<data-id>/` com:

- `configuracao.json`: opções, versões, hashes do código, contexto da pista, estado e duração real.
- `logs/episodios.csv`: episódios e seeds, sem substituir execuções anteriores.
- `logs/tensorboard/`: curvas de aprendizagem quando TensorBoard está instalado.
- `modelos/`: checkpoints e atores dessa execução.

A pasta `ml/pesos/` contém a versão mais recente publicada pelo treino, usada pelas cenas de condução. A execução arquivada mantém os seus próprios ficheiros. As gravações periódicas substituem o checkpoint mais recente dentro da mesma execução; não existe ainda seleção automática de "melhor modelo".

PPO: ZIP completo + JSON do ator/crítico. SAC: ZIP + replay.pkl + JSON do ator. LSTM: ZIP. Um PPO antigo só em JSON permite recuperar pesos, mas não o otimizador nem o contador. Retomar qualquer modelo inicia um novo episódio; não reproduz exatamente a posição, o RNG e a sequência da execução interrompida. Carregar apenas checkpoints/replays de origem conhecida.

Para manter uma versão escolhida na demonstração, copia os ficheiros correspondentes de uma execução para `ml/pesos/`, com o treino parado. Os três ficheiros SAC devem pertencer ao mesmo checkpoint. Uma interrupção abrupta pode deixar esse conjunto incompleto; não há transação atómica entre ficheiros.

## Avaliar para o relatório

Ver `docs/avaliacao.md`. A cena `avaliacao.tscn` abre por omissão o conjunto **validacao**. O conjunto **teste** deve ser reservado para depois de fixar configurações e modelos. Não há aprendizagem durante a avaliação. A demonstração `comparacao.tscn` mantém as regras de campeonato e para todos quando há um vencedor; não é a fonte de tempos independentes do relatório.

## Organização

- `scripts/carro`, `scripts/pista`, `scripts/corrida`, `scripts/ui`: simulação e visualização.
- `scripts/rl`: observações, recompensa e regras dos episódios.
- `ml/controladores/treino_ppo.py`: ponte comum Godot/Python; nome mantido por compatibilidade.
- `ml/treino/`: gestão do treino, registos CSV e arquivo das execuções.
- `ml/modelos/`: exportação, gravação e inferência dos modelos.
- `ml/pesos/`: modelos escolhidos para condução e retoma.
- `ml/logs/`: registos históricos; novos registos ficam em cada experiência.
- `ml/ambiente/`: comunicação com o simulador.
- `ml/controladores/corrida_*.py`: controladores de demonstração.
- `ml/avaliacao/`, `configuracoes/pistas.json`: avaliação e pistas reservadas.
- `docs/Projeto Redes.pdf`: proposta original.
- `ml/testes/`: testes de retoma, exportação, memória e avaliação.

O código Python pertence ao pacote `ml`. Os controladores carregados pelo Godot preparam o caminho da raiz para importar esse pacote, mesmo quando o editor é aberto fora da pasta do projeto. `addons`, `.godot` e `__pycache__` não pertencem ao Git. `experiencias` e `resultados` também ficam fora do Git por omissão: preservar cópias externas e publicar explicitamente os artefactos selecionados. ZIP e JSON de `ml/pesos` podem ser versionados se forem modelos escolhidos; o replay é ignorado pelo tamanho. O código de uma branch não leva automaticamente todos os modelos locais para os colegas.

Os dados anteriores à reorganização foram copiados para `experiencias/legado_<data>/`. Os registos antigos foram transferidos para `ml/logs/` e os modelos para `ml/pesos/`, sem alterar os seus conteúdos. `.validation/` contém testes técnicos, não resultados finais. Nenhum stash foi removido.

## Testes

Usar o Python embutido, sem depender de `.validation/deps`:

```powershell
& ".\addons\py4godot\cpython-3.14.4-windows64\python\python.exe" -s -B -m unittest discover -s ml/testes -v
```

Ainda é necessário avaliar várias seeds de treino (por exemplo 42, 43 e 44), guardar cada execução e reportar variabilidade. Os testes técnicos não demonstram que o agente conduz bem.

A estrutura aproveita os commits `368809f` e `5495ead` do grupo. O CSV simples por episódio introduzido pelo colega é mantido, agora separado por execução para não perder históricos. O SAC que veio da branch também foi preservado em `experiencias/integracao_colega/`; o modelo local continua selecionado em `ml/pesos/`.
