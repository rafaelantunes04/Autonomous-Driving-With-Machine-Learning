extends Resource
class_name CarroConfig

## Parâmetros de física de um carro. Cada variante pode ser guardada num .tres
## (Inspetor -> Guardar como...) e atribuída a um participante da Corrida.
##
## Os valores por omissão são os do carro original: com eles o carro estabiliza
## perto de 360 px/s, mostrado como 120 km/h (1 km/h = 3 px/s).

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
