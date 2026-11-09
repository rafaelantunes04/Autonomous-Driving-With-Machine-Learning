extends ControladorCarro
class_name ControladorTeclado

## Conduz o carro com o teclado. As ações são configuráveis, para dois
## jogadores poderem ter teclas diferentes (Project Settings -> Input Map).

@export var acao_acelerar: StringName = &"ui_up"
@export var acao_travar: StringName = &"ui_down"
@export var acao_esquerda: StringName = &"ui_left"
@export var acao_direita: StringName = &"ui_right"


func _init() -> void:
	nome_modelo = "Manual"


func decidir(_delta: float) -> Vector2:
	return Vector2(
		Input.get_axis(acao_travar, acao_acelerar),
		Input.get_axis(acao_esquerda, acao_direita))
