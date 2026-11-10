# Condução Autónoma com Machine Learning

A cena principal, `cenas/track.tscn`, abre o campeonato do PPO com F5 quando a
`.venv` e o modelo `modelos/ppo_mlp.zip` estão disponíveis. Os comandos de
treino e corrida também usam esta cena por omissão. Para instalar as dependências
na `.venv`, usa `python -m pip install -r requirements.txt`.

As instruções sobre `Corrida`, `Pista` e `CarroConfig` abaixo descrevem a cena
`cenas/corrida_rafael.tscn`. Abre essa cena e executa-a com F6 para testar
essa estrutura. O traçado de Estoril está em `cenas/pista_estoril.tscn`.

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

Isto descarrega o py4godot e cria a pasta `addons/py4godot/`.

Opções úteis:

```bash
python download_addon.py --force                 # volta a descarregar e substitui
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

Cada carro é conduzido por um **controlador**: um script que se torna nó filho do carro e lhe dá os comandos a cada tick de física. Quem escolhe o controlador de cada carro é o `_ready()` de `scripts/corrida/corrida.gd`, onde cada carro é uma linha com `Carro.instanciate(...)` (ver 4.0). Por omissão correm 3 carros controlados pelo teclado.

Para o Python conduzir um carro:

1. Abre `scripts/corrida/corrida.gd` e, no `_ready()`, troca o controlador de um carro (ou acrescenta uma linha):
   ```gdscript
   Carro.instanciate(Carro.criar_config(Color.RED, load("res://main.py"), "Python"))
   ```
2. O segundo argumento é o script que conduz o carro: `ControladorTeclado`, um `.gd` teu, ou `load("res://main.py")`.
3. Corre o jogo (F5). Na consola deve aparecer `[main] pronto`.

Cada participante pode ter um script diferente (outro `.py`, ou um `.gd` que herde de `ControladorCarro`). Um participante sem `controlador` fica parado.

> O algoritmo de aprendizagem (e a rede neuronal, se houver) vive dentro do próprio script do controlador. Se o script tiver uma propriedade `nome_modelo` (texto), o HUD mostra-a ao lado do nome do carro.

### 3.1 Que ficheiros editar

| Ficheiro | É para editar? | Para que serve |
|---|---|---|
| **`main.py`** | ✅ **Sim, é aqui que trabalhas** | Contém a lógica de condução (a "inteligência" do carro) |
| `carro_api.py` | Só se quiseres alargar a API | Camada simples para dar comandos e ler o estado do carro |
| `download_addon.py` | Não | Instala o py4godot |

O `main.py` de exemplo apenas acelera durante 1 s, recua até aos 3,5 s e depois larga o pedal, só para demonstrar os comandos. **Apaga o conteúdo de `_physics_process` e escreve a tua lógica.**

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

O carro não lê o teclado por si: só obedece ao seu controlador. Por isso, um carro conduzido por Python não precisa de desligar nada.

### 3.4 O que (ainda) **não** está disponível em Python
Neste momento o Python **não consegue** ver a pista nem o resto do jogo: não há sensores (raios/distância às paredes), posição do carro, nº de batidas ou voltas, nem reiniciar a corrida. Para um agente de machine learning isto vai ser preciso adicionar. Como fazer, de forma simples:

1. Em `scripts/carro/carro.gd`, cria uma propriedade com *getter* de tipo simples (`float`, `int`, `bool`…), como as `estado_*` que já existem. Por exemplo `estado_em_colisao`.
2. Em `carro_api.py`, adiciona uma propriedade que a lê com `self._ler("estado_em_colisao")`.
3. Usa-a no `main.py` com `self.carro.em_colisao`.

O carro também já tem `reiniciar(posicao, rotacao)` em GDScript, que podes expor da mesma forma.

---

## 4. Editar o jogo no Godot

### 4.0 Criar carros por código: `Carro.instanciate()`

Um carro completo (física, cor, controlador e estatísticas) cria-se numa linha, no `_ready()` da `Corrida`:

```gdscript
Carro.instanciate(Carro.criar_config(Color.YELLOW, ControladorTeclado, "Amarelo"))
Carro.instanciate(Carro.criar_config(Color.RED, load("res://main.py"), "Python"))
Carro.instanciate()   # sem config = carro branco de teclado
```

`Carro.criar_config(cor, controlador, nome, fisica)` — só a cor e o controlador são importantes; `nome` e `fisica` (um `CarroConfig`) são opcionais. O carro é criado na cena atual (ou no nó passado em `Carro.instanciate(config, pai)`) e entra no grupo `carros`, que a `Corrida` usa para ligar o HUD e a câmara. Cada carro traz consigo o controlador (`carro.controlador`) e as estatísticas (`carro.estatisticas`: batidas, tempo, voltas).

### 4.1 Parâmetros sem mexer em código
Seleciona o nó e altera os valores no **Inspetor** (painel da direita).

**Carro** → os parâmetros de física estão num recurso `CarroConfig` (`scripts/carro/carro_config.gd`). Podes criar um novo no Inspetor (e guardá-lo em `.tres`, uma variante por ficheiro) e passá-lo como 4.º argumento de `Carro.criar_config()`. Estão agrupados:

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
├── main.py                 ← controlador Python (EDITAR AQUI)
├── carro_api.py            ← API simples do carro para Python
├── download_addon.py       ← instala o py4godot
├── project.godot           ← configuração do projeto Godot
├── cenas/
│   ├── track.tscn          ← cena principal (Corrida, Pista, câmara, HUD)
│   └── carro.tscn          ← cena do carro
└── scripts/
	├── carro/carro.gd                 ← física do carro + Carro.instanciate()
	├── carro/carro_config.gd          ← parâmetros do carro (resource)
	├── carro/controlador_carro.gd     ← base dos controladores GDScript
	├── carro/controlador_teclado.gd   ← controlador por teclado
	├── pista/pista.gd                 ← geometria da pista (Path2D ou aleatória)
	├── pista/gerador_pista.gd         ← geração aleatória (devolve uma Curve2D)
	├── pista/geometria_pista.gd       ← bordas e validação da pista
	├── pista/camara_pista.gd          ← câmara (vista geral / seguir carro)
	├── corrida/corrida.gd             ← chama Carro.instanciate() e liga HUD e câmara
	├── corrida/participante_config.gd ← nome, cor, config e controlador de um carro
	├── corrida/estatisticas_corrida.gd← batidas, tempo e voltas
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
