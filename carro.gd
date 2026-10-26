extends CharacterBody2D

# CONVENÇÃO: a frente do carro é +X (transform.x). A imagem do sprite deve
# apontar para a direita; se apontar para cima, roda o Sprite2D filho 90°
# (e não o corpo), assim a física fica sempre consistente.

# --- Motor ---
@export var potencia_motor: float = 560.0      # força máxima a baixa velocidade
@export var potencia_travao: float = 800.0
@export var velocidade_max: float = 600.0
@export var velocidade_max_re: float = 150.0
@export var tempo_acelerador: float = 1.2      # s para o acelerador ir de 0 a 100%
@export var tempo_largar: float = 0.4          # s para largar o acelerador

# --- Resistências ---
@export var atrito_rolamento: float = 0.5
@export var arrasto: float = 0.0006

# --- Direção ---
@export var angulo_direcao: float = 30.0       # ângulo máx. das rodas (graus) a baixa velocidade
@export var fator_direcao_alta: float = 0.3    # fração do ângulo à velocidade máxima
@export var suavidade_direcao: float = 6.0     # maior = rodas respondem mais depressa
@export var distancia_eixos: float = 60.0

# --- Aderência (por segundo, independente da framerate) ---
@export var aderencia_baixa: float = 12.0
@export var aderencia_alta: float = 3.0
@export var velocidade_derrapagem: float = 400.0

# --- Colisões com paredes ---
@export_group("Colisões")
@export var perda_impacto: float = 0.6   # fração da velocidade perdida numa batida de frente (0-1)
@export var atrito_parede: float = 3.0   # travagem contínua enquanto encostado (maior = trava mais)

# --- Velocímetro (só afeta o que é mostrado, não a física) ---
# Com os valores acima o carro estabiliza perto de 360 px/s,
# que é mostrado como 120 km/h  ->  1 km/h = 3 px/s.
@export_group("Velocímetro")
@export var pixels_por_kmh: float = 3.0
@export var mostrar_hud: bool = true   # desliga nos carros que não são o principal

# --- Câmara (tecla C alterna) ---
# Por defeito mantém a vista do mapa que já tens na cena.
# Ao carregar em C passa a seguir o carro; carregar outra vez volta à vista original.
@export_group("Câmara")
@export var zoom_seguir: Vector2 = Vector2(1.4, 1.4)
@export var atraso_posicao: float = 5.0   # menor = mais atraso
@export var atraso_rotacao: float = 2.5   # menor = roda mais devagar atrás do carro
@export var atraso_zoom: float = 4.0

# --- Controlo ---
# Para RL: põe controlo_manual = false e escreve input_acel / input_dir
# (ambos em [-1, 1]) a partir do agente.
@export_group("Controlo")
@export var controlo_manual: bool = true
var input_acel: float = 0.0   # +1 acelera, -1 trava/marcha-atrás
var input_dir: float = 0.0    # +1 direita, -1 esquerda

var em_colisao: bool = false
var acelerador: float = 0.0   # acelerador suavizado
var direcao_rodas: float = 0.0

var hud: Label
var camara: Camera2D
var camara_seguir: bool = false
var padrao_posicao: Vector2
var padrao_rotacao: float = 0.0
var padrao_zoom: Vector2 = Vector2.ONE


func _ready() -> void:
	if mostrar_hud:
		criar_hud()
	# Espera que a cena toda esteja pronta para encontrar a câmara atual
	call_deferred("_iniciar_camara")


func _iniciar_camara() -> void:
	# 1) Camera2D filha do carro; 2) câmara atual da cena; 3) cria uma nova
	for filho in get_children():
		if filho is Camera2D:
			camara = filho
			break
	if camara == null:
		camara = get_viewport().get_camera_2d()
	if camara == null:
		camara = Camera2D.new()
		add_child(camara)
		camara.global_position = global_position
		camara.make_current()

	# Se for filha do carro, tem de ser independente para poder ter atraso
	if camara.get_parent() == self:
		camara.top_level = true

	# Guarda as definições padrão (a vista do mapa)
	padrao_posicao = camara.global_position
	padrao_zoom = camara.zoom
	padrao_rotacao = 0.0 if camara.ignore_rotation else camara.rotation

	camara.ignore_rotation = false   # necessário para a câmara poder rodar
	camara.rotation = padrao_rotacao


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		camara_seguir = not camara_seguir


func _physics_process(delta: float) -> void:
	if controlo_manual:
		ler_input()

	var aceleracao := calcular_aceleracao(delta)
	velocity += aceleracao * delta
	calcular_direcao(delta)
	velocity = velocity.limit_length(velocidade_max)
	var vel_antes := velocity
	move_and_slide()

	detetar_colisoes(vel_antes, delta)
	atualizar_camara(delta)
	atualizar_hud()


func velocidade_kmh() -> float:
	return velocity.length() / pixels_por_kmh


func criar_hud() -> void:
	# CanvasLayer fica fixo no ecrã, independente da câmara
	var camada := CanvasLayer.new()
	add_child(camada)
	hud = Label.new()
	hud.position = Vector2(20, 20)
	hud.add_theme_font_size_override("font_size", 24)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	camada.add_child(hud)


func atualizar_hud() -> void:
	if hud == null:
		return
	var rodas := rad_to_deg(direcao_rodas)
	var lado := "reta"
	if rodas > 1.0:
		lado = "direita"
	elif rodas < -1.0:
		lado = "esquerda"
	var rumo := fposmod(rotation_degrees, 360.0)
	hud.text = "Velocidade: %d km/h\nDireção das rodas: %.0f° (%s)\nRumo do carro: %.0f°" % [
			int(velocidade_kmh()), absf(rodas), lado, rumo]


func detetar_colisoes(vel_antes: Vector2, delta: float) -> void:
	var n := get_slide_collision_count()
	if n > 0:
		var colisao := get_slide_collision(0)
		# Só no primeiro frame de contacto: print + perda de velocidade do impacto
		if not em_colisao:
			var outro := colisao.get_collider()
			var nome: String = outro.name if outro else "desconhecido"
			print("Colisão com: ", nome, " | velocidade: ", int(vel_antes.length() / pixels_por_kmh), " km/h")
			# Quanto mais de frente bate na parede, mais velocidade perde
			var frontal := clampf(-vel_antes.normalized().dot(colisao.get_normal()), 0.0, 1.0)
			velocity *= 1.0 - perda_impacto * frontal
		# Enquanto estiver encostado, vai travando continuamente
		velocity *= exp(-atrito_parede * delta)
	em_colisao = n > 0


func atualizar_camara(delta: float) -> void:
	if camara == null:
		return

	var alvo_pos := global_position if camara_seguir else padrao_posicao
	var alvo_zoom := zoom_seguir if camara_seguir else padrao_zoom
	# +90° para o carro aparecer a apontar para cima no ecrã
	var alvo_rot := (rotation + PI / 2.0) if camara_seguir else padrao_rotacao

	camara.global_position = camara.global_position.lerp(
			alvo_pos, 1.0 - exp(-atraso_posicao * delta))
	camara.rotation = lerp_angle(
			camara.rotation, alvo_rot, 1.0 - exp(-atraso_rotacao * delta))
	camara.zoom = camara.zoom.lerp(alvo_zoom, 1.0 - exp(-atraso_zoom * delta))


func ler_input() -> void:
	input_acel = Input.get_axis("ui_down", "ui_up")
	input_dir = Input.get_axis("ui_left", "ui_right")


func calcular_aceleracao(delta: float) -> Vector2:
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
			forca = acelerador * potencia_travao          # travagem
		else:
			var restante_re := clampf(1.0 - (-vel_frente) / velocidade_max_re, 0.0, 1.0)
			forca = acelerador * potencia_motor * 0.5 * restante_re  # marcha-atrás

	var aceleracao := frente * forca

	# Sem input e quase parado: pára de vez
	if velocity.length() < 5.0 and absf(input_acel) < 0.01:
		velocity = Vector2.ZERO
		return Vector2.ZERO

	# Resistências
	aceleracao += -velocity * atrito_rolamento
	aceleracao += -velocity * velocity.length() * arrasto
	return aceleracao


func calcular_direcao(delta: float) -> void:
	var velocidade := velocity.length()
	if velocidade < 1.0:
		return

	# Menos ângulo nas rodas quando se vai depressa (mais estável)
	var f := clampf(velocidade / velocidade_max, 0.0, 1.0)
	var angulo_max := deg_to_rad(angulo_direcao) * lerpf(1.0, fator_direcao_alta, f)
	var alvo := input_dir * angulo_max
	direcao_rodas = lerpf(direcao_rodas, alvo, 1.0 - exp(-suavidade_direcao * delta))

	# Modelo de bicicleta (frente = +X, direita = ângulo positivo; sem "-")
	var roda_tras := position - transform.x * distancia_eixos / 2.0
	var roda_frente := position + transform.x * distancia_eixos / 2.0
	roda_tras += velocity * delta
	roda_frente += velocity.rotated(direcao_rodas) * delta
	var nova_direcao := (roda_frente - roda_tras).normalized()

	# Aderência diminui gradualmente com a velocidade
	var grip := lerpf(aderencia_baixa, aderencia_alta,
			smoothstep(velocidade_derrapagem * 0.5, velocidade_derrapagem * 1.5, velocidade))
	var t := 1.0 - exp(-grip * delta)

	var d := nova_direcao.dot(velocity.normalized())
	if d > 0.0:
		velocity = velocity.lerp(nova_direcao * minf(velocidade, velocidade_max), t)
	else:
		velocity = -nova_direcao * minf(velocidade, velocidade_max_re)

	rotation = nova_direcao.angle()
