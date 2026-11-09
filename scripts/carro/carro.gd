extends CharacterBody2D
class_name Carro

## Física do carro. Os parâmetros vêm de um CarroConfig (resource) e quem o
## conduz é um nó filho (ver ControladorCarro / ControladorTeclado, ou um script
## Python como o main.py): esse nó escreve input_acel e input_dir a cada tick.
## Câmara, HUD e estatísticas vivem noutros scripts.
##
## CONVENÇÃO: a frente do carro é +X (transform.x). Se a imagem do sprite
## apontar para cima, roda o Sprite2D filho 90° (e não o corpo), para a física
## ficar sempre consistente.

## Emitido no primeiro frame de contacto com qualquer corpo.
signal colidiu(colisor: Node, velocidade_kmh: float)

## Parâmetros de física. Se ficar vazio, usa os valores por omissão do CarroConfig.
@export var config: CarroConfig

# Comandos, ambos em [-1, 1]. Sem controlador ficam a 0 (carro parado).
var input_acel: float = 0.0   ## +1 acelera, -1 trava/marcha-atrás
var input_dir: float = 0.0    ## +1 direita, -1 esquerda

var em_colisao: bool = false
var acelerador: float = 0.0   ## acelerador suavizado
var direcao_rodas: float = 0.0

## Velocidade total (qualquer direção) em km/h.
var velocidade_kmh: float:
	get:
		return velocity.length() / config.pixels_por_kmh

# Estado em tipos simples, para controladores externos (Python) lerem com get().
var estado_velocidade_kmh: float:   ## na direção da frente; negativo = marcha-atrás
	get:
		return velocity.dot(transform.x) / config.pixels_por_kmh
var estado_angulo_rodas: float:     ## graus; positivo = direita
	get:
		return rad_to_deg(direcao_rodas)
var estado_rumo: float:             ## graus, 0 a 360 (0 = +X)
	get:
		return fposmod(rotation_degrees, 360.0)


func _ready() -> void:
	if config == null:
		config = CarroConfig.new()


func _physics_process(delta: float) -> void:
	velocity += _calcular_aceleracao(delta) * delta
	_calcular_direcao(delta)
	velocity = velocity.limit_length(config.velocidade_max)

	var vel_antes := velocity
	move_and_slide()

	_detetar_colisoes(vel_antes, delta)


# ------------------------------------------------------------------ API pública

## Coloca o carro parado numa posição/rotação global, sem herdar estado anterior.
func reiniciar(nova_posicao: Vector2, nova_rotacao: float) -> void:
	global_position = nova_posicao
	global_rotation = nova_rotacao
	velocity = Vector2.ZERO
	acelerador = 0.0
	direcao_rodas = 0.0
	input_acel = 0.0
	input_dir = 0.0
	em_colisao = false


# ------------------------------------------------------------------ Interno

## No primeiro frame de contacto emite `colidiu` e tira velocidade conforme o
## quão de frente foi a batida; enquanto encostado, vai travando continuamente.
func _detetar_colisoes(vel_antes: Vector2, delta: float) -> void:
	var n := get_slide_collision_count()
	if n > 0:
		var colisao := get_slide_collision(0)
		if not em_colisao:
			var frontal := clampf(-vel_antes.normalized().dot(colisao.get_normal()), 0.0, 1.0)
			velocity *= 1.0 - config.perda_impacto * frontal
			colidiu.emit(colisao.get_collider(), vel_antes.length() / config.pixels_por_kmh)
		velocity *= exp(-config.atrito_parede * delta)
	em_colisao = n > 0


## Calcula a aceleração: motor/travão/marcha-atrás menos as resistências.
func _calcular_aceleracao(delta: float) -> Vector2:
	var frente := transform.x
	var vel_frente := velocity.dot(frente)

	# Acelerador progressivo: sobe devagar, desce mais depressa
	var taxa := (1.0 / config.tempo_acelerador) if absf(input_acel) > absf(acelerador) else (1.0 / config.tempo_largar)
	acelerador = move_toward(acelerador, input_acel, taxa * delta)

	var forca := 0.0
	if acelerador > 0.0:
		# A força do motor cai à medida que se aproxima da velocidade máxima
		var restante := clampf(1.0 - vel_frente / config.velocidade_max, 0.0, 1.0)
		forca = acelerador * config.potencia_motor * restante
	elif acelerador < 0.0:
		if vel_frente > 10.0:
			forca = acelerador * config.potencia_travao  # travagem
		else:
			var restante_re := clampf(1.0 - (-vel_frente) / config.velocidade_max_re, 0.0, 1.0)
			forca = acelerador * config.potencia_motor * 0.5 * restante_re  # marcha-atrás

	# Sem input e quase parado: pára de vez
	if velocity.length() < 5.0 and absf(input_acel) < 0.01:
		velocity = Vector2.ZERO
		return Vector2.ZERO

	var aceleracao := frente * forca
	aceleracao += -velocity * config.atrito_rolamento
	aceleracao += -velocity * velocity.length() * config.arrasto
	return aceleracao


## Modelo de bicicleta: roda as rodas, calcula a nova direção do carro e faz a
## velocidade segui-la, com menos aderência quanto mais depressa se vai.
func _calcular_direcao(delta: float) -> void:
	var velocidade := velocity.length()
	if velocidade < 1.0:
		return

	# Menos ângulo nas rodas quando se vai depressa (mais estável)
	var f := clampf(velocidade / config.velocidade_max, 0.0, 1.0)
	var angulo_max := deg_to_rad(config.angulo_direcao) * lerpf(1.0, config.fator_direcao_alta, f)
	var alvo := input_dir * angulo_max
	direcao_rodas = lerpf(direcao_rodas, alvo, 1.0 - exp(-config.suavidade_direcao * delta))

	# Frente = +X, direita = ângulo positivo
	var roda_tras := position - transform.x * config.distancia_eixos / 2.0
	var roda_frente := position + transform.x * config.distancia_eixos / 2.0
	roda_tras += velocity * delta
	roda_frente += velocity.rotated(direcao_rodas) * delta
	var nova_direcao := (roda_frente - roda_tras).normalized()

	# Aderência diminui gradualmente com a velocidade
	var grip := lerpf(config.aderencia_baixa, config.aderencia_alta,
			smoothstep(config.velocidade_derrapagem * 0.5, config.velocidade_derrapagem * 1.5, velocidade))
	var t := 1.0 - exp(-grip * delta)

	if nova_direcao.dot(velocity.normalized()) > 0.0:
		velocity = velocity.lerp(nova_direcao * minf(velocidade, config.velocidade_max), t)
	else:
		velocity = -nova_direcao * minf(velocidade, config.velocidade_max_re)  # marcha-atrás

	rotation = nova_direcao.angle()
