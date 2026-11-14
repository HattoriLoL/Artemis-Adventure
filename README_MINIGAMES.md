# Suporte a minigames

Esta branch (`feature/suporte-minigames`) prepara o jogo para receber minigames. Ela **não traz nenhum minigame**:
só deixa o `mapa.gd` pronto para abrir um quando o jogador usa uma tarefa.

Depois que ela entrar na `main`, quem faz um minigame **não precisa mexer no `mapa.gd`**. Basta criar a cena e
apontar para ela no JSON da sala.

## Para que serve

Antes, apertar **E** numa tarefa concluía a tarefa na hora. Agora:

- **Tarefa sem minigame:** continua igual, conclui na hora.
- **Tarefa com minigame:** o jogo abre a cena do minigame por cima da tela, deixa o astronauta parado e só conclui a
  tarefa quando o minigame avisa que terminou.

## Como ligar um minigame a uma tarefa

Adicione o campo `"minigame"` na tarefa, no JSON da sala (`jogo/salas/<sala>.json`):

```json
{"id": "regar", "x": 192, "y": 120, "texto": "REGAR AS PLANTAS", "minigame": "res://cenas/minigame_estufa.tscn"}
```

Pronto. Não precisa mudar mais nada no código do jogo.

## O que a cena do minigame precisa ter

Por dentro, a cena é livre. O jogo só exige três coisas:

| O quê | Para quê |
|---|---|
| Nó raiz `Control` de **320x180** (Layout: Full Rect) | É o tamanho da tela; o minigame fica por cima do jogo. |
| Sinal `terminou` | O minigame chama `terminou.emit()` quando acaba. O jogo então fecha a cena e conclui a tarefa. |
| Variável `demo` | O jogo coloca `demo = true` no modo demo (`-- --demo`); aí o minigame deve se resolver sozinho. |

Menor script que funciona:

```gdscript
extends Control

signal terminou

var demo := false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("usar"):
		terminou.emit()
```

## O que o jogo faz por você

- Abre a cena e passa o `demo`.
- Deixa o astronauta parado enquanto o minigame está aberto.
- Esconde o aviso "E: ..." do HUD e faz o E não acionar outras tarefas nem portas enquanto o minigame está aberto.
- Quando chega o `terminou`, apaga a cena e conclui a tarefa (marca verde no HUD, conta em "BASE x/y").
- Se o caminho no JSON estiver errado, mostra um erro no console e conclui a tarefa sem minigame, para o jogo não
  travar.

## O que fica com o minigame

- **O E que abre o minigame é o mesmo aperto.** Se o seu minigame usa o E, ignore a tecla até ela ser solta pela
  primeira vez.
- **Leia o teclado com `Input` dentro do `_process`**, usando as ações `usar`, `esquerda`, `direita`, `cima` e
  `baixo`. Não use `_gui_input`: sem foco, o `Control` não recebe teclas.
- **Não pause o jogo** (`get_tree().paused`). O jogo já deixa o astronauta parado.

## O que mudou no código

Só em `jogo/scripts/mapa.gd`:

- A antiga `_usar` virou `_concluir`, sem nenhuma mudança por dentro.
- A nova `_usar` decide: se a tarefa não tem minigame, chama `_concluir`; se tem, abre a cena.
- A variável `minigame` guarda a cena aberta. Enquanto ela existe, o `_process` segura o astronauta e o HUD esconde o
  "E: ...".
- Cada tarefa lida do JSON ganhou o campo `minigame` (vazio quando a tarefa não tem minigame).

## Como foi testado

Com uma cena de teste ligada à tarefa da estufa, o modo demo (`godot --path jogo -- --demo`) abriu o minigame, esperou
o `terminou`, concluiu a tarefa, fez as outras salas e fechou sozinho, sem erros no console. As tarefas sem minigame
continuam funcionando como antes.
