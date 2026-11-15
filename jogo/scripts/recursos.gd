extends Node
## Os 4 indicadores da missão (autoload "Recursos"): energia, oxigênio, comida e saúde da equipe ("condicao"),
## de 0 a 100. Começam com as condições do local de pouso (Missao.condicoes) e mudam assim:
##   - sobem (ou trocam um pelo outro) quando o jogador conclui uma tarefa: aplicar("sala/id");
##   - no fechamento de cada dia (fechar_dia, chamado pelo ciclo_dias.gd ao dormir) a base consome energia, oxigênio
##     e comida e os painéis geram energia conforme o local (geracao_solar). Nas noites não há geração solar.
##   - a saúde da equipe não tem consumo diário e dormir não mexe nela: só cai quando algo dá errado (cada recurso
##     baixo na noite) e só sobe com cuidado (refeição, plantas). Regra para o jogador: "a equipe se machuca quando
##     falta suprimento; comida e plantas recuperam".
## Todos os números ficam em res://dados/recursos.json, para o balanceamento mexer sem tocar no código.

signal mudou(id: String, mudancas: Dictionary)   # depois de aplicar(): {"oxigenio": 15.0, ...}

const ARQUIVO := "res://dados/recursos.json"
const NOMES := ["energia", "oxigenio", "comida", "condicao"]   # também a ordem no HUD
const ROTULOS := {"energia": "POWER", "oxigenio": "OXYGEN", "comida": "FOOD", "condicao": "HEALTH"}
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


## A tarefa reforça a blindagem contra a erupção solar ("protecao" em recursos.json)?
func protege(id: String) -> bool:
	return regras.get("protecao", {}).has(id)


## Dano na saúde da erupção solar: pequeno no Abrigo; fora dele, menor a cada reforço da blindagem.
func dano_tempestade(no_abrigo: bool) -> float:
	var r: Dictionary = regras["radiacao"]
	if no_abrigo:
		return float(r["dano_abrigo"])
	return maxf(float(r["dano_fora_min"]), float(r["dano_fora"]) - float(r["reducao_por_reforco"]) * Missao.blindagem)


## Tira saúde (ou outro indicador) de uma vez, como a erupção solar; devolve quanto tirou de fato.
func ferir(nome: String, v: float) -> float:
	var antes: float = valores[nome]
	_somar(nome, -v)
	return antes - valores[nome]


## Aplica o efeito de uma tarefa ou interação e devolve o que mudou de fato (perto de 100 ou de 0, muda menos).
## `fator` < 1 quando o minigame teve erros (fator_erro). Tarefa de proteção (blindagem) soma reforços.
func aplicar(id: String, fator := 1.0) -> Dictionary:
	if protege(id) and fator > 0.0:
		Missao.blindagem += int(regras["protecao"][id])
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


## Fechamento do dia: consumo da base, geração dos painéis e o dano à saúde da equipe por recurso baixo. Devolve as
## partes para o resumo da noite: {"solar": 4.2, "desgaste": 6.0} (desgaste = a saúde perdida por recursos baixos).
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
	_somar("condicao", -float(consumo.get("condicao", 0.0)) - desgaste)
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
