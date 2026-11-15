extends Node
## Os 4 indicadores da missão (autoload "Recursos"): energia, oxigênio, comida e condição da equipe, de 0 a 100.
## Começam com as condições do local de pouso (Missao.condicoes) e mudam assim:
##   - sobem (ou trocam um pelo outro) quando o jogador conclui uma tarefa ou dorme: aplicar("sala/id");
##   - no fechamento de cada dia (fechar_dia, chamado pelo ciclo_dias.gd ao dormir) a base e a equipe consomem a
##     parte do dia e os painéis geram energia conforme o local (geracao_solar). Nas noites não há geração solar.
##     A condição da equipe cai mais quando outro recurso está baixo.
## Todos os números ficam em res://dados/recursos.json, para o balanceamento mexer sem tocar no código.

signal mudou(id: String, mudancas: Dictionary)   # depois de aplicar(): {"oxigenio": 15.0, ...}

const ARQUIVO := "res://dados/recursos.json"
const NOMES := ["energia", "oxigenio", "comida", "condicao"]   # também a ordem no HUD
const ROTULOS := {"energia": "POWER", "oxigenio": "OXYGEN", "comida": "FOOD", "condicao": "CREW"}
const CORES := {"energia": Color("#e8c170"), "oxigenio": Color("#73bed3"), "comida": Color("#a8ca58"),
	"condicao": Color("#df84a5")}

var valores := {"energia": 0.0, "oxigenio": 0.0, "comida": 0.0, "condicao": 0.0}
var noite := false                       # o ciclo de dias liga nas noites do local: painéis sem sol
var regras: Dictionary = {}


func _ready() -> void:
	regras = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))


## Chamado pelo mapa ao abrir a base. Sem pouso escolhido (abrindo o mapa direto pelo editor), usa a planície.
func iniciar() -> void:
	if Missao.local_pouso == "":
		Missao.escolher_local("planicie")
	for nome in NOMES:
		valores[nome] = clampf(float(Missao.condicoes.get(nome, 70.0)), 0.0, 100.0)
	noite = false


## Quanto os painéis rendem agora: a geração do local, ou nada à noite.
func fator_solar() -> float:
	return 0.0 if noite else float(Missao.condicoes.get("geracao_solar", 1.0))


## O que uma tarefa ou interação ("habitat/cama"...) vai mudar, sem aplicar: {"comida": -5.0, "condicao": 10.0}.
## O HUD mostra isso antes de o jogador apertar E (custo e benefício visíveis antes da escolha).
## `fator` (0 a 1) reduz só os ganhos: é quanto o jogador leva depois dos erros no minigame (fator_erro).
func previa(id: String, fator := 1.0) -> Dictionary:
	var efeito: Dictionary = regras["efeitos"].get(id, {})
	var mult := 1.0
	if regras["multiplicadores"].has(id):      # ex.: a água rende mais no polo (gelo_por_coleta)
		var chave: String = regras["multiplicadores"][id]
		mult = fator_solar() if chave == "geracao_solar" else float(Missao.condicoes.get(chave, 1.0))
	var r := {}
	for nome in efeito:
		var v := float(efeito[nome])
		r[nome] = v * mult * fator if v > 0.0 else v   # multiplicador e erros só valem para ganhos, não para custos
	return r


## Quanto do ganho de uma tarefa o jogador leva pela taxa de erro no minigame (0 = nenhum erro, 1 = só erros):
## até "taxa_sem_perda" (20 por cento) leva tudo; acima disso cai em linha reta até nada em "taxa_sem_ganho".
func fator_erro(taxa: float) -> float:
	var r: Dictionary = regras.get("erros", {})
	var livre := float(r.get("taxa_sem_perda", 0.2))
	var zero := float(r.get("taxa_sem_ganho", 1.0))
	if taxa <= livre:
		return 1.0
	return clampf(1.0 - (taxa - livre) / maxf(zero - livre, 0.001), 0.0, 1.0)


## Aplica o efeito de uma tarefa ou interação e devolve o que mudou de fato (perto de 100 ou de 0, muda menos).
## `fator` < 1 quando o minigame teve erros (fator_erro).
func aplicar(id: String, fator := 1.0) -> Dictionary:
	var efeito := previa(id, fator)
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


## Fechamento do dia: consumo da base e da equipe, geração dos painéis. Devolve as partes para o resumo da noite:
## {"solar": 4.2, "desgaste": 6.0} (desgaste = o extra que a equipe perdeu por causa de recursos baixos).
func fechar_dia() -> Dictionary:
	var consumo: Dictionary = regras["consumo_por_dia"]
	var solar := float(regras["geracao_solar_por_dia"]) * fator_solar()
	var desgaste := 0.0
	for nome in ["energia", "oxigenio", "comida"]:
		if baixo(nome):
			desgaste += float(regras["queda_condicao_por_recurso_baixo"])
	_somar("energia", solar - float(consumo["energia"]))
	_somar("oxigenio", -float(consumo["oxigenio"]))
	_somar("comida", -float(consumo["comida"]))
	_somar("condicao", -float(consumo["condicao"]) - desgaste)
	return {"solar": solar, "desgaste": desgaste}


func baixo(nome: String) -> bool:
	return valores[nome] < float(regras["limite_baixo"])


## O primeiro indicador que chegou a zero ("" se nenhum): a missão é abortada.
func esgotado() -> String:
	for nome in NOMES:
		if valores[nome] <= 0.0:
			return nome
	return ""


func _somar(nome: String, v: float) -> void:
	valores[nome] = clampf(valores[nome] + v, 0.0, 100.0)
