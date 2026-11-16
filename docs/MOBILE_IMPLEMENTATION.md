# 📱 Implementação de Suporte Mobile & itch.io Web
## Artemis Adventure — NASA Space Apps Challenge

---

## 1. Visão Geral da Arquitetura
A adaptação mobile do **Artemis Adventure** foi desenvolvida de forma 100% modular, desacoplada e aditiva. O objetivo central é fornecer uma experiência tátil nativa para jogadores e jurados acessando o jogo via smartphones e tablets (Android e iOS) através do **itch.io**, sem alterar ou comprometer a experiência de teclado e mouse no Desktop.

```
                    ┌────────────────────────┐
                    │     MobileManager      │ (Autoload)
                    │  Detecção de Plataforma│
                    │   e Modo de Entrada    │
                    └───────────┬────────────┘
                                │
               ┌────────────────┴────────────────┐
               ▼                                 ▼
      [Dispositivo Desktop]             [Dispositivo Touch/Web]
    - Teclado & Mouse ativo           - TouchOverlay ativado
    - TouchOverlay invisível          - D-Pad 8-Way (Esq)
    - Zero interferência              - Botão de Ação [E] (Dir)
                                      - Atalhos de Pausa & Toggle
                                      - Emulação de Mouse nos Minigames
```

---

## 2. Componentes Criados

### 2.1. `MobileManager` (`res://scripts/mobile/mobile_manager.gd`)
- **Responsabilidade:** Identificar o dispositivo e controlar o estado global de suporte a toque.
- **Detecção:**
  - `OS.has_feature("web_android")` e `OS.has_feature("web_ios")` (navegadores móveis).
  - `OS.has_feature("android")` e `OS.has_feature("ios")` (dispositivos móveis nativos).
  - `DisplayServer.is_touchscreen_available()` (dispositivos com tela sensível ao toque).
  - **Detecção Dinâmica:** Caso um evento de `InputEventScreenTouch` ocorra em qualquer momento da execução, o sistema ativa os controles touch automaticamente.
- **Sinais:**
  - `touch_controls_toggled(enabled: bool)`
  - `input_mode_changed(mode: String)`
  - `controls_minimized_changed(minimized: bool)`

### 2.2. `VirtualDPad` (`res://scripts/mobile/virtual_dpad.gd`)
- **Estética:** Cruz direcional clássica em pixel art retrô (paleta Apollo Yellow `#f2b134` e Metal `#819796`).
- **Comportamento:**
  - Suporta movimentação em 8 direções (cardinais e diagonais).
  - Aciona as Input Actions nativas `"cima"`, `"baixo"`, `"esquerda"` e `"direita"`.
  - Zona morta de 5px para prevenir movimentos indesejados.
  - Multi-touch seguro (rastreia seu próprio `touch_id`).
  - **Zero Ghost Movement:** Liberação garantida de todas as ações no `_exit_tree()`, pausa ou remoção do dedo.

### 2.3. `VirtualActionButton` (`res://scripts/mobile/virtual_action_button.gd`)
- **Estética:** Botão octogonal com moldura vermelha característica de teclas de ação.
- **Comportamento:**
  - Dispara a Input Action `"usar"` (compatível com `[E]`, confirmação, diálogo e minigames).
  - Suporta tanto toque simples quanto toque contínuo (essencial para o aquecimento de comida e purga de tanques).
  - Feedback tátil háptico através de `MobileManager.vibrar(20)`.

### 2.4. `TouchOverlay` (`res://cenas/mobile/touch_overlay.tscn` e `.gd`)
- **Layer:** `CanvasLayer` no índice `15` (acima do mapa do jogo, abaixo de janelas modais e menu de pausa).
- **Layout Ergonômico (320x180):**
  - **D-Pad:** Canto inferior esquerdo (`x=10, y=118`).
  - **Botão [RUN]:** Logo acima do D-Pad (`x=12, y=94`).
  - **Botão [E]:** Lateral direita (`x=276, y=62`), estrategicamente posicionado entre a barra de recursos (topo) e o minimapa (baixo) para evitar qualquer sobreposição visual.
  - **Botão [ ⏸ ] (Pausa):** Topo central (`x=134, y=4`), aciona a tecla `ui_cancel` (Esc).
  - **Botão [ 📱 ] (Minimizar):** Topo central (`x=152, y=4`), permite ao jogador ocultar os botões virtuais temporariamente para ter visão 100% limpa da tela.

---

## 3. Integração com Minigames
Todos os 15 minigames utilizam coordenadas de mouse e eventos de clique:
1. No `project.godot`, foram ativadas as flags:
   - `input_devices/pointing/emulate_touch_from_mouse = true`
   - `input_devices/pointing/emulate_mouse_from_touch = true`
2. No `mapa.gd`, quando um minigame é iniciado via `abrir_minigame()`, o `TouchOverlay` é notificado via `definir_modo_minigame(true)`. O D-Pad é ocultado automaticamente (já que o astronauta não se movimenta dentro do minigame), mantendo a tela desobstruída para gestos de toque nos painéis, fios e telas.
3. Ao finalizar ou fechar o minigame (`_fechar_minigame()`), o `TouchOverlay` restaura a visibilidade do D-Pad imediatamente.

---

## 4. Configurações para o itch.io (HTML5 Web)

### 4.1. `export_presets.cfg`
Configurado com:
- `variant/thread_support = false` (Single-threaded WebAssembly: indispensável para funcionar em qualquer navegador móvel sem exigir cabeçalhos COOP/COEP no iframe do itch.io).
- `html/canvas_resize_policy = 2` (Adaptativo).
- `html/head_include`: Metatags de prevenção de gestos indesejados:
  ```html
  <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, viewport-fit=cover">
  <style>
    html, body, #canvas {
      touch-action: none;
      -webkit-touch-callout: none;
      -webkit-user-select: none;
      user-select: none;
      overflow: hidden;
      margin: 0;
      padding: 0;
      background-color: #090a14;
      width: 100%;
      height: 100%;
    }
  </style>
  ```

### 4.2. Opções Recomendadas no Painel do itch.io
Ao enviar o arquivo `.zip` da exportação Web no painel do itch.io:
1. **Kind of project:** `HTML`
2. **Embed options:**
   - Marcar `Embed in page`
   - **Viewport dimensions:** `960` x `540` (ou proporção 16:9 de sua preferência)
   - Marcar `Enable fullscreen button`
   - Marcar `Automatically start on page load`
3. **Mobile Settings:**
   - **Orientation:** `Landscape` (Paisagem)
