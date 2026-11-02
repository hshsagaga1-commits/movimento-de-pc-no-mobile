# V3.1 preservada: cursor e alcance visual

Base: `feature/pc-movement-v31-preserved-20261101`, commit `62269b83bb05f3fd5eca76f5eeb7102555afc241`.
Entrega isolada: `feature/pc-movement-v31-ui-fixes-20261102`. A branch anterior permanece intacta.

## Loader para Delta AutoExecute

Use somente este loader do joystick:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v31-ui-fixes-20261102/CombinedJoystickAssistV31PreservedLoader.lua?_cb="..game:GetService("HttpService"):GenerateGUID(false),true))()
```

O arquivo `PC_Movement_V31_Preserved_AUTOEXECUTE.lua` contém a mesma linha. Cada download da cadeia mantém um identificador único para evitar cache.

## Mudanças limitadas

- Cursor: módulo separado `PCCursorVisualV31.lua` mantém somente `UserInputService.MouseIconEnabled=false`, com observação da propriedade, respawn e verificação no fim do render. Não envia teclas, cliques ou movimentos de mouse. `Stop()` remove as conexões e restaura a preferência anterior. Falha deste módulo não derruba os controles PC.
- Bolinha: uma única fórmula do bridge troca o limite visual `movementRadius*0.62` por metade do tamanho renderizado do círculo. Isso segue o deslocamento do centro usado no `TouchThumbstick` nativo. Tamanho da bolinha/círculo, posição, raio lógico, sensibilidade, suavização já existente e captura do dedo fora do círculo permanecem iguais.
- Bootstrap: somente os endereços necessários passam a carregar esta cópia do bridge. Mecanismo de teclado PC, troca A/D, câmera, BHOP, Assist e pulo de 200 ms não recebem alterações.

Referência visual primária: [Roblox/avatar — TouchThumbstick.lua](https://github.com/Roblox/avatar/blob/main/ReferenceBodyCreator/StarterPlayerScripts/PlayerModule/ControlModule/TouchThumbstick.lua), função `MoveStick`, limite `thumbstickFrame.AbsoluteSize.x/2`.

## Conflito do macro: ainda pendente

O bridge real foi executado em teste e emitiu somente eventos de teclado; nenhum clique de mouse. Sua saída W/A/S/D/Space permanece idêntica à base. Isso elimina uma chamada de clique feita pelo próprio bridge nesse teste, mas não identifica como o macro externo interpreta os eventos no Delta.

O código/loader do macro de emote ativo não foi identificado. O repositório separado `FloatingMacroG` foi apenas inspecionado: seu macro de pontos usa G, e não há confirmação de que seja o utilizado. Não foi modificado. Possíveis erros de propriedade de toque, sobreposição de UI, tratamento de teclado ou cliques de outro emissor exigem a implementação real para confirmação.

**MEMEDASH permanece intacto e fora do loader.** Nenhum script externo foi alterado, nenhum evento global foi bloqueado e nenhum handler de macro foi substituído por suposição. A correção do conflito não está declarada concluída. É necessário o `.lua` ou link do loader do macro ativo para rastrear e corrigir seu gatilho, se necessário no próprio macro.

## Verificação e limites

```sh
LUAU_BIN=/caminho/luau LUAU_COMPILE=/caminho/luau-compile python3 tools/check_v31_ui_fixes.py
```

Verificações offline executadas com Luau oficial: compilação da cadeia modificada, invariância dos demais arquivos da base, fórmula visual isolada, tamanhos de joystick 70/120/200 px, arrasto além do círculo, traços idênticos de teclas e tempos de pulo, cursor/restauração/reexecução/falha parcial, cancelamento assíncrono do loader e Assist preservado sem novas escritas de velocidade.

Não houve execução no Roblox, Delta ou iPhone. Persistência visual real em respawn/mapas, aparência final no aparelho e convivência com o macro ainda precisam ser observadas nesse ambiente. Os testes simulam serviços Roblox e não validam física real ou detalhes internos do executor.

## Reverter

Para restaurar a entrega anterior, use novamente o loader de `feature/pc-movement-v31-preserved-20261101`. A limpeza da camada de cursor é feita na troca. Para mostrar temporariamente o cursor nesta entrega:

```lua
getgenv().PCMovementAssistV31Preserved.SetCursorHidden(false)
```
