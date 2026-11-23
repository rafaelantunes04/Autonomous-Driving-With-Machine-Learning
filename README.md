# Condução Autónoma com Machine Learning

Simulador 2D de corridas feito em **Godot**, onde o carro pode ser controlado **à mão (setas / WASD)** ou por um **script Python** (através do addon [py4godot](https://github.com/niklas2902/py4godot)). A pista é gerada aleatoriamente e o objetivo é escrever em Python a "inteligência" que conduz o carro.

---

## 1. Instalação

### 1.1 Requisitos
- [Godot 4](https://godotengine.org/download) (o projeto foi criado com a versão indicada em `project.godot`, renderer *GL Compatibility*).
- Python 3 (só para correr o script que instala o addon).

### 1.2 Instalar o addon py4godot
A pasta `addons/` **não vem no repositório** (está no `.gitignore`), por isso cada pessoa tem de a instalar uma vez:

```bash
pip install tqdm
python download_addon.py
```

Isto descarrega o py4godot, cria a pasta `addons/py4godot/` e instala o `requirements.txt` (stable-baselines3, torch, ...) no Python do próprio py4godot, com o pip incluído. Se o addon já existir só faz a parte das dependências, por isso podes voltar a correr o script a qualquer altura.

Opções úteis:

```bash
python download_addon.py --force                 # volta a descarregar e substitui
python download_addon.py --sem-deps              # não instala o requirements.txt (só para conduzir)
python download_addon.py --url "<url do .zip>"   # usa uma release específica
```

> ⚠️ **Versões:** as releases do py4godot são feitas para uma versão concreta do Godot (ex.: a release `4.6-alpha17` é para o Godot 4.6). O script usa a release mais recente (`latest`). Se o addon não carregar, confirma que a tua versão do Godot corresponde à release do py4godot e, se for preciso, passa o URL certo com `--url` (ver [releases](https://github.com/niklas2902/py4godot/releases)).

### 1.3 Abrir no Godot
1. Abre o Godot → **Importar** → escolhe o ficheiro `project.godot` desta pasta.
2. Na primeira vez o Godot demora um pouco a importar os ficheiros.
3. Carrega em **F5** para correr (a cena principal é `cenas/track.tscn`).

Não é preciso ativar o addon em *Project Settings → Plugins*: basta ele estar na pasta `addons/`.

---

## 2. Como jogar / controlos

| Tecla | O que faz |
|---|---|
| ↑ ↓ ← → ou W A S D | Conduz o carro (só em modo manual) |
| **R** | Gera uma pista nova (seed aleatória, aparece na consola) |
| **Enter / Espaço** | Recomeça na mesma pista |
| **C** | Alterna entre vista geral da pista e câmara a seguir o carro |

O HUD mostra velocidade, direção das rodas, rumo, tempo, batidas e voltas (última e melhor).

---

## 3. Controlar o carro com Python

Cada carro é conduzido por um **controlador**: um script que se torna nó filho do carro e lhe dá os comandos a cada tick de física. Quem escolhe o controlador de cada carro é o `_ready()` de `scripts/corrida/corrida.gd`, onde cada carro é uma linha com `Carro.instanciate(...)` (ver 4.0). Por omissão correm 3 carros: um por teclado, um com o exemplo `exemplo_simples.py` e um com o modelo PPO.

Para o Python conduzir um carro:

1. Abre `scripts/corrida/corrida.gd` e, no `_ready()`, troca o controlador de um carro (ou acrescenta uma linha):
   ```gdscript
   Carro.instanciate(Color.RED, load("res://main.py"), "Python")
   ```
2. O segundo argumento é o script que conduz o carro (o terceiro é o nome): `ControladorTeclado`, um `.gd` teu, ou `load("res://main.py")`.
3. Corre o jogo (F5). Na consola deve aparecer `[main] pronto`.

Cada participante pode ter um script diferente (outro `.py`, ou um `.gd` que herde de `ControladorCarro`). Um participante sem `controlador` fica parado.

> O algoritmo de aprendizagem (e a rede neuronal, se houver) vive dentro do próprio script do controlador.

### 3.1 Que ficheiros editar

| Ficheiro | É para editar? | Para que serve |
|---|---|---|
| **`main.py`** | ✅ **Sim, é aqui que trabalhas** | Contém a lógica de condução (a "inteligência" do carro) |
| `exemplo_simples.py` | Para copiares | Exemplo mínimo de controlador (usado pelo carro Vermelho) |
| `ml/ambiente/carro_api.py` | Só se quiseres alargar a API | Camada simples para dar comandos e ler o estado do carro |
| `ml/` (ver `ml/README.md`) | Não | Treino por reforço, modelos e pesos (ver 3.6) |
| `ml/controladores/corrida_ppo.py` | Não | Conduz com o modelo PPO treinado (ver 3.5) |
| `telemetria_ui.py` | Não | Janela Tkinter de telemetria, usada pelo `main.py` |
| `ml/constantes.py` | Só se mudares o treino | Valores partilhados com o GDScript (ações por tick, nº de observações) |
| `download_addon.py` | Não | Instala o py4godot |

O `main.py` de exemplo (que também abre uma janela de telemetria; desliga-a com `USAR_TELEMETRIA = False`) apenas acelera durante 1 s, recua até aos 3,5 s e depois larga o pedal, só para demonstrar os comandos. **Apaga o conteúdo de `_physics_process` e escreve a tua lógica.**

### 3.2 Estrutura do `main.py`

```python
from py4godot.classes import gdclass
from py4godot.classes.Node import Node
from carro_api import CarroAPI


@gdclass
class main(Node):                      # mantém o nome da classe igual ao do ficheiro

	def _ready(self) -> None:
		# corre uma vez; o nó pai é o carro
		self.carro = CarroAPI(self.get_parent())

	def _physics_process(self, delta: float) -> None:
		# corre a cada tick de física (~60x por segundo): decide aqui o que fazer
		self.carro.acelerar(0.8)
		self.carro.virar(0.0)
```

Depois de gravares, volta a correr o jogo (F5) para ver as alterações.

### 3.3 O que a API (`CarroAPI`) disponibiliza

**Comandos** (chama-os a cada tick de física):

| Comando | Descrição |
|---|---|
| `carro.acelerar(forca)` | Pedal para a frente, de `0` (solto) a `1` (a fundo) |
| `carro.recuar(forca)` | Pedal para trás, de `0` a `1`. Trava se ainda vai para a frente; engata marcha-atrás quando está quase parado |
| `carro.virar(valor)` | Volante de `-1` (esquerda) a `+1` (direita) |
| `carro.largar_pedal()` | Força a 0 (o carro vai abrandando) |
| `carro.parar()` | Larga o pedal e põe o volante a direito |

Os valores fora do intervalo são limitados automaticamente.

**Leitura do estado:**

| Propriedade | Descrição |
|---|---|
| `carro.velocidade` | km/h na direção da frente (negativa em marcha-atrás) |
| `carro.rumo` | Graus de 0 a 360 para onde o carro aponta (0 = eixo +X) |
| `carro.angulo_rodas` | Ângulo das rodas da frente em graus (positivo = direita) |
| `carro.sensores` | Dicionário com os 5 raycasts (`esquerda_2`, `esquerda`, `frente`, `direita`, `direita_2`), de `0` (parede encostada) a `1` (livre) |
| `carro.observacao` | As 7 observações que o modelo PPO usa |

O carro não lê o teclado por si: só obedece ao seu controlador. Por isso, um carro conduzido por Python não precisa de desligar nada.

### 3.4 O que (ainda) **não** está disponível em Python
O Python vê a velocidade, o rumo, as rodas e os 5 sensores, mas **não** a posição do carro, o nº de batidas ou voltas, nem consegue reiniciar a corrida (só o treino o faz, via `CarroTreinoAPI`). Para expor mais coisas, de forma simples:

1. Em `scripts/carro/carro.gd`, cria uma propriedade com *getter* de tipo simples (`float`, `int`, `bool`…), como as `estado_*` que já existem. Por exemplo `estado_em_colisao` (o carro guarda isto em `_em_colisao`).
2. Em `carro_api.py`, adiciona uma propriedade que a lê com `self._ler("estado_em_colisao")`.
3. Usa-a no `main.py` com `self.carro.em_colisao`.

O carro também já tem `reiniciar(posicao, rotacao)` em GDScript, que podes expor da mesma forma.

### 3.5 Conduzir com o modelo PPO treinado

`ml/controladores/corrida_ppo.py` é um controlador py4godot (como o `main.py`) que corre a política PPO-MLP em Python puro, sem torch. Lê os pesos de `ml/pesos/ppo_mlp.json`, que é escrito pelo treino (ver 3.6). Em `corrida.gd` o carro Verde usa `load("res://ml/controladores/corrida_ppo.py")`. Corre o jogo (F5): na consola aparece `[corrida_ppo] pronto, pesos em ...`.

As 7 observações (velocidade, ângulo das rodas e 5 raycasts) são calculadas em GDScript (`scripts/rl/observacao_rl.gd`) e lidas com `carro.observacao`. Um `ppo_mlp.json` antigo (8 entradas) já não serve: o `corrida_ppo.py` avisa e fica parado. Treina de novo, sem `TREINO_CONTINUAR`. O `exemplo_simples.py` continua a ser o exemplo simples.

### 3.6 Treinar um modelo (dentro do Godot, sem TCP)

O treino corre na mesma cena da corrida (`cenas/track.tscn`) em modo treino: só há um carro, conduzido por `ml/controladores/treino_ppo.py`. O SB3 corre numa thread do Python do py4godot e o jogo faz de simulador (recompensa e fim de episódio em `scripts/rl/treino_rl.gd`).

1. Instala as dependências no Python do py4godot: `python download_addon.py` já o faz (ou volta a correr se falhou).
2. Escolhe o modelo e a duração com variáveis de ambiente (opcionais): `TREINO_MODELO` = `ppo_mlp` (por omissão), `ppo_lstm` ou `sac_mlp`; `TREINO_PASSOS` = `100000` por omissão; `TREINO_CONTINUAR` = `1` para continuar a treinar a partir de `ml/pesos/ppo_mlp.json` (só `ppo_mlp`).
3. Em linha de comandos: `godot --headless --path . -- --treino`. Para treinar com o editor, põe `modo_treino` a ligado no nó `Corrida` de `cenas/track.tscn` (ou *Project Settings → Application → Run → Main Run Args* = `--treino`) e corre com F5.
4. No fim escreve os pesos em `ml/pesos/ppo_mlp.json` (para `ppo_lstm` e `sac_mlp` guarda `ml/pesos/<modelo>.zip` do SB3) e fecha o jogo. Um treino do zero guarda antes o modelo anterior em `ml/pesos/ppo_mlp.anterior.json`. O `corrida_ppo.py` passa logo a usar o modelo novo.

A velocidade da simulação é `velocidade_treino` no nó `Corrida` (1 = tempo real; por omissão 20). Os registos ficam em `ml/logs/`.

---

## 4. Editar o jogo no Godot

### 4.0 Criar carros por código: `Carro.instanciate()`

Um carro completo (física, cor, controlador e estatísticas) cria-se numa linha, no `_ready()` da `Corrida`:

```gdscript
Carro.instanciate(Color.YELLOW, ControladorTeclado, "Amarelo")
Carro.instanciate(Color.RED, load("res://main.py"), "Python")
Carro.instanciate()   # sem argumentos = carro branco de teclado
```

`Carro.instanciate(cor, script_controlador, nome)` — a cor e o script são o que importa; sem nome o carro chama-se "Carro N". O carro é criado na cena atual e entra no grupo `carros`, que a `Corrida` usa para ligar o HUD e a câmara. Cada carro traz consigo o controlador (`carro.controlador`) e as estatísticas (`carro.estatisticas`: batidas, tempo, voltas).

### 4.1 Parâmetros sem mexer em código
Seleciona o nó e altera os valores no **Inspetor** (painel da direita).

**Carro** → os parâmetros de física são `@export` de `scripts/carro/carro.gd`: abre `cenas/carro.tscn`, seleciona o nó do carro e altera-os no Inspetor. Estão agrupados:

| Grupo | O que controla |
|---|---|
| Motor | Potência do motor e do travão, velocidade máxima (frente e marcha-atrás), tempo de resposta do acelerador |
| Resistências | Atrito de rolamento e arrasto do ar |
| Direção | Ângulo máximo das rodas, quanto diminui a alta velocidade, suavidade, distância entre eixos |
| Aderência | Aderência a baixa/alta velocidade e velocidade a partir da qual derrapa |
| Colisões | Velocidade perdida numa batida de frente e travagem ao encostar à parede |
| Velocímetro | Conversão pixels → km/h (só afeta o que é mostrado) |

**Corrida** → abre `cenas/track.tscn` e seleciona o nó `Corrida`:

| Parâmetro | O que faz |
|---|---|
| `partida_sobreposta` | `true` = todos os carros partem do mesmo ponto; `false` = partem em grelha |
| `colisao_entre_carros` | Se os carros se empurram (usa com `partida_sobreposta` desligado) |
| `voltas_para_vencer` / `tempo_maximo` / `corridas_avaliacao` | Regras mostradas no HUD |

**Pista** → seleciona o nó `Pista` (filho de `Corrida`):

| Parâmetro | O que faz |
|---|---|
| `path` | Path2D a usar como pista (ver "Desenhar a pista com um Path2D", abaixo). Vazio = procura automática |
| `largura` | Largura da pista |
| `semente` | Seed da pista aleatória (mesma seed = mesma pista) |
| `num_pontos` | Nº de pontos de controlo (mais pontos = pista mais complexa) |
| `raio_min` / `raio_max` | Tamanho da pista (escalam com `num_pontos`) |

> Mesma *seed* = mesma pista. Isto é útil para comparar versões do teu controlador na mesma pista. Para fixar uma pista, muda `semente` na `Pista`.

#### Desenhar a pista com um Path2D

Em vez da pista aleatória, podes desenhar o percurso à mão:

1. Adiciona um nó **Path2D** à cena (filho da `Pista`, ou onde quiseres) e desenha a curva com os pontos no editor. Mínimo 3 pontos.
2. Se o Path2D não for filho da `Pista`, põe-no no grupo `pista_path` ou arrasta-o para o campo `path` da `Pista`.
3. A `Pista` encontra-o sozinha e preenche o asfalto, as bordas e as paredes à volta da curva. No editor atualiza enquanto mexes nos pontos.

Notas: um Path2D aberto é fechado automaticamente; se a curva for apertada demais para a `largura`, aparece um aviso na consola; um `Marker2D` chamado `Partida`, filho do Path2D, põe a linha de partida junto a ele. Com um Path2D, a tecla **R** não gera pista nova.

### 4.2 Estrutura do projeto

```
.
├── main.py                 ← controlador Python de exemplo, com telemetria (EDITAR AQUI)
├── exemplo_simples.py      ← controlador Python mínimo
├── telemetria_ui.py        ← janela Tkinter de telemetria
├── ml/                     ← treino, modelos, pesos e controladores de ML (ver ml/README.md)
├── download_addon.py       ← instala o py4godot
├── project.godot           ← configuração do projeto Godot
├── cenas/
│   ├── track.tscn          ← cena principal (Corrida, Pista, câmara, HUD)
│   └── carro.tscn          ← cena do carro
└── scripts/
	├── carro/carro.gd                 ← física do carro + Carro.instanciate()
	├── carro/controlador_carro.gd     ← base dos controladores GDScript
	├── carro/controlador_teclado.gd   ← controlador por teclado
	├── pista/pista.gd                 ← geometria da pista (Path2D ou aleatória)
	├── pista/gerador_pista.gd         ← geração aleatória (devolve uma Curve2D)
	├── pista/geometria_pista.gd       ← bordas e validação da pista
	├── pista/camara_pista.gd          ← câmara (vista geral / seguir carro)
	├── corrida/corrida.gd             ← campeonato: cria carros, pontos, HUD e câmara
	├── corrida/estatisticas_corrida.gd← batidas, tempo e voltas
	├── rl/observacao_rl.gd            ← as 7 observações e a posição na pista
	├── rl/treino_rl.gd                ← recompensa e fim de episódio
	└── ui/hud.gd                      ← texto no ecrã
```

### 4.3 Convenções importantes
- A **frente do carro é o eixo +X**. Se um dia puseres um sprite, roda o `Sprite2D` (filho) e não o corpo do carro.
- A física corre a ~60 ticks por segundo; o `delta` do `_physics_process` é o tempo entre ticks.
- Só são contadas como **batidas** as colisões com o grupo `paredes`, acima de 3 km/h e com pelo menos 0,25 s entre elas (ajustável em `estatisticas_corrida.gd`).
- Uma **volta** só conta quando o progresso líquido ao longo da pista dá uma volta inteira (a marcha-atrás desconta).

---

## 5. Problemas comuns

| Problema | O que verificar |
|---|---|
| O carro não se mexe | O participante não tem `controlador` (fica parado) ou o script do controlador não carregou |
| O carro não obedece ao Python | O `main.py` tem de estar no campo `controlador` do participante, em `Corrida`, e o nome da classe tem de ser igual ao do ficheiro |
| Erros sobre `py4godot` / o Python não carrega | A pasta `addons/py4godot/` existe? A release do py4godot é compatível com a tua versão do Godot? |
| `[carro_api] set/get ... falhou` | Nome de propriedade errado ao ler/escrever no nó do carro (o erro só aparece uma vez para não encher a consola) |
| `ModuleNotFoundError: tqdm` | Corre `pip install tqdm` antes do `download_addon.py` |
