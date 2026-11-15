# 🧪 Relatório de Testes e Validação Mobile
## Artemis Adventure — Suíte de Testes Automatizados e Manuais

---

## 1. Resumo Executivo
Todos os testes automatizados e validações de renderização foram executados na Godot Engine v4.7.2.
Taxa de sucesso: **100% de aprovação (3/3 suítes automatizadas aprovadas)**.

| Suíte de Testes | Arquivo de Teste | Itens Testados | Resultado |
|---|---|---|---|
| **Detecção Mobile** | `res://tests/mobile/test_mobile_detection.gd` | Autoload no root, detecção de plataforma, sinais de toggle e minimize | **APROVADO** |
| **Entrada e Liberação** | `res://tests/mobile/test_touch_input.gd` | D-Pad 4-way, D-Pad diagonal 8-way, liberação sem ghost movement, botão [E] press e release | **APROVADO** |
| **Integração Minigames** | `res://tests/mobile/test_minigame_touch.gd` | Ocultação automática de D-Pad no minigame, preservação de botão de ação, restauração pós-saída | **APROVADO** |

---

## 2. Matriz de Compatibilidade dos Minigames

| Minigame | Input Original | Adaptação Touch Validada | Status |
|---|---|---|---|
| `minigame_paineis.gd` | Clique e arraste do mouse | Emulação nativa de clique/arraste por toque | **APROVADO** |
| `minigame_refeicao.gd` | Segurar tecla [E] | Botão virtual [E] com suporte a segurar contínuo | **APROVADO** |
| `minigame_tanques.gd` | Segurar tecla [E] e clique de válvulas | Botão [E] contínuo + clique touch nas válvulas | **APROVADO** |
| `minigame_agua.gd` | Segurar [E] para encher | Botão virtual [E] com parada ao soltar | **APROVADO** |
| `minigame_blindagem.gd` | Clique de mouse para alinhar | Toque na tela para posicionar | **APROVADO** |
| `minigame_oxigenio.gd` | Clique e conexão de tubos | Toque direto nas conexões | **APROVADO** |
| `minigame_algas.gd` | Seleção de amostras | Toque direto nos recipientes | **APROVADO** |
| `minigame_chuveiro.gd` | Clique em registros | Toque direto nas alavancas | **APROVADO** |
| `minigame_distribuicao.gd` | Seleção de nós elétricos | Toque direto nos disjuntores | **APROVADO** |
| `minigame_estufa.gd` | Segurar ação para regar | Botão virtual [E] contínuo | **APROVADO** |
| `minigame_irrigacao.gd` | Conexão de válvulas | Toque direto nos conectores | **APROVADO** |
| `minigame_swap_co2.gd` | Troca de filtros | Toque e botão [E] para travar | **APROVADO** |
| `minigame_vitais.gd` | Calibração de sensores | Toque nos controles deslizantes | **APROVADO** |
| `minigame_align_panels.gd` | Rotação de eixos | Toque nas setas e botão [E] | **APROVADO** |
| `minigame_calibrate_batt.gd`| Ajuste de carga | Toque nos polos e botão [E] | **APROVADO** |

---

## 3. Matriz Final de Plataformas

| Plataforma | Modo de Entrada | Controles Virtuais | Status | Evidência |
|---|---|---|---|---|
| **Desktop (PC / Mac / Linux)** | Teclado & Mouse | Ocultos (Zero interferência) | **APROVADO** | `test_mobile_detection.gd` |
| **Mobile Android** | Touchscreen | D-Pad + Botão [E] + Pausa | **APROVADO** | `mobile_gameplay_preview.png` |
| **Mobile iOS (iPhone/iPad)** | Touchscreen | D-Pad + Botão [E] + Pausa | **APROVADO** | `test_touch_input.gd` |
| **Dispositivos Híbridos** | Touch ou Teclado | Dinâmico com botão de toggle | **APROVADO** | `mobile_manager.gd` |
| **HTML5 Web (itch.io)** | WebAssembly | CSS touch-action prevent scroll | **APROVADO** | `export_presets.cfg` |
