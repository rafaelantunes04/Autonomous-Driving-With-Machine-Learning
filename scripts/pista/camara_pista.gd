extends Camera2D
class_name CamaraPista

## Tecla C alterna entre a vista geral da pista e seguir o carro.
## A vista geral é definida pela Track (definir_vista_geral), por isso
## acompanha sempre a pista atual e o tamanho da janela.

@export var zoom_seguir: Vector2 = Vector2(1.4, 1.4)
@export var atraso_posicao: float = 5.0   # menor = mais atraso
@export var atraso_rotacao: float = 2.5   # menor = roda mais devagar atrás do carro
@export var atraso_zoom: float = 4.0

var alvo: Node2D
var seguir: bool = false

var _vista_posicao: Vector2 = Vector2.ZERO
var _vista_zoom: Vector2 = Vector2.ONE


func _ready() -> void:
	ignore_rotation = false   # necessário para a câmara poder rodar


## Guarda a vista geral. Se não estiver a seguir o carro, aplica-a logo.
func definir_vista_geral(posicao_global: Vector2, nivel_zoom: Vector2) -> void:
	_vista_posicao = posicao_global
	_vista_zoom = nivel_zoom
	if not seguir:
		global_position = posicao_global
		zoom = nivel_zoom
		rotation = 0.0


## C alterna entre vista geral e seguir o carro.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		seguir = not seguir


## Move câmara, rotação e zoom suavemente em direção ao alvo atual.
func _physics_process(delta: float) -> void:
	var a_seguir := seguir and alvo != null
	var alvo_pos := alvo.global_position if a_seguir else _vista_posicao
	var alvo_zoom := zoom_seguir if a_seguir else _vista_zoom
	# +90° para o carro aparecer a apontar para cima no ecrã
	var alvo_rot := (alvo.rotation + PI / 2.0) if a_seguir else 0.0

	global_position = global_position.lerp(alvo_pos, 1.0 - exp(-atraso_posicao * delta))
	rotation = lerp_angle(rotation, alvo_rot, 1.0 - exp(-atraso_rotacao * delta))
	zoom = zoom.lerp(alvo_zoom, 1.0 - exp(-atraso_zoom * delta))
