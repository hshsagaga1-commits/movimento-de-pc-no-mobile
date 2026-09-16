# V614 — Controlled Yaw/Pitch Segment Matching — Acquisition R2

## Escopo

A V614 continua diretamente da V613. Ela não reabre V604–V613, não implementa
correção de câmera e não tenta reproduzir PC. O único objetivo é obter unidades
Touch-versus-relay comparáveis sem alterar qualquer uma das duas rotas.

Relay continua significando somente:

```text
V604 OnMouseMoved(same real Touch UserInputObject)
```

Não existe alegação de MouseMovement PC nativo.

## Revisão Acquisition R2 — auditoria do primeiro teste V614

O primeiro runtime V614 foi estruturalmente limpo (`frameCorrelationErrors=0`,
`callbackErrors=0`, `controllerErrors=0`), mas terminou com 48 segmentos Touch,
6 relay e somente 3 pares. A reconstrução dos 3.475 samples aceitos reproduziu
exatamente todos os contadores do relatório.

```text
Touch accepted span: 31,999188 s
Touch target reaches: 359
Touch eligible: 48 = 1,500038 eligible/s

Relay accepted span: 35,633830 s
Relay target reaches: 69
Relay eligible: 6 = 0,168379 eligible/s
```

Relay não recebeu menos tempo: B1 e B2 tiveram aproximadamente `17,48 s` e
`18,15 s` de samples aceitos. A diferença foi a formação dos segmentos:

- 71 candidatos relay fecharam `short`, todos ainda abaixo de 60°;
- esses 71 vieram de 35 trocas de direção, 34 gaps de mais de três frames,
  uma troca de fase e um fim de coleta;
- 69 candidatos chegaram a 60°;
- 63/69 foram rejeitados pelo pitch já predefinido;
- 60 tinham `abs(netPitch)>2°`, 49 excediam o limite de pitch absoluto e 46
  falhavam ambos;
- somente seis ficaram elegíveis.

Assim, a causa primária por contagem foi fragmentação antes de 60° (`short=71`),
agravada pelo menor yaw/frame do relay. A causa secundária, quase total entre os
segmentos que alcançaram o alvo, foi pitch (`63/69`). Nenhum threshold foi
recalculado a partir desses números.

## Aquisição controlada R2

O matching permanece idêntico. A revisão muda somente painel e encerramento de
fase. O alvo foi fixado antes do novo resultado em 16 segmentos elegíveis por
janela ABBA:

```text
A1 Touch: 16
B1 relay: 16
B2 relay: 16
A2 Touch: 16
```

Isso produz 32 elegíveis por rota. Aplicando apenas como planejamento a antiga
compatibilidade descritiva de 3/6, a expectativa é 16 pares, quatro de margem
sobre os 12 exigidos. O valor não altera input, segmento nem matching.

Ao atingir o alvo, cada janela — inclusive A2 — vira `complete` e deixa de
aceitar novos samples. A próxima janela é recusada enquanto a atual não estiver
completa. `potentialPairs` é recalculado após cada segmento elegível pelos
calipers originais e informa separadamente se os 12 pares foram alcançados; ele
não reabre nem prolonga uma janela que já atingiu os 16 segmentos predefinidos.

## Auditoria decisiva da V613

O arquivo integral do relatório V613 contém 730 samples Touch e 467 relay.
O pipeline executado foi:

```text
standing válido
→ abs(pitch) <= 0.350°
→ suporte yaw p05–p95 compartilhado
→ bins fixos de 0.500°
→ >=20 samples de cada rota no mesmo bin
→ diferença das medianas de yaw <=0.150°
→ agregação
→ moving-block bootstrap
→ validationReady
```

Resultados reconstituídos diretamente dos 1.197 registros por frame:

- filtro de pitch reteve 218/730 Touch (`29,86%`);
- filtro de pitch reteve 128/467 relay (`27,41%`);
- suporte compartilhado pitch-valid: `0,850618°–22,185006°`;
- 22 bins possuíam ao menos um sample de cada rota;
- 13 desses 22 tinham median yaw gap `<=0,150°`;
- nenhum bin tinha 20 samples em ambas as rotas;
- ocupação máxima: Touch 17, relay 6;
- mesmo removendo retrospectivamente o filtro de pitch, nenhum bin de `0,5°`
  chegaria a 20 em ambas as rotas.

Logo, `medianYawGap` não foi o primeiro gate bloqueador. O mínimo 20 por rota,
com bins estreitos e dados lattice-sparse, foi decisivo. O filtro de pitch
agravou fortemente a escassez, mas não foi a única causa. Não há evidência de
bug no código do gate e o resultado não pode ser descrito simplesmente como
“o usuário precisava coletar mais”.

## Quantização observada

Os valores reais mostram duas grades:

```text
Touch: aproximadamente 0,8505° por passo básico
       rotateInput.x aproximadamente 0,014844 rad

relay: aproximadamente 0,18° por passo básico
       rotateInput.x aproximadamente 0,0031416 rad
```

As duas grades têm sobreposição parcial/acidental, mas não oferecem matching
per-frame denso. A distribuição também foi diferente: no conjunto completo, a
mediana yaw/frame foi aproximadamente `17,8605°` Touch e `12,2400°` relay.
Isso não autoriza mudar gain; a quantização e a cadência permanecem dados.

## Origem dos 157 correlation errors

A V613 executava isto dentro do hook de `CameraModule.Update`:

```text
finalizeFrame
→ refreshLiveStatus
→ statusLabel.Text / statusLabel.TextColor3
→ refreshPhaseButtons
→ propriedades de GUI Instances
```

No Delta, a thread que chamou o hook não possuía capability Plugin para acessar
esses GUI Instances. O estágio ficou como `commit-sample` em 95 erros e como
`standing-gate` em 62.

O refresh ocorre depois da decisão/commit da amostra. Portanto:

- os 95 erros `commit-sample` aconteceram depois de a amostra ser gravada;
- os 62 restantes ocorreram em frames não committed, como estabilização ou
  frames não aceitos, também depois da decisão standing;
- não foi demonstrada remoção de uma amostra aceita;
- a parte posterior dos diagnósticos desses frames foi truncada.

A V614 não contorna capability. Ela remove qualquer acesso à GUI da thread
hookada. O hook atualiza somente dados Lua/primitivos. Um updater criado pela
thread superior do script atualiza o painel a cada `0,20 s` e usa `pcall`.

## Unidade escolhida

Matching per-frame foi rejeitado como unidade principal. Janelas com número
fixo de frames também foram rejeitadas porque igualariam duração, mas não yaw.

A V614 usa segmentos angulares não sobrepostos:

```text
alvo inicial de yaw absoluto: 60°
mesma direção: coerência >= 0,90
mínimo: 3 frames
máximo entre frames aceitos: 3 frames
duração máxima: 1,25 s
yaw máximo aceito após overshoot: 120°
abs(net pitch) <= 2°
total abs pitch <= max(5°, 6% do yaw)
```

O relatório V613 foi usado apenas para justificar a unidade antes da V614:
segmentos de 60° formaram 31 candidatos Touch, 17 relay e 13 pares compatíveis
numa simulação pós-hoc conservadora. Esses números não são resultado V614 e não
entram no seu gate.

Cada segmento preserva:

- duração e frame count;
- yaw assinado/absoluto e trajetória completa;
- pitch total, líquido, mean, median e trajetória;
- rota e janela ABBA;
- Head, PrimaryPart e subject em X/Y/2D;
- projeção observada e returned/controller;
- subject→PrimaryPart, subject→Head e PrimaryPart→Head no início/fim;
- yaw/pitch de câmera e geometria retornada.

## Matching entre segmentos

Um par precisa ter:

- mesma direção de yaw;
- diferença de yaw total `<=5°`;
- diferença de net pitch `<=1°`;
- diferença de total abs pitch `<=2°`.

O pareamento é one-to-one, sem reposição, pelo menor score normalizado. Duração,
frame count e trajetórias não são forçados a coincidir: continuam visíveis como
diferenças reais entre pipelines.

## Contrabalanceamento

A ordem obrigatória é:

```text
A1 Touch → B1 relay → B2 relay → A2 Touch
```

ABBA dá às duas rotas a mesma posição ordinal média sob uma tendência temporal
linear. Isso reduz, mas não elimina, confundimento de sessão. Por esse motivo a
V614 não declara causalidade PC.

## Estatística

Com pelo menos 12 pares válidos:

```text
unidade = par de segmentos não sobrepostos
método = paired moving-block bootstrap
block size = 3 pares em ordem temporal
iterations = 1000
estatística = mediana(relay - Touch)
CI = 95%
```

Frames adjacentes não são tratados como IID. Sem 12 pares,
`statisticalEvidence = unproved`.

## Corpus visual externo PC × mobile

Foram revisados oito vídeos completos por amostragem ao longo de cada arquivo:
cinco PC e três mobile. O trecho aproximadamente `20,0s–24,0s` da referência
PC Legacy e os demais vídeos são usados somente para caracterização qualitativa.
O corpus é compatível com maior rigidez perceptual da região Head/upper-torso
no PC e maior “folga” no mobile, mas não prova pivot, subject, mecanismo,
causalidade nem equivalência PC. Diferenças de crop, FOV, escala, resolução,
edição e estado do personagem impedem comparar pixels absolutos entre arquivos.
Nenhum valor visual foi usado para calibrar a probe.

```text
externalPCReferenceUsed = true
externalPCReferenceWindow = approximately 20.0s-24.0s
externalPCVideosReviewed = 5
externalMobileVideosReviewed = 3
externalVideoRole = qualitative-only
absoluteVideoPixelsUsedForCalibration = false
videoEvidenceChangedV614Thresholds = false
videoEvidenceChangedMatching = false
headMechanismClaimed = false
pcEquivalenceClaimed = false
pcEquivalenceClaimAllowed = false
```

## Painel mobile

O painel mostra em tempo real:

- phase, route e state;
- `currentSegmentYawDeg` e pitch líquido/absoluto;
- elegíveis na janela e totais Touch/relay;
- `matchedPairsAvailable` e `targetPairs=12`;
- correlationErrors e uiErrors;
- instruções `GIRE MAIS`, `CONTINUE`, `MANTENHA HORIZONTAL`, `PITCH ALTO`,
  `DIREÇÃO QUEBROU`, `GAP QUEBROU`, `SEGMENTO VÁLIDO`, `MUDE A DIREÇÃO`,
  `COBERTURA RELAY BAIXA`, `FASE COMPLETA` e
  `COBERTURA SUFICIENTE`.

Ele não pede pixels e não transforma input.

## Teste em uma sessão

1. Execute `Loader.lua` no Delta.
2. Toque **INICIAR**.
3. Toque **1 • A1 TOUCH**; espere `active`.
4. Parado e sem joystick, gire principalmente na horizontal até
   **FASE COMPLETA**; não conte segundos.
5. Toque **2 • B1 RELAY** e siga a GUI até **FASE COMPLETA**.
6. Toque **3 • B2 RELAY** e siga a GUI até **FASE COMPLETA**.
7. Toque **4 • A2 TOUCH** e siga até **FASE COMPLETA**.
8. Confirme `matchedPairsAvailable >= 12` e **COBERTURA SUFICIENTE**. Se a
   aquisição terminar abaixo de 12, não altere o teste: pare e copie o relatório
   insuficiente para auditoria.
9. Toque **PARAR**.
10. Toque **COPIAR REPORT COMPLETO** e só saia após `REPORT COPIADO`.

## Segurança

A V614 não escreve Camera/Focus/RootPart/PrimaryPart/Head CFrame, não altera
CameraSubject, gain, sensitivity, física, PreferredInput, MouseBehavior,
RotationType ou AutoRotate. Não usa `UpdateMouseBehavior`, VirtualInput,
`firesignal` ou UserInputObject sintético.

V604 ownership/relay e V500 fail-open são preservados. V20, V500 e V604 devem
permanecer byte-identical.

## Validação pré-publicação

```text
LuauValidation = pass: luau-compile
LoaderValidation = pass: luau-compile plus cache-busted V614 R2 URL
StateTransitionValidation = pass: ABBA order, early-advance rejection, freeze at 16 per window, no 17th sample, 32 per route
ProhibitedWriteAudit = pass: no prohibited property writes or input APIs added

V20 SHA-256  = 634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
V500 SHA-256 = 5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096
V604 SHA-256 = 19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571

matchingCriteriaChanged = false
calipersChanged = false
gainChanged = false
cameraCorrectionAdded = false
v615Created = false
```
