# V610 — Input Semantic and Timing Trace

## Escopo fechado

A V610 continua diretamente da V609. Ela não reabre ownership V604, root yaw
V605, composição BaseCamera V606, MouseLockController V607, writers V608 nem o
bloco custom do Evade encerrado pela V609.

O único alvo é a primeira divergência funcional entre os caminhos que alimentam
`activeCameraController.rotateInput`:

```text
Touch real -> OnInputChanged(Touch) -> OnTouchChanged

Mouse PC -> OnInputChanged(MouseMovement) -> OnMouseMoved

V604 -> OnInputChanged(Touch) -> bookkeeping Touch -> OnMouseMoved(mesmo Touch)
```

Esta build é somente diagnóstica. O experimento permanece bloqueado.

## Evidência herdada, sem repetir scans

A V605 mediu coeficientes distintos:

- Touch: aproximadamente `0.029688 rad/delta X` e `0.010603 rad/delta Y`;
- rota `OnMouseMoved`: aproximadamente `0.006283 rad/delta X` e
  `0.004712 rad/delta Y`.

A V609 mostrou `rotateInput = 0, 0` no tail de `CameraModule.Update`, indicando
que o valor precisa ser observado antes e durante o update, não depois do frame.

## Análise estática focada

Não existe nova varredura ampla. A V610 acessa somente os objetos já conhecidos:

- `CameraModule.Update`;
- `activeCameraController.Update`;
- `OnInputChanged`;
- `OnTouchChanged`;
- `OnMouseMoved`;
- `InputTranslationToCameraAngleChange`;
- `CalculateNewLookCFrame`.

Se `decompile` estiver disponível, somente `BaseCamera` e o módulo do controller
ativo (`ClassicCamera` ou `OrbitalCamera`) são lidos. O relatório guarda janelas
limitadas ao redor dos nomes acima e de `rotateInput`; não percorre novamente o
PlayerModule inteiro.

## Instrumentação runtime

Para cada callback de input, a probe registra:

- tipo e `Delta` do `UserInputObject` real;
- estado do relay;
- identidade entre o Touch externo e o Touch passado a `OnMouseMoved`;
- `rotateInput` antes/depois;
- coeficiente por eixo entre `input.Delta` e mudança de `rotateInput`;
- intervalo entre callbacks;
- tempo entre a última escrita e o próximo `CameraModule.Update`;
- `UserGameSettings.MouseSensitivity` apenas como leitura;
- viewport usada durante cada rota;
- alterações nos campos persistentes relevantes do controller.

`InputTranslationToCameraAngleChange` é observado diretamente, incluindo
argumentos, retorno e coeficiente. Isso separa a normalização do Touch do ganho
da rota Mouse.

## Consumo e reset por frame

A V610 mede, na ordem real:

1. `rotateInput` na entrada de `CameraModule.Update`;
2. quantidade e soma das escritas acumuladas desde o frame anterior;
3. `rotateInput` na entrada de `activeCameraController:Update(dt)`;
4. valor antes/depois de `CalculateNewLookCFrame`;
5. valor na saída do controller e do CameraModule.

Também registra `dt` do update, quantidade de callbacks agrupados antes de um
único frame e se o reset ocorreu dentro ou depois de
`CalculateNewLookCFrame`. Os handlers registram se receberam algum argumento
numérico extra semelhante a `dt`; nenhum valor é injetado.

## Critério de decisão

`timingDivergenceFound` só fica true quando o runtime prova que o relay chamou
`OnMouseMoved` sincronamente dentro de um `OnInputChanged(Touch)`, usando o
mesmo objeto Touch. Isso demonstra que reutilizar a função Lua não cria um
evento `MouseMovement` independente nem a cadence nativa do PC.

`gainOriginFound` exige amostras das duas rotas, coeficientes observáveis e
chamadas reais ao helper de tradução Touch. Uma diferença numérica isolada não
libera experimento.

`pcSemanticsReproducible` e `experimentEligible` permanecem false na V610: o
iPhone não expõe uma fonte nativa segura de `MouseMovement`, e a probe não cria
input sintético nem agenda uma imitação antes de haver prova suficiente.

O relatório termina obrigatoriamente com:

```text
touchInputPipeline
mouseInputPipeline
firstInputSemanticDivergence
timingDivergenceFound
gainOriginFound
pcSemanticsReproducible
anchorRelevance
experimentEligible
```

## Teste no iPhone + Delta, em uma sessão

Não saia do Roblox durante as fases:

1. Execute `Loader.lua` uma vez.
2. Pressione **INICIAR**.
3. Com **RELAY V604: OFF**, arraste a câmera de forma contínua por 15 segundos.
4. Segure/mova o joystick com um dedo e arraste a câmera com outro para manter a
   prova de ownership disponível.
5. Pressione **RELAY V604** para ligá-lo.
6. Repita por 15 segundos um arrasto parecido, incluindo joystick + câmera.
7. Pressione **PARAR**.
8. Pressione **COPIAR REPORT COMPLETO**.
9. Só saia após aparecer `REPORT COPIADO. Agora pode sair e colar.`

**EMERGÊNCIA** para a coleta, restaura os hooks V610, desliga apenas o relay e
mantém o fail-open V500.

O ciclo herdado da correção V606/V609 foi mantido: **PARAR**, **COPIAR** e
**EMERGÊNCIA** restauram imediatamente cada função hookada. O relatório expõe
`hookRestoreOk` e `hookRestoreDetail`; pressionar esses botões antes mesmo de
iniciar também remove os wrappers ociosos.

## Segurança

A V610:

- não escreve `Camera.CFrame`, `RootPart.CFrame` ou `PrimaryPart.CFrame`;
- não força `PreferredInput`, `MouseBehavior`, `RotationType` ou `AutoRotate`;
- não altera `MouseSensitivity`, ganho, WalkSpeed ou física;
- não usa `firesignal`, VirtualInput ou `UserInputObject` sintético;
- não chama `UpdateMouseBehavior`;
- preserva integralmente V604 e V500.

`PCMovementV20_STABLE.lua` permanece byte-identical com SHA-256:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
