# V607 — Native Mouse-Lock Activation Boundary

## Estado aceito sem repetir testes

A V607 continua diretamente da V606 e não mede novamente ownership, yaw,
sensibilidade ou composição downstream.

São fatos de entrada desta versão:

- V604 identifica Touch de joystick e câmera por identidade real;
- o mesmo Touch real de câmera passa pelo bookkeeping de `OnTouchChanged` e
  segue para `OnMouseMoved`;
- joystick + câmera simultâneos funcionam sem crossover;
- V500 permanece fail-open;
- V606 provou a transformação camera-relative de `mouseLockOffset = 2, 0.5, 0`
  em 1416/1416 frames, com `compositionMatchRatio = 1` e resíduo máximo
  `0.0000054`.

Consequentemente, a V607 não procura offset ausente e não altera sua composição.

## Fronteira investigada

O único caminho examinado é:

```text
TouchEnabled / PreferredInput / last input
    -> CameraModule.new
    -> criação e disponibilidade do MouseLockController
    -> binding/cursor/toggle event
    -> CameraModule.OnMouseLockToggled
    -> Controller.Update (apenas a fronteira)
```

O scan é uma lista fechada de métodos nomeados. Não existe travessia global de
GC, connections, tabelas do PlayerModule ou funções downstream.

## Por que activeMouseLockController é nil

O PlayerModule cuja assinatura corresponde ao runtime observado contém no
construtor de `CameraModule` o gate:

```lua
if not UserInputService.TouchEnabled then
    self.activeMouseLockController = MouseLockController.new()
end
```

Assim, em um iPhone com `TouchEnabled = true`, o objeto não chega a ser criado.
Isso é mais específico que a classificação inicial por `PreferredInput`: o
enum permanece uma evidência de plataforma, mas o gate de construção histórico
é `TouchEnabled`.

A V607 não assume isso apenas por fonte externa. Ela inspeciona no próprio Delta:

- constants/upvalues/protos de `CameraModule.new`;
- presença do ModuleScript `MouseLockController`;
- ausência do campo `activeMouseLockController` no objeto ativo;
- `TouchEnabled`, `PreferredInput` e `GetLastInputType()`;
- estado no início e no fim da coleta.

`constructorTouchGateProven` só fica true quando essas evidências concordam.

Referência de código Roblox usada para restringir a probe:
[CameraModule no repositório Roblox/avatar](https://github.com/Roblox/avatar/blob/286397ebcfd6b54dd83677c402407a6319b9963d/ReferenceBodyCreator/StarterPlayerScripts/PlayerModule/CameraModule/init.lua).

## O que o MouseLockController realmente adiciona

A V607 obtém a tabela já carregada do ModuleScript, mas nunca chama `.new()`.
Ela inspeciona apenas estes métodos, quando expostos:

- `new`;
- `UpdateMouseLockAvailability`;
- `EnableMouseLock`;
- `BindContextActions` / `UnbindContextActions`;
- `OnBoundKeysObjectChanged`;
- `DoMouseLockSwitch`;
- `OnMouseLockToggled`;
- `GetIsMouseLocked`, `GetMouseLockOffset` e `GetBindableToggleEvent`.

A arquitetura compatível adiciona quatro grupos de comportamento:

1. decide disponibilidade a partir de opções de jogador/usuário e plataforma;
2. instala um ContextAction/InputAction para a tecla Shift;
3. troca o cursor visual de mouse;
4. dispara um BindableEvent para `CameraModule.OnMouseLockToggled`, que transfere
   lock e, dependendo da revisão, offset ao active camera controller.

Não há cálculo de CFrame, subject, focus, PrimaryPart ou projeção dentro dessa
fronteira. O relatório procura explicitamente esses tokens e publica
`mouseLockGeometryHits` e `mouseLockAddsCameraGeometry`.

Referência do controlador:
[MouseLockController no repositório Roblox/avatar](https://github.com/Roblox/avatar/blob/286397ebcfd6b54dd83677c402407a6319b9963d/ReferenceBodyCreator/StarterPlayerScripts/PlayerModule/CameraModule/MouseLockController.lua).

## Primeira diferença funcional

A ausência do objeto nativo remove no mobile o binding de Shift, o cursor e o
evento de toggle. Porém V604/V500 já colocam o camera controller em lock e
fornecem o offset, e a V606 provou que o controller consome ambos corretamente.

Logo, instanciar `MouseLockController` não fornece uma transformação geométrica
nova. O único comportamento PC ainda não reproduzido nessa fronteira é a
captura relativa real do ponteiro:

```text
PC:    mouse-lock -> UpdateMouseBehavior -> MouseBehavior.LockCenter
Touch: SetIsMouseLocked(true) executa, RotationType muda, mas MouseBehavior
       permanece Default
```

Esse é um efeito funcional, não apenas uma diferença de enum: no PC o ponteiro
é recentralizado e produz movimento relativo; no Touch não existe ponteiro
nativo equivalente. Entretanto, isso afeta aquisição/semântica de input e não
demonstra uma transformação de screen-space ausente depois de `rotateInput`.
Portanto a V607 não declara que esse ponto explica sozinho a deriva visual.

Os campos decisivos são:

- `constructorTouchGateProven`;
- `mouseLockBindingEffectFound`;
- `mouseLockCursorEffectFound`;
- `mouseLockToggleEventFound`;
- `onMouseLockToggledStateTransferOnly`;
- `mouseLockGeometryHits`;
- `boundMouseLockAction*` e `inputActionInstance*`;
- `onMouseLockToggledCalls`;
- `firstFunctionalDivergence`;
- `decisiveAnswer`.

## Por que não existe experimento nesta build

Forçar `PreferredInput` não reproduziria o hardware. Criar manualmente um
`MouseLockController` instalaria binding/cursor/eventos já desnecessários, sem
geometria nova. Forçar `MouseBehavior.LockCenter` repetiria uma tentativa que o
caminho nativo já faz e que a plataforma não retém.

Nenhuma dessas ações tem evidência suficiente para corrigir a âncora de
screen-space. Por isso `experimentEligible = false`; o botão opt-in permanece
visível, mas bloqueado e instrumentado. `DESLIGAR EXPERIMENTO` e a emergência
continuam disponíveis dentro do Roblox.

## Teste mobile em uma única sessão

Não saia do Roblox até copiar o relatório.

1. Execute `Loader.lua` uma vez.
2. Faça joystick + câmera simultaneamente para provar ownership da V604.
3. Ligue **RELAY V604**. Se for recusado, repita o gesto simultâneo.
4. Toque em **INICIAR**.
5. Jogue e gire a câmera normalmente por 20–30 segundos, incluindo joystick +
   câmera com dois dedos.
6. Toque em **PARAR**.
7. O botão de experimento deve continuar como **BLOQUEADO**. Não é necessário
   tocá-lo.
8. Toque em **COPIAR REPORT COMPLETO**.
9. Só saia quando aparecer `REPORT COPIADO. Agora pode sair e colar.`

O botão **EMERGÊNCIA • RELAY OFF / V500** para a coleta, garante experimento OFF
e desliga o relay V604 imediatamente.

## Segurança

A V607 não instancia `MouseLockController`, não chama `OnMouseLockToggled`, não
força `PreferredInput`, `MouseBehavior` ou `RotationType`, não cria input, não usa
VirtualInput nem `firesignal` e não escreve Camera/RootPart CFrame. Também não
altera AutoRotate, sensibilidade, ganho, WalkSpeed ou física.

V604 e V500 permanecem as camadas funcional e fail-open. O arquivo
`PCMovementV20_STABLE.lua` deve continuar byte-identical com SHA-256:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
