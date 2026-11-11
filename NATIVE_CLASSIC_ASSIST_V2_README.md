# Native Classic Lateral + Assist V2 — Evade iOS / Delta

**Status: candidato experimental.** Nao houve teste real no iPhone 11. Nao confundir testes estaticos/vetoriais com validacao dentro do Evade.

## Pedido original (09/11/2026)

- Continuar usando o **Classic Thumbstick NATIVO** do Roblox (nao Dynamic, nao PC Movement).
- A↔D muito mais rapido; comando horizontal 100% quando dedo chega a 20% do raio visual.
- Ao inverter rapidamente a direcao, aceitar 100% na outra lateral apos cruzar fisicamente o centro em 6,5% (janela de 110 ms, so quando havia lateral forte anterior recente).
- Nao mexer em tamanho/posicao/desenho do joystick, camera, TouchGui, pulo, bhop, trimp, diagonais reais, WASD, WalkSpeed ou velocidade fisica.
- Incluir Assist de grades, sem substituir o movimento.

## Mudancas em relacao a V1

1. **PlayerModule vivo apenas:** a V1 podia usar o modulo-modelo em StarterPlayer. V2 usa apenas `LocalPlayer.PlayerScripts.PlayerModule` e compara o controlador ativo ao modulo `TouchThumbstick`. Se o jogo usa novo stack sem esse modulo, a V2 nao faz nenhuma substituicao falsa; retorna um motivo em `GetState()`.
2. **Inversao no vetor, nao em fisica:** para lateral pura, troca o comando na amostra da posicao real do dedo. Nao antecipa o cruzamento de centro, nao cria toque artificial nem teleporte. O Evade ainda controla aceleracao, atrito e inercia.
3. **Seguranca:** chamadas protegidas por `pcall` no algoritmo; erro retorna o vetor nativo. O hook e removido apenas se ainda for o nosso, restaurando a implementacao original ao chamar `Stop()`.
4. **Assist de grades V3.1 adaptado:** reduz a busca de cerca de 40 para ate **15 raycasts por scan** e a frequencia de contato para 12 Hz. Somente tenta orientar suavemente o avatar quando detecta grade real muito proxima, esta no chao e AutoRotate e nativo. Nao altera camera, WalkSpeed, velocidade ou salto. O recurso visual pode ser desligado sem desligar a melhoria lateral.
5. **Isolamento:** novos arquivos/branch. V1, PC Movement V3.1/V3.2 e outras versoes continuam intactos.

## Instalacao (Delta, EVade)

Antes: Configuracoes do Roblox → **Classic Thumbstick**. Desative V3.1/V3.2, outros scripts de joystick e macros no AutoExecute para nao disputar o input. Rode somente:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/native-classic-lateral-assist-v2-20261111/NativeClassicAssistV2Loader.lua"))()
```

Apos entrar no jogo e movimentar o Classic, inspecione:

```lua
local s=getgenv().NativeClassicAssistCombo.GetState()
print("Native Classic connected:",s.native and s.native.installed)
print("Active finger:",s.native and s.native.active)
print("Reason:",s.native and s.native.reason)
print("Enhanced frames:",s.native and s.native.enhancedFrames)
print("Reversals:",s.native and s.native.reversals)
print("Assist enabled:",s.assist and s.assist.enabled)
```

**Se `installed=false`, nao afirmar que foi aplicado.** Experimente esperar a inicializacao do PlayerModule e confira `reason` antes de pedir ajustes.

## Controles de emergencia e isolamento

```lua
local x=getgenv().NativeClassicAssistCombo
x.SetEnabled(false)                -- desliga a melhoria A/D, restaura GetMoveVector
x.SetEnabled(true)                 -- religa a melhoria A/D
x.SetAssistEnabled(false)          -- desliga o Assist
x.SetAssistEnabled(true)           -- religa o Assist
x.SetVisualAssistEnabled(false)    -- Assist ainda detecta grade, mas nao gira avatar
x.SetVisualAssistEnabled(true)     -- reativa somente orientacao suave de grades
x.SetDiagnostics(true)
local ok,path,contents=x.ExportDiagnostics()
print(ok,path,contents)
x.Stop()                           -- encerra tudo, restaura joystick nativo
```

## Checklist manual dentro do Evade

1. Confirmar `native.installed=true` com Classic selecionado. Trocar para Dynamic deve remover o hook.
2. Testar A forte → cruzar centro → D; depois D forte → A, **sem soltar dedo**. Repetir com distancias e FPS similares ao baseline.
3. Testar W, S, diagonais, movimento leve no centro, soltar dedo, abrir menu, respawn e camera.
4. Comparar FPS e bhop/trimp com e sem Assist. Em caso de travamento, `SetAssistEnabled(false)` antes de desativar o modulo lateral.
5. Testar `Stop()` e confirmar que o controle continua original sem reiniciar o cliente.

## Validacao executada / nao executada

- Checagens estaticas de API, isolamento, ausencias de substituicao visual, ausencia de velocidade fisica e uso correto de controller vivo.
- Simulacao independente de 3.500 vetores com pass-through em diagonais e analogico neutro, reversao bilateral, um novo touch, expiracao da janela.
- **Nao** validado na engine Roblox, nem no iPhone 11/Delta, nem FPS real, nem aceleracao fisica instantanea.
- O PlayerModule nativo pode mudar de estrutura entre versoes de Roblox; quando isso acontecer, desativar e inspecionar `reason`.

**Arquivos V2**:
- `NativeClassicLateralV2.lua`
- `NativeClassicGridAssistV2.lua`
- `NativeClassicAssistV2Loader.lua`

**Rollback V1:** branch `feature/native-classic-lateral-assist-20261109`, intacta.
