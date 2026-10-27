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

Por omissão o carro anda com as setas. Para o Python assumir o controlo:

1. Abre `scripts/pista/track.gd`.
2. Na função `_garantir_carro()`, **descomenta** a linha:
   ```gdscript
   _adicionar_controlador_python()   #descomentar para o script python
   ```
3. Corre o jogo (F5). O Godot vai carregar o `main.py` e ligá-lo ao carro. Na consola deve aparecer `Script Python adicionado ao carro` e `[main] pronto`.

Se o ficheiro Python não existir ou não carregar, o jogo avisa na consola e volta às setas.

> Para usar outro ficheiro que não `main.py`, seleciona o nó **Track** em `cenas/track.tscn` e muda a propriedade `classe_controlador_python` (nome do ficheiro **sem** `.py`).

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

Ao criar o `CarroAPI`, o controlo por setas é desligado automaticamente (`controlo_manual = False`).

### 3.4 O que (ainda) **não** está disponível em Python
Neste momento o Python **não consegue** ver a pista nem o resto do jogo: não há sensores (raios/distância às paredes), posição do carro, nº de batidas ou voltas, nem reiniciar a corrida. Para um agente de machine learning isto vai ser preciso adicionar. Como fazer, de forma simples:

1. Em `scripts/carro/carro.gd`, cria uma variável de tipo simples (`float`, `int`, `bool`…) e atualiza-a em `_atualizar_estado()`. Por exemplo `estado_em_colisao`.
2. Em `carro_api.py`, adiciona uma propriedade que a lê com `self._ler("estado_em_colisao")`.
3. Usa-a no `main.py` com `self.carro.em_colisao`.

O carro também já tem `aplicar_comandos(acel, direcao)` e `reiniciar(posicao, rotacao)` em GDScript, que podes expor da mesma forma.

---

## 4. Editar o jogo no Godot

### 4.1 Parâmetros sem mexer em código
Seleciona o nó e altera os valores no **Inspetor** (painel da direita).

**Carro** → abre `cenas/carro.tscn` e seleciona o nó `Carro`. Os parâmetros estão agrupados:

| Grupo | O que controla |
|---|---|
| Motor | Potência do motor e do travão, velocidade máxima (frente e marcha-atrás), tempo de resposta do acelerador |
| Resistências | Atrito de rolamento e arrasto do ar |
| Direção | Ângulo máximo das rodas, quanto diminui a alta velocidade, suavidade, distância entre eixos |
| Aderência | Aderência a baixa/alta velocidade e velocidade a partir da qual derrapa |
| Colisões | Velocidade perdida numa batida de frente e travagem ao encostar à parede |
| Velocímetro | Conversão pixels → km/h (só afeta o que é mostrado) |
| Controlo | `controlo_manual`: `true` = setas, `false` = controlado por código |

**Pista** → abre `cenas/track.tscn` e seleciona o nó `Track`:

| Parâmetro | O que faz |
|---|---|
| `track_width` | Largura da pista |
| `num_points` | Nº de pontos de controlo (mais pontos = pista mais complexa) |
| `min_radius` / `max_radius` | Tamanho da pista (escalam com `num_points`) |
| `car_scene` | Cena usada para o carro |
| `classe_controlador_python` | Nome do ficheiro Python que controla o carro (sem `.py`) |

> Mesma *seed* = mesma pista. Isto é útil para comparar versões do teu controlador na mesma pista. Para fixar uma pista, muda `current_seed` em `track.gd`.

### 4.2 Estrutura do projeto

```
.
├── main.py                 ← controlador Python (EDITAR AQUI)
├── carro_api.py            ← API simples do carro para Python
├── download_addon.py       ← instala o py4godot
├── project.godot           ← configuração do projeto Godot
├── cenas/
│   ├── track.tscn          ← cena principal (pista, câmara, HUD, estatísticas)
│   └── carro.tscn          ← cena do carro
└── scripts/
    ├── carro/carro.gd                 ← física do carro
    ├── pista/track.gd                 ← orquestra a corrida e liga o Python
    ├── pista/gerador_pista.gd         ← geração aleatória da pista
    ├── pista/camara_pista.gd          ← câmara (vista geral / seguir carro)
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
| O carro só anda com as setas | A linha `_adicionar_controlador_python()` em `track.gd` ainda está comentada |
| `Script Python não encontrado...` | `main.py` tem de estar na raiz do projeto (ao lado de `project.godot`) ou o nome em `classe_controlador_python` está errado |
| Erros sobre `py4godot` / o Python não carrega | A pasta `addons/py4godot/` existe? A release do py4godot é compatível com a tua versão do Godot? |
| `[carro_api] set/get ... falhou` | Nome de propriedade errado ao ler/escrever no nó do carro (o erro só aparece uma vez para não encher a consola) |
| `ModuleNotFoundError: tqdm` | Corre `pip install tqdm` antes do `download_addon.py` |
