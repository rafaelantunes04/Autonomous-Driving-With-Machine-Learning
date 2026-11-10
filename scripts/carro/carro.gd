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

const CENA := "res://cenas/carro.tscn"
const GRUPO := &"carros"
const CAMADA_PAREDES := 1
const CAMADA_CARROS := 2

## Parâmetros de física. Se ficar vazio, usa os valores por omissão do CarroConfig.
@export var config: CarroConfig

# Preenchidos pelo Carro.instanciate().
var nome: String = ""            ## nome do carro
var nome_exibicao: String = ""   ## nome + modelo do controlador, para o HUD
var cor: Color = Color.WHITE
var controlador: Node            ## quem conduz o carro (filho deste nó); null = parado
var estatisticas: EstatisticasCorrida   ## batidas, tempo e voltas (filho deste nó)

## Compatibilidade com a cena Track. A cena Corrida usa nós controladores.
var controlo_manual := false

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

@onready var _sensor_front := get_node_or_null("Front_Sensor") as RayCast2D
@onready var _sensor_right := get_node_or_null("Right_Sensor") as RayCast2D
@onready var _sensor_right_2 := get_node_or_null("Right_Sensor_2") as RayCast2D
@onready var _sensor_left := get_node_or_null("Left_Sensor") as RayCast2D
@onready var _sensor_left_2 := get_node_or_null("Left_Sensor_2") as RayCast2D

## Distância normalizada: 0 junto à parede, 1 sem parede ao alcance.
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


func _ler_sensor(sensor: RayCast2D) -> float:
	if sensor == null or not sensor.is_colliding():
		return 1.0
	var alcance := sensor.global_position.distance_to(sensor.to_global(sensor.target_position))
	var distancia := sensor.global_position.distance_to(sensor.get_collision_point())
	return clampf(distancia / maxf(alcance, 0.001), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if controlo_manual:
		aplicar_comandos(Input.get_axis("ui_down", "ui_up"), Input.get_axis("ui_left", "ui_right"))

	velocity += _calcular_aceleracao(delta) * delta
	_calcular_direcao(delta)
	velocity = velocity.limit_length(config.velocidade_max)

	var vel_antes := velocity
	move_and_slide()

	_detetar_colisoes(vel_antes, delta)


# ------------------------------------------------------------------ Criação

## Cria a config de um carro numa linha:
##   Carro.criar_config(Color.YELLOW, ControladorTeclado)
##   Carro.criar_config(Color.RED, load("res://main.py"), "Python")
## - controlador: script que conduz o carro (null = carro parado)
## - fisica: CarroConfig opcional (null = valores por omissão)
static func criar_config(cor: Color = Color.WHITE, controlador: Script = null, nome: String = "", fisica: CarroConfig = null) -> ParticipanteConfig:
	var p := ParticipanteConfig.new()
	p.cor = cor
	p.controlador = controlador
	p.nome = nome
	p.config = fisica
	return p


## Cria um carro completo (física, cor, controlador, estatísticas) e põe-no na
## árvore, já no grupo "carros". Uso:
##   Carro.instanciate(Carro.criar_config(Color.YELLOW, ControladorTeclado))
##
## - participante: ver criar_config(). null = carro branco de teclado.
## - pai: nó onde o carro é adicionado. null = a cena atual (ou a raiz da árvore).
static func instanciate(participante: ParticipanteConfig = null, pai: Node = null) -> Carro:
	var arvore := Engine.get_main_loop() as SceneTree
	var posicao := arvore.get_nodes_in_group(GRUPO).size()   # 0 = o primeiro carro

	var carro := (load(CENA) as PackedScene).instantiate() as Carro
	carro.name = "Carro"
	carro.z_index = 1000 - posicao   # o primeiro carro fica por cima dos outros

	var script_controlador: Script = ControladorTeclado
	if participante != null:
		script_controlador = participante.controlador
		carro.nome = participante.nome
		carro.cor = participante.cor
		if participante.config != null:
			carro.config = participante.config.duplicate() as CarroConfig   # cópia própria de cada carro
	if carro.nome.is_empty():
		carro.nome = "Carro %d" % (posicao + 1)
	carro.modulate = carro.cor

	# Por omissão os carros só colidem com as paredes
	carro.collision_layer = CAMADA_CARROS
	carro.collision_mask = CAMADA_PAREDES

	var modelo := ""
	if script_controlador != null:
		carro.controlador = Node.new()
		carro.controlador.name = "Controlador"
		carro.controlador.set_script(script_controlador)
		carro.add_child(carro.controlador)
		var nome_modelo = carro.controlador.get("nome_modelo")   # null se o script não tiver
		if nome_modelo is String:
			modelo = nome_modelo
	carro.nome_exibicao = carro.nome if modelo.is_empty() else "%s (%s)" % [carro.nome, modelo]

	carro.estatisticas = EstatisticasCorrida.new()
	carro.estatisticas.name = "Estatisticas"
	carro.add_child(carro.estatisticas)
	carro.estatisticas.configurar(carro)

	carro.add_to_group(GRUPO)
	if pai == null:
		pai = arvore.current_scene if arvore.current_scene != null else arvore.root
	pai.add_child(carro, true)   # true = nome legível e único (Carro, Carro2, ...)
	return carro


# ------------------------------------------------------------------ API pública

## Liga ou desliga a colisão com outros carros (as paredes colidem sempre).
func permitir_colisao_entre_carros(ativo: bool) -> void:
	collision_mask = CAMADA_PAREDES | (CAMADA_CARROS if ativo else 0)


func aplicar_comandos(acelerar: float, virar: float) -> void:
	input_acel = clampf(acelerar, -1.0, 1.0)
	input_dir = clampf(virar, -1.0, 1.0)


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
