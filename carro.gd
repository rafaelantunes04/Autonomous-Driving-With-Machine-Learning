extends CharacterBody2D

# --- Configuração (ajusta no Inspetor) ---
@export var rotacao_sprite: float = 90.0       # compensa a orientação da imagem (graus)
@export var potencia_motor: float = 900.0      # aceleração para a frente
@export var potencia_travao: float = 600.0     # travagem / marcha-atrás
@export var velocidade_max: float = 600.0
@export var velocidade_max_re: float = 200.0
@export var atrito: float = 0.8                # resistência passiva (0 = nenhuma)
@export var angulo_direcao: float = 35.0       # ângulo máximo das rodas (graus)
@export var distancia_eixos: float = 60.0      # distância entre eixo da frente e de trás
@export var aderencia_rapida: float = 0.9      # aderência a baixa velocidade (0-1)
@export var aderencia_derrapagem: float = 0.4  # aderência a alta velocidade (0-1)
@export var velocidade_derrapagem: float = 400.0

var aceleracao: Vector2 = Vector2.ZERO
var direcao_rodas: float = 0.0


func _ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	aceleracao = Vector2.ZERO
	ler_input()
	aplicar_atrito(delta)
	calcular_direcao(delta)

	velocity += aceleracao * delta
	move_and_slide()


func ler_input() -> void:
	# Direção das rodas
	var virar := Input.get_axis("ui_left", "ui_right")
	direcao_rodas = -virar * deg_to_rad(angulo_direcao)

	# Acelerar
	if Input.is_action_pressed("ui_up"):
		aceleracao = -transform.x * potencia_motor

	# Travar / marcha-atrás
	if Input.is_action_pressed("ui_down"):
		aceleracao = -transform.x * -potencia_travao


func aplicar_atrito(delta: float) -> void:
	# Para completamente quando a velocidade é muito baixa
	if velocity.length() < 5.0 and aceleracao == Vector2.ZERO:
		velocity = Vector2.ZERO
		return

	var forca_atrito := velocity * -atrito
	var arrasto := velocity * velocity.length() * -0.001
	aceleracao += forca_atrito + arrasto


func calcular_direcao(delta: float) -> void:
	# Modelo de bicicleta: posição das rodas da frente e de trás
	var roda_tras := position - transform.x * distancia_eixos / 2.0
	var roda_frente := position + transform.x * distancia_eixos / 2.0

	roda_tras += velocity * delta
	roda_frente += velocity.rotated(direcao_rodas) * delta

	var nova_direcao := (roda_frente - roda_tras).normalized()

	# Aderência diminui com a velocidade (derrapagem)
	var aderencia := aderencia_rapida
	if velocity.length() > velocidade_derrapagem:
		aderencia = aderencia_derrapagem

	var d := nova_direcao.dot(velocity.normalized())

	if d > 0:
		# A andar para a frente
		velocity = velocity.lerp(nova_direcao * min(velocity.length(), velocidade_max), aderencia)
	elif d < 0:
		# A andar para trás
		velocity = -nova_direcao * min(velocity.length(), velocidade_max_re)

	rotation = nova_direcao.angle()
