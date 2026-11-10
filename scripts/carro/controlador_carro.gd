extends Node
class_name ControladorCarro

## Base dos controladores GDScript. Tem de ser filho de um Carro: a cada tick de
## física chama decidir() e escreve o resultado em input_acel / input_dir.
##
## Esta classe usada tal e qual é um controlador "nulo" (o carro fica parado).
## Para um controlador novo (teclado, regras, rede neuronal, ...), herda desta
## classe e redefine decidir(). Um script Python (ex.: main.py) não precisa de
## herdar daqui: basta ser um nó filho do carro e escrever os mesmos inputs
## através do CarroAPI.
##
## Se o controlador for um agente de IA, o algoritmo e a rede ficam dentro do
## próprio script; nome_modelo é só o texto mostrado no HUD.

@export var nome_modelo: String = ""

var carro: Carro


func _ready() -> void:
	carro = get_parent() as Carro
	if carro == null:
		push_error("%s tem de ser filho de um Carro." % name)
		set_physics_process(false)
		return
	# Corre antes do carro, para o comando aplicar-se no mesmo tick
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	var comandos := decidir(delta)
	carro.input_acel = clampf(comandos.x, -1.0, 1.0)
	carro.input_dir = clampf(comandos.y, -1.0, 1.0)


## Devolve Vector2(acelerar, virar), ambos em [-1, 1]:
## acelerar +1 = acelera, -1 = trava/marcha-atrás; virar +1 = direita, -1 = esquerda.
func decidir(_delta: float) -> Vector2:
	return Vector2.ZERO
