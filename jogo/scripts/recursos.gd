extends Node
## Os 4 indicadores da missão (autoload "Recursos"): energia, oxigênio, comida e condição da equipe, de 0 a 100.
## Começam com as condições do local de pouso (Missao.condicoes) e mudam assim:
##   - descem sozinhos com o tempo (consumo da base e da equipe); a energia ganha a geração dos painéis, que
##     depende do local (geracao_solar). A condição da equipe cai mais rápido quando outro recurso está baixo;
##   - sobem (ou trocam um pelo outro) quando o jogador conclui uma tarefa ou dorme: aplicar("sala/id").
## Todos os números ficam em res://dados/recursos.json, para o balanceamento mexer sem tocar no código.
## Ainda não há dias, noites nem eventos: entram nas próximas tasks e usam este mesmo script.

signal mudou(id: String, mudancas: Dictionary)   # depois de aplicar(): {"oxigenio": 15.0, ...}

const ARQUIVO := "res://dados/recursos.json"
const NOMES := ["energia", "oxigenio", "comida", "condicao"]

var valores := {"energia": 0.0, "oxigenio": 0.0, "comida": 0.0, "condicao": 0.0}
var ativo := false                       # só corre na base (não na tela de pouso nem no fim)
var regras: Dictionary = {}


func _ready() -> void:
	regras = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))


## Chamado pelo mapa ao abrir a base. Sem pouso escolhido (abrindo o mapa direto pelo editor), usa a planície.
func iniciar() -> void:
	if Missao.local_pouso == "":
		Missao.escolher_local("planicie")
	for nome in NOMES:
		valores[nome] = clampf(float(Missao.condicoes.get(nome, 70.0)), 0.0, 100.0)
	ativo = true


func _process(delta: float) -> void:
	if not ativo:
		return
	var consumo: Dictionary = regras["consumo_por_segundo"]
	var solar := float(regras["geracao_solar_por_segundo"]) * float(Missao.condicoes.get("geracao_solar", 1.0))
	_somar("energia", (solar - float(consumo["energia"])) * delta)
	_somar("oxigenio", -float(consumo["oxigenio"]) * delta)
	_somar("comida", -float(consumo["comida"]) * delta)
	var queda := float(consumo["condicao"])
	for nome in ["energia", "oxigenio", "comida"]:
		if baixo(nome):
			queda += float(regras["queda_condicao_por_recurso_baixo"])
	_somar("condicao", -queda * delta)


## O que uma tarefa ou interação ("habitat/cama"...) vai mudar, sem aplicar: {"comida": -5.0, "condicao": 10.0}.
## O HUD mostra isso antes de o jogador apertar E (custo e benefício visíveis antes da escolha).
func previa(id: String) -> Dictionary:
	var efeito: Dictionary = regras["efeitos"].get(id, {})
	var mult := 1.0
	if regras["multiplicadores"].has(id):      # ex.: a água rende mais no polo (gelo_por_coleta)
		mult = float(Missao.condicoes.get(regras["multiplicadores"][id], 1.0))
	var r := {}
	for nome in efeito:
		var v := float(efeito[nome])
		r[nome] = v * mult if v > 0.0 else v    # o multiplicador só vale para ganhos, não para custos
	return r


## Aplica o efeito de uma tarefa ou interação e devolve o que mudou de fato (perto de 100 ou de 0, muda menos).
func aplicar(id: String) -> Dictionary:
	var efeito := previa(id)
	var mudancas := {}
	for nome in efeito:
		var v: float = efeito[nome]
		var antes: float = valores[nome]
		_somar(nome, v)
		if not is_equal_approx(valores[nome], antes):
			mudancas[nome] = valores[nome] - antes
	if not mudancas.is_empty():
		mudou.emit(id, mudancas)
	return mudancas


func baixo(nome: String) -> bool:
	return valores[nome] < float(regras["limite_baixo"])


func _somar(nome: String, v: float) -> void:
	valores[nome] = clampf(valores[nome] + v, 0.0, 100.0)
