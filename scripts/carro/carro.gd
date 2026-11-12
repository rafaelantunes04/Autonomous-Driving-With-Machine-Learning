extends CharacterBody2D
class_name Carro

#####							FISICA
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
## Só afeta o que é mostrado, não a física.
@export var pixels_por_kmh: float = 3.0

## Emitido no primeiro frame de contacto com qualquer corpo.
signal colidiu(colisor: Node, velocidade_kmh: float)



#####							CONFIGS
@export var nome: String = ""
@export var cor: Color = Color.WHITE
@export var controlador: Node


#####							OUTROS
const CENA := "res://cenas/carro.tscn"
const GRUPO := &"carros"
const CAMADA_PAREDES := 1
const CAMADA_CARROS := 2
var estatisticas: EstatisticasCorrida   ## batidas, tempo e voltas (filho deste nó)


#####							INPUTS
# Comandos, ambos em [-1, 1]. Sem controlador ficam a 0 (carro parado).
var input_acel: float = 0.0   ## +1 acelera, -1 trava/marcha-atrás
var input_dir: float = 0.0    ## +1 direita, -1 esquerda

var em_colisao: bool = false
var acelerador: float = 0.0   ## acelerador suavizado
var direcao_rodas: float = 0.0


#####							SENSORES
@onready var _sensor_front: RayCast2D = $Front_Sensor
@onready var _sensor_right: RayCast2D = $Right_Sensor
@onready var _sensor_right_2: RayCast2D = $Right_Sensor_2
@onready var _sensor_left: RayCast2D = $Left_Sensor
@onready var _sensor_left_2: RayCast2D = $Left_Sensor_2

# Estado dos sensores para a API (retorna um valor normalizado de 0.0 a 1.0)
# 1.0 = Sem obstáculo / Alcance máximo; 0.0 = Colisão imediata na origem do raio.
var estado_sensor_front: float:
	get: return _ler_sensor(_sensor_front)
var estado_sensor_right: float:
	get: return _ler_sensor(_sensor_right)
var estado_sensor_right_2: float:
	get: return _ler_sensor(_sensor_right_2)
var estado_sensor_left: float:
	get: return _ler_sensor(_sensor_left)
var estado_sensor_left_2: float:
	get: return _ler_sensor(_sensor_left_2)


## Velocidade total (qualquer direção) em km/h.
var velocidade_kmh: float:
	get:
		return velocity.length() / pixels_por_kmh

# Estado em tipos simples, para controladores externos (Python) lerem com get().
var estado_velocidade_kmh: float:   ## na direção da frente; negativo = marcha-atrás
	get:
		return velocity.dot(transform.x) / pixels_por_kmh
var estado_angulo_rodas: float:     ## graus; positivo = direita
	get:
		return rad_to_deg(direcao_rodas)
var estado_rumo: float:             ## graus, 0 a 360 (0 = +X)
	get:
		return fposmod(rotation_degrees, 360.0)


func _ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	velocity += _calcular_aceleracao(delta) * delta
	_calcular_direcao(delta)
	velocity = velocity.limit_length(velocidade_max)

	var vel_antes := velocity
	move_and_slide()

	_detetar_colisoes(vel_antes, delta)


# ------------------------------------------------------------------ Criação

## Cria um carro completo (física, cor, controlador, estatísticas) e põe-no na
## árvore, já no grupo "carros". Uso:
##   Carro.instanciate(Carro.criar_config(Color.YELLOW, ControladorTeclado))
##
## - participante: ver criar_config(). null = carro branco de teclado.
## - pai: nó onde o carro é adicionado. null = a cena atual (ou a raiz da árvore).
static func instanciate(cor: Color = Color.WHITE, script_controlador: Script = ControladorTeclado, nome: String = "") -> Carro:
	var arvore := Engine.get_main_loop() as SceneTree
	var posicao := arvore.get_nodes_in_group(GRUPO).size()   # 0 = o primeiro carro

	var carro := (load(CENA) as PackedScene).instantiate() as Carro
	carro.nome = nome
	carro.cor = cor
	
	carro.z_index = 1000 - posicao   # o primeiro carro fica por cima dos outros

	if carro.nome.is_empty():
		carro.nome = "Carro %d" % (posicao + 1)
	carro.modulate = carro.cor

	# Por omissão os carros só colidem com as paredes
	carro.collision_layer = CAMADA_CARROS
	carro.collision_mask = CAMADA_PAREDES
	
	# Setup Controlador
	carro.controlador = Node.new()
	carro.controlador.name = "Controlador"
	carro.controlador.set_script(script_controlador)
	carro.add_child(carro.controlador)

	carro.estatisticas = EstatisticasCorrida.new()
	carro.estatisticas.name = "Estatisticas"
	carro.add_child(carro.estatisticas)
	carro.estatisticas.configurar(carro)
	
	arvore.current_scene.add_child(carro)

	carro.add_to_group(GRUPO)
	return carro


# ------------------------------------------------------------------ API pública

## true  = o controlador (filho deste carro: teclado, GDScript ou Python) conduz.
## false = o controlador fica parado e quem manda é código externo (ex.: a
##         PonteRL do treino PPO), que escreve os comandos com aplicar_comandos().
var controlo_manual: bool = true:
	set(valor):
		controlo_manual = valor
		if controlador != null:
			controlador.set_physics_process(valor and is_physics_processing())


## Atalho para controladores externos (RL, Python, ...). Valores em [-1, 1].
func aplicar_comandos(acelerar: float, virar: float) -> void:
	input_acel = clampf(acelerar, -1.0, 1.0)
	input_dir = clampf(virar, -1.0, 1.0)


## Liga ou desliga a física do carro (e do seu controlador, se controlo_manual).
## Usado pela Corrida para congelar os carros no fim de uma corrida.
func ativar(ligado: bool) -> void:
	set_physics_process(ligado)
	if controlador != null:
		controlador.set_physics_process(ligado and controlo_manual)


## Liga ou desliga a colisão com outros carros (as paredes colidem sempre).
func permitir_colisao_entre_carros(ativo: bool) -> void:
	collision_mask = CAMADA_PAREDES | (CAMADA_CARROS if ativo else 0)


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
	if estatisticas != null:
		estatisticas.reiniciar()


# ------------------------------------------------------------------ Interno

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


## Lê um RayCast2D e devolve a distância normalizada (0.0 a 1.0).
func _ler_sensor(sensor: RayCast2D) -> float:
	if sensor == null:
		return 1.0
	if not sensor.is_enabled():
		sensor.enabled = true
	if not sensor.is_colliding():
		return 1.0  # Sem obstáculo detetado
	
	var ponto := sensor.get_collision_point()
	var distancia_max := sensor.target_position.length()
	if distancia_max <= 0.0:
		return 0.0
	var distancia := sensor.global_position.distance_to(ponto)
	return clampf(distancia / distancia_max, 0.0, 1.0)
