# V614 — Temporal/Pose Telemetry R1

## Continuidade e objetivo

Esta é uma revisão instrumental da própria V614, posterior ao commit
`5b1a4bee3fee00ff8005bd0a0bd912602152e7e2` e à conclusão de
`V614_CAUSAL_GEOMETRIC_AUDIT.md`. Ela não cria V615, não reabre V604–V613 e
não implementa correção de câmera.

A auditoria anterior reproduziu o efeito horizontal route-conditioned da Head,
mas mostrou que o relay percorreu yaw semelhante em aproximadamente `180,89 ms
/ 10,86 frames`, contra `77,38 ms / 4,64 frames` no Touch. Como a V614 não
registrava pose local, juntas, tracks nem o `Camera.CFrame` completo nos mesmos
limites, tempo e estado inicial permaneceram confundidores.

O objetivo desta revisão é produzir exatamente a observação faltante, mantendo
inalterados:

- aquisição e congelamento de cobertura da V614 Acquisition R2;
- ordem ABBA `A1 Touch -> B1 relay -> B2 relay -> A2 Touch`;
- ownership/relay V604;
- segmentos não sobrepostos de aproximadamente 60 graus;
- matching one-to-one, direção, calipers de yaw/pitch e bootstrap;
- standing gate, gain, sensitivity, física e geometria já medida.

## Telemetria adicionada

Para cada frame potencialmente aceito da fase ativa, a probe captura snapshots
read-only em quatro limites:

1. imediatamente antes de `CameraModule.Update`;
2. imediatamente antes do `activeCameraController:Update`;
3. imediatamente depois do `activeCameraController:Update`;
4. imediatamente depois de `CameraModule.Update`.

Cada snapshot contém somente valores imutáveis/tabelas simples:

- `Camera.CFrame` completo via 12 componentes, `FieldOfView` e `ViewportSize`;
- `PrimaryPart.CFrame`, `Head.CFrame` e
  `PrimaryPart.CFrame:ToObjectSpace(Head.CFrame)`;
- `Neck`, `Waist` e `RootJoint`, quando forem `Motor6D`: `Transform`, `C0`,
  `C1`, `Part0` e `Part1`;
- estado do Humanoid;
- todos os tracks ativos retornados por `Animator:GetPlayingAnimationTracks()`:
  `AnimationId`, nome, `TimePosition`, `WeightCurrent`, `WeightTarget`, `Speed`,
  `IsPlaying`, `Looped`, prioridade e duração.

`C0/C1` são registrados porque permitem reconstruir a relação do `Motor6D` sem
inferir a base da junta. Nenhuma `Instance` é serializada no relatório.

## Proteção e efeito sobre o runtime

As leituras sensíveis usam `pcall` e são fail-open. Um erro de capability não
derruba `Controller.Update`, não muda elegibilidade e não escreve estado; ele é
contabilizado em:

```text
telemetryCaptureErrors
telemetryCaptureErrorSources
```

Para reduzir perturbação, a captura só é ativada quando a janela está `active`
e o frame já possui exclusivamente a rota esperada. Frames de idle,
estabilização, rota errada e ausência de input não executam a leitura pesada de
juntas/tracks.

O relatório detalhado serializa a nova telemetria apenas para os segmentos que
entraram nos pares finais. Os dados dos demais samples continuam com o formato
V614 anterior. Para limitar memória no iPhone, o campo novo é removido assim
que um segmento é rejeitado e, em `PARAR`, também dos segmentos elegíveis que
não entraram no matching final; nenhuma métrica antiga é removida. O gate
`validationReady` agora exige:

- zero `callbackErrors`, `controllerErrors`, `frameCorrelationErrors`,
  `uiRefreshErrors` e `telemetryCaptureErrors`;
- pelo menos 12 pares pelo matching original;
- quatro janelas ABBA completas;
- snapshots completos de CameraModule e pelo menos um Controller.Update em
  todos os samples dos pares.

## O que a próxima análise poderá separar

Os componentes completos permitem reconstruir, par a par:

- movimento/rotação do `PrimaryPart`;
- mudança de `PrimaryPart -> Head` no espaço local;
- contribuição local de `Neck`, `Waist` e `RootJoint`;
- progressão e mistura dos tracks durante cada segmento;
- projeção contrafactual com câmera fixa/pose móvel e câmera móvel/pose fixa;
- duração e número de frames sem confundi-los com yaw total;
- diferença de estado inicial de câmera, pose e animação antes de qualquer
  interpretação causal.

Esta build não aplica um novo caliper temporal ou de pose. Fazer isso antes de
observar se existe suporte comum seria outro critério post-hoc. O relatório
termina, portanto, com os campos causais marcados como `unproved` até a nova
coleta ser auditada pair-by-pair.

## Relatório e workflow mobile

O painel e o fluxo permanecem os mesmos, em uma sessão:

1. executar `Loader.lua` e tocar em **INICIAR**;
2. concluir A1 Touch, B1 Relay, B2 Relay e A2 Touch seguindo a GUI;
3. confirmar cobertura suficiente;
4. tocar em **PARAR**;
5. tocar em **COPIAR REPORT COMPLETO** antes de sair do Roblox.

Nova seção:

```text
=== V614 MATCHED TEMPORAL POSE TELEMETRY ===
```

O relatório termina explicitamente com:

```text
temporalConfoundResolved
initialPoseConfoundResolved
rootMotionContribution
jointTransformContribution
animationProgressContribution
projectionDepthContribution
headHorizontalEffectAfterTemporalControl
firstConcreteGeometricDivergence
causalMechanismProved
implementationTargetIdentified
v615Justified
astra6MaxJustified
```

Antes do novo runtime, esses campos permanecem `unproved`/`false`. Isso é uma
restrição científica, não uma falha da probe.

## Segurança

A revisão não adiciona escrita em `Camera.CFrame`, `Camera.Focus`,
`PrimaryPart/RootPart/Head.CFrame`, `Motor6D.Transform/C0/C1`, animações,
`CameraSubject`, gain, sensitivity, input, `PreferredInput`, `MouseBehavior`,
`RotationType`, `AutoRotate` ou física. Não usa `VirtualInput`, `firesignal` nem
`UserInputObject` sintético. O relay V604 e o fail-open V500 permanecem
inalterados.

## Decisão pré-runtime

```text
temporalConfoundResolved = unproved
initialPoseConfoundResolved = unproved
rootMotionContribution = unproved
jointTransformContribution = unproved
animationProgressContribution = unproved
projectionDepthContribution = unproved
headHorizontalEffectAfterTemporalControl = unproved
firstConcreteGeometricDivergence = unproved after temporal/initial-pose control
causalMechanismProved = false
implementationTargetIdentified = false
v615Justified = false
astra6MaxJustified = false
```

Se a nova coleta não oferecer sobreposição suficiente de estado inicial, a
menor aquisição seguinte será repetir a mesma V614 orientando apenas a cobertura
da variável identificada como ausente. Nenhum critério será relaxado
retroativamente e nenhum novo subsistema será aberto por conveniência.

## Validação pré-publicação

```text
LuauValidation = pass: luau-compile runtime + Loader
LoaderValidation = pass: mesmo arquivo V614 + revision TemporalPoseTelemetryR1 + GUID cache busting
StateTransitionValidation = pass: lógica ABBA/freeze/coverage sem alteração
MatchingValidation = pass: SEGCFG, calipers, one-to-one e bootstrap sem alteração
ProhibitedWriteAudit = pass

V614 runtime SHA-256 = 4a8e278778336c373d62635a295cab8d678562bfc234d2fb354cc738c2fc6e7e
Loader SHA-256       = d8f8f857bde504b8de11c69e0ddd497222642836ae1e0c33de11e2a837d130d1
V20 SHA-256          = 634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
V500 SHA-256         = 5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096
V604 SHA-256         = 19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571
```
