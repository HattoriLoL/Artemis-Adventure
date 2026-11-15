extends Node
## Estado da missão que continua existindo quando o jogo troca de cena (autoload "Missao").
## Guarda local de pouso, ciclo dos 7 dias, clima espacial DONKI e diário de bordo.

const ARQUIVO := "res://dados/locais_pouso.json"
const ARQUIVO_DONKI := "res://dados/donki_eventos.json"

var local_pouso := ""                    # "borda", "polo" ou "planicie"; vazio = ainda não escolheu
var dados_local: Dictionary = {}         # a entrada inteira do local no JSON (título, vantagem, risco...)
var condicoes: Dictionary = {}           # as condições de partida do local (energia, oxigênio, noite, gelo...)

var dia_atual: int = 1                   # Dia da missão (1 a 7)
var dia_impacto_cme: int = 4             # O dia em que a onda de choque da CME atinge a órbita lunar
var blindagem_reforcada: bool = false    # Se o jogador reforçou o abrigo no minigame de blindagem
var eventos_donki: Array = []
var evento_donki_ativo: Dictionary = {}

var diario_entradas: Dictionary = {}


func _ready() -> void:
	_carregar_dados_donki()
	atualizar_diario()


func _carregar_dados_donki() -> void:
	if FileAccess.file_exists(ARQUIVO_DONKI):
		var texto := FileAccess.get_file_as_string(ARQUIVO_DONKI)
		var parsed: Variant = JSON.parse_string(texto)
		if parsed is Array and not parsed.is_empty():
			eventos_donki = parsed
			evento_donki_ativo = eventos_donki[0]
	if evento_donki_ativo.is_empty():
		evento_donki_ativo = {
			"id": "CME-2023-04-21",
			"tipo": "EJICAO DE MASSA CORONAL (CME)",
			"fonte": "NASA GODDARD CCMC / SOHO",
			"data_real": "21/04/2023 - 18:12 UTC",
			"velocidade": "1.100 KM/S",
			"radiacao": "NIVEL CRITICO (CLASSE M1.7)",
			"tempo_impacto": "DIA 4 (JANELA ESTIMADA 24-36H)",
			"descricao": "ONDA DE CHOQUE DE PLASMA SOLAR DETECTADA PELO OBSERVATORIO SDO.",
			"acao": "RECOLHA A EQUIPE AO ABRIGO OU REFORCE A BLINDAGEM!"
		}


func obter_status_clima() -> Dictionary:
	match dia_atual:
		1:
			return {
				"fase": "calmo",
				"titulo": "SOL ESTAVEL",
				"risco": "BAIXO",
				"cor": Color("#a8ca58"), # verde
				"vento_solar": "340 KM/S",
				"resumo": "SEM ERUPCOES. FLUXO BASAL.",
				"detalhes": "SISTEMA EM MONITORAMENTO CONTINUO VIA SDO/GOES. FLUXO DE RAIOS-X EM NIVEL A/B."
			}
		2:
			return {
				"fase": "alerta_leve",
				"titulo": "REGIAO ATIVA EM ROTACAO",
				"risco": "BAIXO A MODERADO",
				"cor": Color("#e8c170"), # amarelo
				"vento_solar": "415 KM/S",
				"resumo": "CAMPO MAGNETICO INSTAVEL.",
				"detalhes": "MANCHA SOLAR REGIAO ATIVA 13283 EM ALINHAMENTO COM A ORBITA LUNAR."
			}
		3:
			return {
				"fase": "deteccao_cme",
				"titulo": "CME DETECTADA (TRANSITO)",
				"risco": "ELEVADO",
				"cor": Color("#e88b35"), # laranja
				"vento_solar": "1.100 KM/S",
				"resumo": "ONDA DE PLASMA A CAMINHO.",
				"detalhes": "ERUPCAO CLASSE M CONFIRMADA PELA NASA. ONDA DE CHOQUE ATINGIRA A LUA NO DIA 4. REFORCE O ABRIGO."
			}
		4:
			return {
				"fase": "impacto",
				"titulo": "IMPACTO SOLAR ATIVO",
				"risco": "CRITICO",
				"cor": Color("#cf573c"), # vermelho
				"vento_solar": "1.280 KM/S",
				"resumo": "TEMPESTADE DE PROTONS!",
				"detalhes": "PARTICULAS ENERGETICAS SOLARES ATINGINDO A SUPERFICIE. TRANCAR EQUIPE NO ABRIGO BLINDADO!"
			}
		5:
			return {
				"fase": "pos_impacto",
				"titulo": "RECUPERACAO POS-EVENTO",
				"risco": "MODERADO",
				"cor": Color("#e8c170"), # amarelo
				"vento_solar": "560 KM/S",
				"resumo": "POEIRA IONIZADA NOS PAINEIS.",
				"detalhes": "PICO DA ONDA PASSOU. RECALIBRAR BATERIAS E LIMPAR PAINEIS SOLARES."
			}
		6:
			return {
				"fase": "estavel",
				"titulo": "SISTEMAS NOMINAIS",
				"risco": "BAIXO",
				"cor": Color("#a8ca58"), # verde
				"vento_solar": "370 KM/S",
				"resumo": "ESTABILIDADE RESTAURADA.",
				"detalhes": "NIVEIS DE RADIACAO DE FUNDO NORMALIZADOS. SUPORTE DE VIDA 100% OPERACIONAL."
			}
		_:
			return {
				"fase": "conclusao",
				"titulo": "MISSAO 7 DIAS CONCLUIDA",
				"risco": "MINIMO",
				"cor": Color("#73bed3"), # azul
				"vento_solar": "350 KM/S",
				"resumo": "BASE ARTEMIS ASSEGURADA.",
				"detalhes": "ROTACAO DE 7 DIAS CUMPRIDA COM EXITO. DADOS TRANSMITIDOS COM SUCESSO A TERRA."
			}


func avancar_dia() -> void:
	dia_atual = mini(7, dia_atual + 1)
	atualizar_diario()


func escolher_local(id: String) -> void:
	for local in JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO)):
		if local["id"] == id:
			local_pouso = id
			dados_local = local
			condicoes = local["condicoes"]
			print("Missao: pouso em ", id, " ", condicoes)
			return
	push_error("Local de pouso desconhecido: " + id)


# ------------------------------------------------------------- SISTEMA DE DIÁRIO DE BORDO DINÂMICO
func atualizar_diario() -> void:
	for sol in range(1, 8):
		diario_entradas[sol] = obter_entrada_diario(sol)


func obter_entrada_diario(sol: int) -> Dictionary:
	var entrada: Dictionary
	if sol > dia_atual:
		entrada = {
			"titulo": "[REGISTRO BLOQUEADO // AGUARDANDO SOL %d]" % sol,
			"autor": "SISTEMA ARTEMIS-OS",
			"texto": "ESTE SOL AINDA NAO OCORREU NA BASE ARTEMIS. DADOS HISTORICOS SERAO REGISTRADOS PELA COMANDANTE LUNA CONFORME A MISSAO AVANCAR E CADA DIA FOR ENCERRADO AO DORMIR NO HABITAT.",
			"estado": "bloqueado"
		}
	elif sol == dia_atual:
		entrada = {
			"titulo": "SOL %d: TURNO ATIVO // OPERACOES EM CURSO" % sol,
			"autor": "CMD. LUNA / ARTEMIS BASE",
			"texto": _obter_texto_sol_ativo(sol),
			"estado": "ativo"
		}
	else:
		entrada = _obter_entrada_sol_concluido(sol)

	diario_entradas[sol] = entrada
	return entrada


func _obter_texto_sol_ativo(sol: int) -> String:
	match sol:
		1:
			return "CMD. LUNA: ESTAMOS EXECUTANDO OS PROCEDIMENTOS INICIAIS DA BASE ARTEMIS. O RESUMO COMPLETO DESTE SOL SERA CONCLUIDO AO FINAL DO DIA, NO ENCERRAMENTO DO TURNO."
		2:
			return "CMD. LUNA: ROTINA OPERACIONAL NOMINAL. MONITORAMOS A MANCHA SOLAR ATIVA COM A NASA DONKI. O RESUMO COMPLETO DESTE SOL SERA CONCLUIDO AO FINAL DO DIA, NO ENCERRAMENTO DO TURNO."
		3:
			return "CMD. LUNA: ALERTA CONFIRMADO DE CME PELA NASA DONKI. PRIORIDADE TOTAL NO REFORCO DO ABRIGO CONTRA RADIACAO. O RESUMO COMPLETO DESTE SOL SERA CONCLUIDO AO FINAL DO DIA, NO ENCERRAMENTO DO TURNO."
		4:
			return "CMD. LUNA: TEMPESTADE SOLAR EM ANDAMENTO NA SUPERFICIE LUNAR. EQUIPE CONCENTRADA NO ABRIGO BLINDADO. O RESUMO COMPLETO DESTE SOL SERA CONCLUIDO AO FINAL DO DIA, NO ENCERRAMENTO DO TURNO."
		5:
			return "CMD. LUNA: RESCALDO DO IMPACTO SOLAR. LIMPANDO PAINEIS E RECALIBRANDO SISTEMAS AFETADOS PELO PLASMA. O RESUMO COMPLETO DESTE SOL SERA CONCLUIDO AO FINAL DO DIA, NO ENCERRAMENTO DO TURNO."
		6:
			return "CMD. LUNA: SISTEMAS ESTABILIZADOS E DADOS SENDO TRANSMITIDOS AO CENTRO GODDARD DA NASA NA TERRA. O RESUMO COMPLETO DESTE SOL SERA CONCLUIDO AO FINAL DO DIA, NO ENCERRAMENTO DO TURNO."
		_:
			return "CMD. LUNA: ULTIMO TURNO DO CICLO DE 7 DIAS. REVISANDO TELEMETRIA E HOMOLOGACAO DA BASE ARTEMIS. O RESUMO COMPLETO DESTE SOL SERA CONCLUIDO AO FINAL DO DIA, NO ENCERRAMENTO DO TURNO."


func _obter_entrada_sol_concluido(sol: int) -> Dictionary:
	match sol:
		1:
			return {
				"titulo": "SOL 1: POUSO E PRESSURIZACAO",
				"autor": "CMD. LUNA / ARTEMIS BASE",
				"texto": "POUSO BEM-SUCEDIDO NA CRATERA SHACKLETON. O MODULO LUNAR ASSENTOU COM FIRMEZA NO REGOLITO. CONCLUIMOS A PRESSURIZACAO INICIAL, ATIVAMOS OS FILTROS DE CO2 E ALINHOU-SE O SUPORTE DE VIDA. A TERRA PARECE UMA PEQUENA JOIA AZUL SOBRE O HORIZONTE NEGRO.",
				"estado": "concluido"
			}
		2:
			return {
				"titulo": "SOL 2: ROTINA E INSTABILIDADE SOLAR",
				"autor": "CMD. LUNA / ARTEMIS BASE",
				"texto": "ROTINA MATINAL NOMINAL. OS PAINEIS SOLARES JA FORNECEM 92% DA CARGA BASAL. O OBSERVATORIO SDO DA NASA REPORTOU UMA MANCHA SOLAR ATIVA EM ROTACAO (AR 13283). O VENTO SOLAR SUBIU DE 340 PARA 415 KM/S. TELEMETRIA EM ALERTA.",
				"estado": "concluido"
			}
		3:
			var txt_sol3: String
			if blindagem_reforcada:
				txt_sol3 = "ALERTA CONFIRMADO PELA REDE NASA DONKI: CME DE CLASSE M A CAMINHO A 1.100 KM/S. NOSSA RESPOSTA OPERACIONAL FOI IMEDIATA: REFORCAMOS A BLINDAGEM DO ABRIGO COM CAMADAS EXTRAS DE REGOLITO. ESTAMOS PRONTOS PARA O IMPACTO."
			else:
				txt_sol3 = "ALERTA CONFIRMADO PELA REDE NASA DONKI: CME DE CLASSE M A CAMINHO A 1.100 KM/S. TEMPO ESCASSO ANTES DO IMPACTO. O ABRIGO PERMANECE APENAS COM A BLINDAGEM BASICA E VULNERAVEL. A RADIACAO SERA UM RISCO EXTREMO."
			return {
				"titulo": "SOL 3: DETECCAO DE CME PELA DONKI",
				"autor": "CMD. LUNA / ARTEMIS BASE",
				"texto": txt_sol3,
				"estado": "concluido"
			}
		4:
			var txt_sol4: String
			if blindagem_reforcada:
				txt_sol4 = "A ONDA DE CHOQUE ATINGIU A LUA AS 14:00. O FLUXO DE PROTONS SUBIU CRITICAMENTE. TODA A TRIPULACAO SE FECHOU NO ABRIGO. GRACAS A BLINDAGEM REFORCADA, OS NIVEIS DE RADIACAO INTERNOS FICARAM SEGUROS. RESISTIMOS AO PIOR."
			else:
				txt_sol4 = "A ONDA DE CHOQUE ATINGIU A LUA AS 14:00. FLUXO DE PROTONS CRITICO. A BLINDAGEM BASICA DO ABRIGO SOFREU COM INDUCAO MAGNETICA E A RADIACAO PASSOU DO LIMITE SEGURO. DANOS ELETRICOS NA BASE, MAS A EQUIPE RESISTIU."
			return {
				"titulo": "SOL 4: O IMPACTO DA TEMPESTADE SOLAR",
				"autor": "CMD. LUNA / ARTEMIS BASE",
				"texto": txt_sol4,
				"estado": "concluido"
			}
		5:
			var txt_sol5: String
			if blindagem_reforcada:
				txt_sol5 = "A FRENTE PRINCIPAL PASSOU! A BASE SOBREVIVEU COM DANOS MINIMIZADOS PELA BLINDAGEM DO ABRIGO. A POEIRA LUNAR IONIZADA COBRIU OS PAINEIS SOLARES EXTERNOS. INICIAMOS A VARREDURA DOS PAINEIS E RECALIBRAGEM DAS BATERIAS."
			else:
				txt_sol5 = "A FRENTE PRINCIPAL PASSOU. A FALTA DE REFORCO NA BLINDAGEM SOBRECARREGOU OS CIRCUITOS E EXAURIU A EQUIPE. PASSAMOS O DIA REPARANDO COMPONENTES DANIFICADOS E LIMPANDO A POEIRA IONIZADA DOS PAINEIS SOLARES."
			return {
				"titulo": "SOL 5: AVALIACAO DE DANOS E RESCALDO",
				"autor": "CMD. LUNA / ARTEMIS BASE",
				"texto": txt_sol5,
				"estado": "concluido"
			}
		6:
			return {
				"titulo": "SOL 6: ESTABILIZACAO E CIENCIA",
				"autor": "CMD. LUNA / ARTEMIS BASE",
				"texto": "SISTEMAS REESTABILIZADOS. A ESTUFA HIDROPONICA VOLTOU A FLORESCER E O SUPORTE DE VIDA ESTA 100% NOMINAL. TRANSMITIMOS TODOS OS DADOS DA TEMPESTADE PARA O GODDARD SPACE FLIGHT CENTER DA NASA. A BASE ESTA SALVA.",
				"estado": "concluido"
			}
		_:
			return {
				"titulo": "SOL 7: FINAL DA MISSAO ARTEMIS",
				"autor": "CMD. LUNA / ARTEMIS BASE",
				"texto": "SETIMO DIA CONCLUIDO NA FRONTEIRA LUNAR. PROVAMOS QUE A HUMANIDADE PODE RESISTIR E PROSPERAR SOB TEMPESTADES ESPACIAIS SEVERAS. A BASE ARTEMIS ESTA SEGURA, OPERACIONAL E HOMOLOGADA PARA A PROXIMA ROTACAO. RUMO A MARTE.",
				"estado": "concluido"
			}
