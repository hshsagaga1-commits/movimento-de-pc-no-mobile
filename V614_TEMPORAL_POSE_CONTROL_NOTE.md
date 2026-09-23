# V614 Temporal + Initial-Pose Control R2

## Escopo da revisão

Esta revisão acrescenta uma análise secundária determinística sobre a telemetria
somente-leitura já capturada. Ela não altera aquisição, ownership/relay V604,
formação dos segmentos de 60 graus, ordem ABBA, matcher Baseline, calipers
Baseline, bootstrap, gain, sensibilidade, câmera, personagem, juntas, animações
ou física. Nenhuma V615 ou correção de câmera foi criada.

O Loader continua usando o arquivo
`PCMovementV614_ControlledYawPitchMatching.lua` e muda apenas o cache bust para
`V614-TemporalPoseControlR2-FullClipboardR1`. O runtime identifica esta revisão
como `V614-ControlledYawPitchMatching-TemporalPoseControlR2` e o relatório usa o
schema `V614-EssentialReportR2-TemporalPoseControl`.

## Baseline e aquisição protegidos

As seguintes regiões permanecem byte-identical ao checkpoint
`a288b72c0ed8a7154045be9d797be677c1bd4d3d`:

| Região/função protegida | SHA-256 |
|---|---|
| `standingObservation` | `3fb21fc9df1e874d3236554ffcda9de185bbaee489904d1955f871c2c1ce821d` |
| `recordPairedSample` | `2f790200d79140c884d634f65828c9bc51feab50717c5824aed7aa180e40c952` |
| `closeCurrentSegment` | `4a5c00d066a4d763c1e7763314fe9e796909ee945b027be2c8ba444924cd6ca8` |
| `segmentConsumer` | `c13a1ce2ca5f6cad32ff3c82855a9f2348bdd0a046b4866673b7829f5e694203` |
| `SEGCFG.matchSegments` | `d720b294563ff5b550548a9fb6690d33e517693cced879c7f4dcc89faa9cef27` |
| `SEGCFG.updateCoverageState` | `9fe57eebb16f98b60f31de7c8ea37dc9ee7b6806945fa4684a4ff13c512e86f3` |

Os arquivos-base protegidos também permanecem byte-identical:

| Arquivo | SHA-256 |
|---|---|
| `PCMovementV20_STABLE.lua` | `634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef` |
| `PCMovementV500_ScrapFusion.lua` | `5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096` |
| `PCMovementV604_MultitouchOwnershipProbe.lua` | `19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571` |

O Baseline continua exigindo mesma direção e os calipers exatos
`yawGap <= 5 graus`, `netPitchGap <= 1 grau` e
`absPitchGap <= 2 graus`. Ele continua usando o matcher guloso existente e não
é renomeado como controle temporal ou de pose.

## Variáveis, fórmulas e unidades

Para um segmento Touch `T` e um segmento relay `R`, os gaps são calculados
antes da seleção:

```text
yawGap = abs(T.totalAbsYaw - R.totalAbsYaw)                         graus
netPitchGap = abs(T.netPitch - R.netPitch)                         graus
absPitchGap = abs(T.totalAbsPitch - R.totalAbsPitch)               graus
durationGap = abs(T.duration - R.duration)                         segundos
frameCountGap = abs(T.frameCount - R.frameCount)                   frames
animationAdvanceGap = abs(T.animationAdvance - R.animationAdvance) segundos
localHeadTranslationGap = norm(pT - pR)                            studs
localHeadRotationGap = degrees(acos(clamp((trace(RT^T RR)-1)/2)))  graus
cameraPrimaryRotationGap = distância angular entre
    (RPrimaryT^T RCameraT) e (RPrimaryR^T RCameraR)                graus
initialHeadDepthGap = abs(T.initialHeadDepth - R.initialHeadDepth) studs
```

`sameDirection` exige `T.totalSignedYaw * R.totalSignedYaw > 0`. FOV e viewport
iniciais devem ser exatamente iguais. `animationAdvance` é a progressão do
início ao fim; em track looped usa `(endTime - startTime) mod L`, e em track
não looped usa `endTime - startTime`.

### Fase circular e track dominante

Para uma track looped de comprimento `L`:

```text
d = abs(timeTouch - timeRelay) mod L
animationPhaseGap = min(d, L - d) segundos
animationPhaseFraction = animationPhaseGap / L
```

Para uma track não looped,
`animationPhaseGap = abs(timeTouch - timeRelay)` em segundos. O valor ausente
ou inválido rejeita o candidato; não é substituído por zero.

A track dominante inicial precisa estar tocando e ter `WeightCurrent > 0`.
Escolhe-se o maior `WeightCurrent`; empate usa a menor chave estável
`AnimationId|name|priority|looped|length`. Identidade duplicada é ambígua e
rejeita a feature. Touch e relay devem ter a mesma chave de track e o mesmo
`HumanoidState`, com `speedGap <= 0.05` e `weightGap <= 0.05`.

## Perfis fixos e gates

Os perfis são literais predeclarados. Eles não se alargam conforme cobertura,
efeito observado ou significância.

| Gate | Strict | Moderate (primário) | Broad |
|---|---:|---:|---:|
| `durationGap` | 0.034 s | 0.067 s | 0.100 s |
| `frameCountGap` | 2 frames | 4 frames | 6 frames |
| `animationAdvanceGap` | 0.034 s | 0.067 s | 0.100 s |
| `localHeadTranslationGap` | 0.025 stud | 0.050 stud | 0.100 stud |
| `localHeadRotationGap` | 1.0 grau | 2.5 graus | 5.0 graus |
| `animationPhaseFraction` | 0.05 | 0.10 | 0.20 |
| `cameraPrimaryRotationGap` | 2.0 graus | 5.0 graus | 10.0 graus |
| `initialHeadDepthGap` | 0.025 stud | 0.050 stud | 0.100 stud |

Todos os perfis preservam ainda os gates Baseline 5/1/2 graus, mesma direção,
identidade de track e estado, `speedGap <= 0.05`, `weightGap <= 0.05` e
igualdade exata de FOV/viewport. Dados ausentes, ambíguos ou inválidos falham
fechados e geram motivo de rejeição contado.

Para candidatos que passam todos os gates, a distância científica é:

```text
D² = Σ (gap_i / caliper_i)²
D = sqrt(D²)
```

A soma contém os 11 gaps numéricos: yaw, net pitch, absolute pitch, duração,
frames, avanço de animação, translação local do Head, rotação local do Head,
fração de fase circular, rotação câmera-Primary e profundidade inicial do Head.
Cada razão é arredondada ao `1e-6` mais próximo; `D²` vira custo inteiro na
escala `1e12`. Speed, weight, identidade, estado, direção e configuração da
câmera são gates, não pesos ajustados.

## Seleção determinística e retenção

Strict, Moderate e Broad são resolvidos de forma independente:

1. maximiza-se a cardinalidade do matching bipartido one-to-one;
2. entre soluções de cardinalidade máxima, minimiza-se o custo inteiro total
   derivado de `D`;
3. entre soluções de mesmo custo, escolhe-se canonicamente a lista
   lexicograficamente menor de pares `(Touch ID, relay ID)`;
4. os pares finais são ordenados cronologicamente para o moving-block
   bootstrap.

Os IDs estáveis servem apenas ao desempate canônico e não entram em `D`.

Ao `PARAR`, o runtime fotografa todos os elegíveis antes de qualquer pruning. A
coleta-alvo congela 32 features Touch e 32 relay, derivadas das quatro janelas
de 16 segmentos (`A1/B1/B2/A2`). Baseline e os três perfis são calculados sobre
essa fotografia. Depois, a telemetria detalhada retida é a união dos segmentos
selecionados pelo Baseline, Strict, Moderate e Broad; as 32+32 features
compactas, os contadores e os motivos de rejeição permanecem no Essential
Report. A preparação ou uma lista inválida falha fechada antes do pruning.

O modelo deduplica um segmento usado por mais de um conjunto. Se nenhuma
definição de Neck, Waist ou RootJoint tiver sido capturada, o JSON contém
`constants.joints=[]`. Nesse caso não há base para alegar controle ou mecanismo
em nível de joint; a pose local agregada `PrimaryPart:ToObjectSpace(Head.CFrame)`
continua sendo o controle disponível.

## Interpretação do relatório

O bloco **Baseline** preserva a comparação publicada e deve ser lido como
efeito descritivo condicionado à rota. Ele não controla duração, frame count,
progressão/fase de animação e pose inicial e não prova causalidade.

**Moderate** é o resultado controlado primário. **Strict** e **Broad** são
somente análises de sensibilidade. Para qualquer perfil com menos de 12 pares:

```text
temporalConfoundResolved = unproved: insufficient controlled overlap
initialPoseConfoundResolved = unproved: insufficient controlled overlap
```

Esse caso mantém `causalMechanismProved`, `implementationTargetIdentified`,
`v615Justified`, `astra6MaxJustified` e `pcEquivalenceClaimAllowed` falsos.

Com pelo menos 12 pares Moderate, uma CI do Head que contém zero significa
“efeito não suportado sob estes controles”; não prova equivalência exata. Uma
CI que exclui zero significa que o efeito persiste sob os controles e orienta
a próxima investigação. Nenhum dos dois resultados identifica sozinho um
mecanismo causal. Esta revisão não faz alegação de causalidade de PC nem de
equivalência com PC.

## Exportação mobile preservada

O fluxo continua:

```text
Loader -> INICIAR -> A1 -> B1 -> B2 -> A2 -> PARAR
-> COPIAR REPORT ESSENCIAL COMPLETO
```

`COPIAR REPORT ESSENCIAL COMPLETO` continua sendo a rota primária de um toque:
ela reconstrói e copia exatamente a string Essential R2 congelada. O painel dá
feedback visível de sucesso ou falha. `GERAR PARTES DO REPORT`,
`PARTE ANTERIOR` e `PRÓXIMA PARTE` permanecem como fallback, com reconstrução
exata por concatenação dos payloads.

O relatório continua publicando `fullReportChars`, `essentialReportChars`,
`reductionPercent` e `essentialChunks`.
