extends CharacterBody2D
class_name Carro

## Física do carro. Câmara, HUD e estatísticas vivem noutros scripts
## (camara_pista.gd, hud.gd, estatisticas_corrida.gd).
##
## CONVENÇÃO: a frente do carro é +X (transform.x). Se a imagem do sprite
## apontar para cima, roda o Sprite2D filho 90° (e não o corpo), para a física
## ficar sempre consistente.

## Emitido no primeiro frame de contacto com qualquer corpo.
signal colidiu(colisor: Node, velocidade_kmh: float)

@export_group("Motor")
@export var potencia_motor: float = 560.0      ## força máxima a baixa velocidade
@export var potencia_travao: float = 800.0
@export var velocidade_max: float = 600.0
@export var velocidade_max_re: float = 150.0
@export var tempo_acelerador: float = 1.2      ## s para o acelerador ir de 0 a 100%
@export var tempo_largar: float = 0.4          ## s para largar o acelerador

@export_group("Resistências")
@export var atrito_rolamento: float = 0.5
@export var arrasto: float = 0.0006

@export_group("Direção")
@export var angulo_direcao: float = 30.0       ## ângulo máx. das rodas (graus) a baixa velocidade
@export var fator_direcao_alta: float = 0.3    ## fração do ângulo à velocidade máxima
@export var suavidade_direcao: float = 6.0     ## maior = rodas respondem mais depressa
@export var distancia_eixos: float = 60.0

@export_group("Aderência")
## Valores por segundo (independentes da framerate).
@export var aderencia_baixa: float = 12.0
@export var aderencia_alta: float = 3.0
@export var velocidade_derrapagem: float = 400.0

@export_group("Colisões")
@export var perda_impacto: float = 0.6   ## fração da velocidade perdida numa batida de frente (0-1)
@export var atrito_parede: float = 3.0   ## travagem contínua enquanto encostado (maior = trava mais)

@export_group("Velocímetro")
## Só afeta o que é mostrado, não a física. Com os valores acima o carro
## estabiliza perto de 360 px/s, mostrado como 120 km/h (1 km/h = 3 px/s).
@export var pixels_por_kmh: float = 3.0

@export_group("Controlo")
## true  -> o carro lê as setas (ui_up/down/left/right).
## false -> um controlador externo (ex.: main.py via CarroAPI) escreve
##          input_acel / input_dir, ambos em [-1, 1].
@export var controlo_manual: bool = true

var input_acel: float = 0.0   ## +1 acelera, -1 trava/marcha-atrás
var input_dir: float = 0.0    ## +1 direita, -1 esquerda

var em_colisao: bool = false
var acelerador: float = 0.0   ## acelerador suavizado
var direcao_rodas: float = 0.0

# Estado em tipos simples, para controladores externos (Python) lerem com get().
var estado_velocidade_kmh: float = 0.0   ## na direção da frente; negativo = marcha-atrás
var estado_angulo_rodas: float = 0.0     ## graus; positivo = direita
var estado_rumo: float = 0.0             ## graus, 0 a 360 (0 = +X)


func _physics_process(delta: float) -> void:
	if controlo_manual:
		_ler_input()

	velocity += _calcular_aceleracao(delta) * delta
	_calcular_direcao(delta)
	velocity = velocity.limit_length(velocidade_max)

	var vel_antes := velocity
	move_and_slide()

	_detetar_colisoes(vel_antes, delta)
	_atualizar_estado()


# ------------------------------------------------------------------ API pública

## Velocidade total (qualquer direção) em km/h.
func velocidade_kmh() -> float:
	return velocity.length() / pixels_por_kmh


## Atalho para controladores externos (Python, RL, ...). Valores em [-1, 1].
func aplicar_comandos(acel: float, direcao: float) -> void:
	input_acel = clampf(acel, -1.0, 1.0)
	input_dir = clampf(direcao, -1.0, 1.0)


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

## Copia o estado para as variáveis simples lidas pelos controladores externos.
func _atualizar_estado() -> void:
	estado_velocidade_kmh = velocity.dot(transform.x) / pixels_por_kmh
	estado_angulo_rodas = rad_to_deg(direcao_rodas)
	estado_rumo = fposmod(rotation_degrees, 360.0)


## Lê as setas e converte-as em input_acel / input_dir.
func _ler_input() -> void:
	input_acel = Input.get_axis("ui_down", "ui_up")
	input_dir = Input.get_axis("ui_left", "ui_right")


## No primeiro frame de contacto emite `colidiu` e tira velocidade conforme o
## quão de frente foi a batida; enquanto encostado, vai travando continuamente.
func _detetar_colisoes(vel_antes: Vector2, delta: float) -> void:
	var n := get_slide_collision_count()
	if n > 0:
		var colisao := get_slide_collision(0)
		if not em_colisao:
			var frontal := clampf(-vel_antes.normalized().dot(colisao.get_normal()), 0.0, 1.0)
			velocity *= 1.0 - perda_impacto * frontal
			colidiu.emit(colisao.get_collider(), vel_antes.length() / pixels_por_kmh)
		velocity *= exp(-atrito_parede * delta)
	em_colisao = n > 0


## Calcula a aceleração: motor/travão/marcha-atrás menos as resistências.
func _calcular_aceleracao(delta: float) -> Vector2:
	var frente := transform.x
	var vel_frente := velocity.dot(frente)

	# Acelerador progressivo: sobe devagar, desce mais depressa
	var taxa := (1.0 / tempo_acelerador) if absf(input_acel) > absf(acelerador) else (1.0 / tempo_largar)
	acelerador = move_toward(acelerador, input_acel, taxa * delta)

	var forca := 0.0
	if acelerador > 0.0:
		# A força do motor cai à medida que se aproxima da velocidade máxima
		var restante := clampf(1.0 - vel_frente / velocidade_max, 0.0, 1.0)
		forca = acelerador * potencia_motor * restante
	elif acelerador < 0.0:
		if vel_frente > 10.0:
			forca = acelerador * potencia_travao  # travagem
		else:
			var restante_re := clampf(1.0 - (-vel_frente) / velocidade_max_re, 0.0, 1.0)
			forca = acelerador * potencia_motor * 0.5 * restante_re  # marcha-atrás

	# Sem input e quase parado: pára de vez
	if velocity.length() < 5.0 and absf(input_acel) < 0.01:
		velocity = Vector2.ZERO
		return Vector2.ZERO

	var aceleracao := frente * forca
	aceleracao += -velocity * atrito_rolamento
	aceleracao += -velocity * velocity.length() * arrasto
	return aceleracao


## Modelo de bicicleta: roda as rodas, calcula a nova direção do carro e faz a
## velocidade segui-la, com menos aderência quanto mais depressa se vai.
func _calcular_direcao(delta: float) -> void:
	var velocidade := velocity.length()
	if velocidade < 1.0:
		return

	# Menos ângulo nas rodas quando se vai depressa (mais estável)
	var f := clampf(velocidade / velocidade_max, 0.0, 1.0)
	var angulo_max := deg_to_rad(angulo_direcao) * lerpf(1.0, fator_direcao_alta, f)
	var alvo := input_dir * angulo_max
	direcao_rodas = lerpf(direcao_rodas, alvo, 1.0 - exp(-suavidade_direcao * delta))

	# Frente = +X, direita = ângulo positivo
	var roda_tras := position - transform.x * distancia_eixos / 2.0
	var roda_frente := position + transform.x * distancia_eixos / 2.0
	roda_tras += velocity * delta
	roda_frente += velocity.rotated(direcao_rodas) * delta
	var nova_direcao := (roda_frente - roda_tras).normalized()

	# Aderência diminui gradualmente com a velocidade
	var grip := lerpf(aderencia_baixa, aderencia_alta,
			smoothstep(velocidade_derrapagem * 0.5, velocidade_derrapagem * 1.5, velocidade))
	var t := 1.0 - exp(-grip * delta)

	if nova_direcao.dot(velocity.normalized()) > 0.0:
		velocity = velocity.lerp(nova_direcao * minf(velocidade, velocidade_max), t)
	else:
		velocity = -nova_direcao * minf(velocidade, velocidade_max_re)  # marcha-atrás

	rotation = nova_direcao.angle()
