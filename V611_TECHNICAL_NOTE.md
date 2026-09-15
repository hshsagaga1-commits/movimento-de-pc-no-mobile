# V611 — Input-to-Geometry Causality Trace

## Escopo fechado

A V611 continua diretamente da conclusão da V610. Ela não reabre ownership
V604, root yaw V605, composição/offset V606, MouseLockController V607, writers
V608, bloco custom V609 ou a origem do gain/timing já medida pela V610.

O único objetivo é decidir se a divergência de magnitude/cadência do input
sobrevive à geometria já conhecida e produz diferença mensurável de projeção:

```text
input write -> rotateInput -> Controller.Update
-> primeiro CalculateNewLookCFrame
-> clamp relativo ao PrimaryPart
-> GetSubjectPosition -> mouse-lock offset
-> CFrame/Focus retornados -> projeção de PrimaryPart/Head
```

A build é somente diagnóstica. `experimentEligible` permanece `false`.

## Instrumentação correlacionada por frame

Cada `CameraModule.Update` recebe exatamente as escritas acumuladas desde o
update anterior. O relatório associa ao mesmo frame:

- contagem e soma das escritas Touch ou relay;
- `rotateInput` na entrada de `Controller.Update`;
- X solicitado e X efetivo do primeiro `CalculateNewLookCFrame`;
- camera yaw, PrimaryPart yaw, yaw gap, clamp e look yaw retornado;
- ordem observada de `GetSubjectPosition`, `CalculateNewLookCFrame`,
  `GetMouseLockOffset` e saída do controller;
- classe/nome do `CameraSubject`, posição bruta do subject, PrimaryPart e Head;
- distâncias subject→PrimaryPart e subject→Head;
- offset local, vetores right/up/look, offset world-space e posição após offset;
- `CameraCFrame` e `CameraFocus` retornados pelo controller;
- projeção puramente observacional de PrimaryPart e Head e pixels por grau de
  yaw efetivamente aplicado.

A projeção é medida de duas formas: pelo `CurrentCamera` observado no início e
fim do update e por cálculo matemático usando o `CFrame` retornado pelo
controller. A segunda forma não atribui esse CFrame à câmera; ela apenas evita
confundir a geometria retornada com o instante posterior em que o Roblox a
aplica.

## Reconstrução do clamp

A V611 lê somente os upvalues da função já localizada
`CalculateNewLookCFrame`. Os limites horizontais conhecidos da V610 são
`-2π..+2π`; caso os números estejam expostos no runtime, o relatório registra a
fonte como `CalculateNewLookCFrame-upvalues`. A previsão é comparada ao look
real retornado e expõe residual, sem mudar `rotateInput`.

`inputDivergenceSurvivesClamp` só recebe booleano quando há pelo menos 20
amostras calculáveis em cada fase. Sem amostragem suficiente, fica `unproved`.

## Decisão conservadora

- Diferença de offset/focus só é material quando há amostras nas duas fases; um
  residual numérico abaixo de `0.01` stud não vira diferença por erro relativo.
- A comparação de screen-space usa pixels por grau, preferindo frames parado e
  a projeção contra o retorno do controller.
- `inputCausalForAnchor=false` exige que o input sobreviva ao clamp, a geometria
  mouse-lock permaneça igual e a deriva normalizada seja próxima nas duas fases.
- `inputCausalForAnchor=true` exige clamp divergente e diferença forte de deriva
  com amostragem suficiente. Qualquer situação intermediária fica `unproved`.
- O relay continua sendo `OnMouseMoved` com o mesmo Touch real; ele não é
  rotulado como evidência de `MouseMovement` PC nativo.

O relatório termina exatamente com:

```text
inputDivergenceSurvivesClamp =
firstGeometricDivergence =
subjectOriginClassification =
subjectCloserToHeadOrPrimaryPart =
mouseLockGeometryDifference =
screenSpaceDriftTouch =
screenSpaceDriftRelay =
inputCausalForAnchor =
nextSuspectIfInputInnocent =
experimentEligible =
```

## Teste no iPhone + Delta, em uma sessão

1. Execute `Loader.lua` uma vez e permaneça no Roblox.
2. Pressione **INICIAR**.
3. Com **RELAY V604: OFF • FASE A**, gire a câmera por cerca de 15 segundos,
   primeiro parado e depois andando.
4. Inclua joystick + câmera simultâneos para conservar a prova de ownership.
5. Pressione **RELAY V604** para entrar na FASE B.
6. Repita por cerca de 15 segundos movimentos semelhantes, parado e andando.
7. Pressione **PARAR**.
8. Pressione **COPIAR REPORT COMPLETO**.
9. Só saia após aparecer `REPORT COPIADO. Agora pode sair e colar.`

**EMERGÊNCIA** restaura os hooks V611, desliga o relay e deixa o caminho V500
ativo. **PARAR** e **COPIAR** também restauram todos os hooks da V611.

## Segurança e preservação

A V611:

- não escreve `Camera.CFrame`, `Camera.Focus`, `RootPart.CFrame`,
  `PrimaryPart.CFrame` ou `Head.CFrame`;
- não altera subject, sensitivity, gain ou física;
- não força `PreferredInput`, `MouseBehavior`, `RotationType` ou `AutoRotate`;
- não usa VirtualInput, `firesignal` ou `UserInputObject` sintético;
- preserva o relay/ownership V604 e o fail-open V500 sem editar esses arquivos;
- não cria correção artificial de screen-space e não inicia V612.

`PCMovementV20_STABLE.lua` permanece byte-identical com SHA-256:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
