# Buraco Legacy — auditoria do acoplamento na V1.1

**Checkpoint preservado:** `PCBuracoNativeMouseV1_1.lua`, commit `93ec52804ecb9fca3ca658f771d868a4736a8d12`. Esta nota não modifica o runtime. `PROVEN` = código ou relatório existente demonstra o fato; `SUPPORTED` = inferência delimitada; `QUALITATIVE` = observação de vídeo/usuário; `UNKNOWN` = não identificável com os dados disponíveis.

## 1. PC SIGNATURE

**QUALITATIVE.** Em `02_PC_REFERENCE.mp4`, sobretudo na sequência contínua de quadros 75–134 (2,5–4,5 s, 30 fps), o cenário muda de orientação enquanto a região do tronco superior permanece perto da referência central. O emote muda a silhueta; o centro visual da silhueta não equivale a Head, PrimaryPart ou CameraSubject. O vídeo não contém teclas registradas nem CFrames do PC. Não é possível atribuir os quadros a A ou D individualmente nem calcular yaw Root↔Camera real a partir de pixels.

## 2. MOBILE DIVERGENCE

**QUALITATIVE.** Em `01_MOBILE_V1_1.mp4`, inclusive nos quadros consecutivos 525–584 (17,5–19,5 s), o personagem muda orientação/pose em torno da referência central, mas a relação visual com tronco/Head parece menos firme que a referência PC. São mapas, capturas, FOV e escalas diferentes; nenhuma diferença absoluta em pixels entre os vídeos é um caliper válido. O resultado humano confirmado é que a câmera voltou a girar na V1.1, mas Buraco e A/D ainda não se comportam como o PC.

## 3. BURACO KINEMATICS

**PROVEN pelo código V1.1:** `BuracoDot` é um `Frame` de 1×1 em `UDim2.fromScale(0.5,0.5)`. Sua coordenada de tela é fixa. Portanto a separação visual descreve mudança da projeção do avatar em relação ao centro, não movimento do próprio ponto guiado pelo personagem. Para ponto 3D `P`, a variável geométrica relevante é `project(Camera.CFrame:PointToObjectSpace(P))`; Root, Head e subject não podem ser confundidos. **PROVEN nos relatórios X9 anteriores, não na sessão V1.1:** Touch e Gamepad em 3P usavam offset `(2,0.5,0)` e `rootLocalX≈-2`. Essas medidas descartam a tese geral de offset mobile ausente, mas não fornecem Camera/Root/Head CFrames sincronizados da V1.1.

**PROVEN na V614 anterior:** projeções de PrimaryPart/subject e evolução da Head podem divergir devido à pose relativa do rig; só 3 de 12 pares sobreviveram aos controles Moderate. A V614 não identifica mecanismo PC nem estabelece causalidade V1.1.

## 4. A/D + BODY ORIENTATION

**PROVEN pelo código:** V1.1 importa `PCModeLockV5_9`, que seleciona e mantém o controlador real de teclado, enquanto `PCKeyboardTouchBridgeV5_9` preserva a emissão contínua das teclas W/A/S/D de V5.2 em `RenderPriority.Input + 8` (108). No [ControlModule de referência Roblox](https://github.com/Roblox/avatar/blob/286397ebcfd6b54dd83677c402407a6319b9963d/ReferenceBodyCreator/StarterPlayerScripts/PlayerModule/ControlModule/init.lua), `ControlScriptRenderstep` lê `GetMoveVector`, converte por orientação da câmera quando `IsMoveVectorCameraRelative()` é verdadeiro e chama `Player:Move` em `RenderPriority.Input` (100). Uma **transição de tecla emitida pela rotina por frame** em 108 ocorre depois dessa leitura, podendo ser observada pelo controlador de movimento somente no próximo passo; `InputBegan` do joystick também chama `refreshKeys` de imediato, então a afirmação não vale indistintamente para todas as transições. O ganho, o conteúdo do chord e o comportamento quando a tecla já está sustentada são questões distintas.

**SUPPORTED, limitado:** esse descompasso é candidato ao início/fim/reversão de A/D. Não demonstra que o giro corporal sustentado seja diferente, pois segurar A ou D mantém o mesmo chord entre frames. Não explica sozinho o afastamento em emote sem A/D. `Humanoid.AutoRotate` e o yaw efetivo do Root durante a sessão V1.1 não estão registrados nos dados anexados; nenhum write de Root é autorizado.

## 5. PIPELINE MAP

```text
joystick real → filtro digital/latch V5.9 → VirtualInput W/A/S/D @ Input+8 (108)
ControlModule ativo (keyboard) → GetMoveVector → camera-relative transform → Player:Move @ Input (100)
Touch câmera direita → OnInputChanged / bookkeeping → pendingDelta
V1.1 → OnMouseMoved(proxy Lua) OU contribuição medida em rotateInput @ Camera-10 (190)
CameraModule → Controller.Update → subject/focus/offset → CFrame final @ Camera (~200)
PCModeLockV5 → restauração condicional do controlador keyboard @ Last-1 (1999)
```

**PROVEN pelo código:** V1.1 mantém bookkeeping de Touch, suprime pan temporariamente e tenta `OnMouseMoved` antes de escrever somente `rotateInput` se o proxy Lua não alterou esse acumulador. O vídeo prova câmera móvel; não determina qual das duas rotas internas prevaleceu nessa coleta, pois não há `GetState()` dela. Nada demonstra que um proxy Lua seja um `MouseMovement` nativo de PC. O `CameraModule.Update` do Evade possui um tail custom conhecido que usa `ShiftLockEnabled.Value` para chamar `SetIsMouseLocked` depois de `Controller.Update` (V608/V609). Não foi estabelecido que esse tail tenha transformação geométrica ausente na V1.1.

## 6. EMERGENCY DELTA

**PROVEN pelo código exato:** o botão `EMERGÊNCIA • RELAY OFF / V500` da V614 chama `stopProbe()` (restaura hooks) e `PCV604SetRelayEnabled(false)`. O V500 preservado permanece ativo; ele aplica lock/offset de câmera em `Camera-2`, força `RotationType.MovementRelative` antes e depois da câmera, evita `UpdateMouseBehavior` e espelha teclas em `Input+1`. Esses fatos são uma diferença arquitetural real em relação à V1.1 + V5.9. A impressão de que a emergência se parecia mais com PC é **QUALITATIVE**: não isola qual dessas mudanças, se alguma, produziu a aparência, e não prova que `MovementRelative` seja o estado desejado no PC.

## 7. OVERHAUL CROSS-CHECK

**UNKNOWN.** `OverhaulCameraServiceX9.lua` é uma *probe* que procura a closure de `ReplicatedStorage.Services.Client.CameraService`; não é a implementação desse serviço. O pacote não contém um relatório runtime Overhaul comparável nem o código do serviço. Logo não existe transformação comum PC/Overhaul comprovada que possa ser transplantada para Legacy a partir desses arquivos.

## 8. TOP 3 HYPOTHESES

| Hipótese | Evidência | Estado |
| --- | --- | --- |
| A/D emitido após `ControlModule` | Código de V5.9 e ControlModule, 108 > 100 | **PROVEN como diferença de ordem**; relação causal com Buraco **UNKNOWN** |
| Coupling Root/rig↔câmera diferente na sessão V1.1 | Vídeo e geometria 3P X9 anterior; sem CFrames V1.1/PC | **SUPPORTED como classe de causa**, estágio específico **UNKNOWN** |
| Tail custom/CameraService adiciona composição ausente | V609 não identificou branch Touch↔PC; sem fonte Overhaul | **UNKNOWN**; não justifica patch |

## 9. SELECTED MECHANISM

**Nenhum mecanismo do Buraco está identificado com confiança suficiente.** O primeiro desvio funcional comprovado é a ordem de emissão de A/D nas transições do joystick. Uma correção da prioridade poderia testar exclusivamente a latência dessas transições; não justificaria anunciar que a câmera/rig/emote do PC foi reproduzida. O vídeo não fornece profundidade, pose local da Head, yaw do PrimaryPart, `CameraSubject`, estado do lock na V1.1, telemetria de A/D nem valores de `ShiftLockEnabled` na mesma sessão. Nem os relatórios X9 nem os 3 pares Moderate da V614 podem preencher retroativamente essas lacunas.

## 10. IMPLEMENTATION TARGET

**Bloqueado para correção do Buraco.** Preservar a V1.1 exatamente como está: uma alteração em Input+8, lock, offset ou `Camera.CFrame` seria implementação de hipótese parcial sem ligação demonstrada com a separação durante emote. Não criar V2.x nem pedir nova coleta manual; o material disponível termina aqui. Se um dia existirem dados já capturados do *mesmo* evento PC/mobile contendo a relação sincronizada `Camera.CFrame`, subject, PrimaryPart, Head/pose e tecla/chord A/D, a primeira diferença nessa cadeia definirá um alvo único. Não inventar esse estado a partir do vídeo.

### Integridade desta auditoria

- Vídeos revistos: `01_MOBILE_V1_1.mp4` (SHA-256 `34e7c1723f997f1a334d7916dbbd28bbc58bcfed557eeb54bda4c4cf6a9e2019`), `02_PC_REFERENCE.mp4` (`4db54ffb7b22822bec2a2f4bdea3cf2fc78c316d68630755207da26c040ec7c7`). Trechos 75–134 PC e 525–584 mobile revistos por quadros consecutivos. A revisão visual não recupera estado 3D nem teclas não gravadas.
- `PCBuracoNativeMouseV1_1.lua` consultado sem modificar: SHA-256 `aa98b008c53dcf77785c6787dc94243a3ac563588ec317b4d7895d3f4657e165`.
- V20, V500 e V604 preservados. SHA-256 respectivamente `634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef`, `5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096`, `19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571`.
- **Sem alteração de runtime, sem correção visual, sem testes solicitados ao usuário.**
