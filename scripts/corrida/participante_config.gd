extends Resource
class_name ParticipanteConfig

## Um carro da corrida: como é (config), quem o conduz (controlador) e como
## aparece (nome, cor).

@export var nome: String = ""
@export var cor: Color = Color.WHITE

## Parâmetros de física. Vazio = valores por omissão do CarroConfig.
## Cada carro recebe a sua própria cópia, por isso o mesmo .tres pode ser partilhado.
@export var config: CarroConfig

## Script do controlador deste carro (um .gd que herda de ControladorCarro, ou um
## .py como o main.py). É instanciado como nó filho do carro. Vazio = carro parado.
## O modelo de IA, se existir, vive dentro deste script.
@export var controlador: Script
