# V606 — Targeted Mouse-Lock Composition Trace

## Ponto de partida preservado

A V606 continua diretamente da evidência real da V605. Ela não repete a busca
global de callbacks, não reabre ownership e não altera o ganho.

A camada funcional continua sendo a V604 publicada, sem mudança na arquitetura:

```text
joystick Touch real -> bloqueado do mouse path pela identidade do movement controller
camera Touch real   -> OnTouchChanged bookkeeping -> mesmo objeto -> OnMouseMoved
unknown/pinch       -> fail-open preservado
```

A V606 carrega a V604, reutiliza o painel para ligar/desligar seu relay validado
e mantém V500 como fallback. O relay começa desligado e ainda exige prova de
ownership simultâneo na sessão atual antes de aceitar ativação.

## Conclusão usada da V605

O Root acompanha o yaw da câmera quase 1:1 durante movimento. Assim, a V606 não
tenta corrigir yaw do RootPart. A diferença restante é tratada como composição
de câmera/subject/focus durante mouse-lock.

A V605 também mostrou que o jogo executa `CameraModule.Update` uma vez por frame
e expôs neste método as constantes `ShiftLockEnabled`, `SetIsMouseLocked`,
`Character`, `PrimaryPart`, `ToOrientation` e `CFrame`. Ao mesmo tempo, o active
camera controller executou os getters de mouse-lock/offset e os métodos de look.
Isso restringiu a V606 a essa cadeia; os scans amplos da V605 não são refeitos.

## Cadeia instrumentada

A V606 instala wrappers observacionais somente nos alvos alcançados a partir da
cadeia já provada:

- `CameraModule.Update`;
- `activeCameraController.Update`;
- `UpdateMouseBehavior` (observado, nunca chamado pela V606);
- `Set/GetIsMouseLocked` e `Set/GetMouseLockOffset`;
- `GetSubjectPosition`;
- `CalculateNewLookCFrame` e `GetCameraLookVector`;
- `activeOcclusionModule.Update`;
- getters do `activeMouseLockController`, quando expostos;
- `CameraModule.OnMouseLockToggled` é inspecionado, mas não chamado.

Cada wrapper encaminha `self`, argumentos e retornos originais. Quando o trace
está parado ele faz somente o encaminhamento, sem contabilizar ou amostrar. Ao
iniciar uma nova coleta, todos os contadores, últimas amostras e acumuladores da
janela anterior são zerados. Ao parar ou copiar, a janela fica congelada.

## Evidência dinâmica produzida

Para cada frame amostrado, o relatório registra a ordem real de entrada/saída
dos estágios e seus valores principais:

- Camera CFrame/Focus na entrada e na saída de `CameraModule.Update`;
- CFrame/Focus retornados pelo controller;
- posição retornada por `GetSubjectPosition`;
- look CFrames retornados por `CalculateNewLookCFrame`;
- lock e offset realmente consumidos dentro do update;
- MouseBehavior e RotationType antes/depois de `UpdateMouseBehavior`;
- argumentos de SetIsMouseLocked/SetMouseLockOffset, separados entre chamadas
  dentro e fora de `CameraModule.Update`;
- mudança observada do `Character.PrimaryPart` durante o update do jogo;
- alteração feita pelo occlusion module;
- alterações posteriores à saída de `CameraModule.Update`, amostradas em
  prioridade `Camera + 20`;
- projeção do HumanoidRootPart e separação automática entre frames parado e
  andando, apenas para medir a deriva — nunca para realimentá-la.

## Prova da composição do offset

A cada frame que contém subject, focus, offset e look, a V606 testa a hipótese
nativa de composição:

```text
offsetTotal = GetMouseLockOffset() + Humanoid.CameraOffset
offsetMundo = X*Look.RightVector + Y*Look.UpVector + Z*Look.LookVector
shiftReal   = controllerFocus.Position - subjectPosition
resíduo     = magnitude(shiftReal - offsetMundo)
```

Todos os look CFrames realmente produzidos no frame são candidatos; o menor
resíduo é registrado. `compositionMatchRatio` usa tolerância de 0,025 studs.
Isso permite demonstrar se o shoulder offset já está aplicado no controller,
em vez de inferir pela simples presença de `mouseLockOffset = 2, 0.5, 0`.

## Classificação da primeira divergência

`firstDivergenceCandidate` é calculado somente depois da coleta, nesta ordem:

1. controller composition não capturada;
2. offset não consumido dentro do update;
3. offset camera-relative não explica o Focus retornado;
4. transformação posterior a `CameraModule.Update` altera o resultado final;
5. native MouseLockController reporta unlocked enquanto o camera controller foi
   colocado em locked;
6. `PreferredInput.Touch` impede a ativação nativa de mouse-lock embora a
   composição downstream já esteja presente;
7. bloco Evade `ShiftLockEnabled` e composição executam juntos, sem estágio
   ausente ainda demonstrado;
8. nenhuma primeira divergência provada dentro da cadeia medida.

Os campos `dynamicChainProven`, `compositionStageProven`,
`compositionMatchRatio`, `sequenceSummary`, contadores inside/outside,
`primaryPart*`, `occlusion*` e `postCamera*` fornecem a evidência usada nessa
classificação.

## Experimento opt-in

Não há mutação experimental nesta build. O botão permanece visível como
`EXPERIMENTO NATIVO: BLOQUEADO` e contabiliza tentativas recusadas.

Isso é intencional: análise estática e V605 restringiram a cadeia, mas ainda não
provaram uma transformação nativa ausente que possa ser reaplicada sem escrever
CFrames ou duplicar a composição. A V606 prefere produzir a evidência decisiva
a chutar uma correção.

## Teste mobile em uma única sessão

Não saia do Roblox até o painel confirmar que o relatório foi copiado.

1. Execute `Loader.lua` uma vez. O painel V606 aparece à direita e pode ser
   arrastado ou recolhido.
2. Antes do trace, segure/mova o joystick e arraste a câmera com outro dedo para
   provar o ownership V604 na sessão atual.
3. Toque em **RELAY V604: DESLIGADO**. Ele deve mudar para **LIGADO**. Se for
   recusado, repita o gesto simultâneo e tente novamente.
4. Toque em **INICIAR TRACE**.
5. Parado, gire horizontal e verticalmente; faça reversão rápida, uma volta de
   aproximadamente 180 graus, pitch forte e zoom/pinch.
6. Depois segure o joystick e, com outro dedo, repita rotações enquanto anda,
   incluindo terreno inclinado se for seguro no jogo.
7. Toque em **PARAR TRACE** e depois **COPIAR REPORT COMPLETO**.
8. Só saia do Roblox quando aparecer `REPORT COPIADO. Agora pode sair e colar.`

O botão vermelho **EMERGÊNCIA • RELAY OFF / V500** para a coleta e desliga o
relay imediatamente, mantendo V500 ativo. Nenhum console/F9 é necessário.

## Restrições verificáveis

A V606 não cria UserInputObject sintético, não usa `firesignal`, VirtualInput,
reconnect, regiões/half-screen ou `processed` como gate. Ela não chama
`UpdateMouseBehavior`, não escreve `Camera.CFrame` nem
`HumanoidRootPart.CFrame`, não força `Humanoid.AutoRotate`, não ajusta
sensibilidade/gain e não altera WalkSpeed, velocidade ou física. A projeção de
tela é exclusivamente observacional.

`PCMovementV20_STABLE.lua` permanece byte-identical com SHA-256 obrigatório:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
