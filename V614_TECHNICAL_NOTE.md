# V614 — Controlled Yaw/Pitch Segment Matching

## Escopo

A V614 continua diretamente da V613. Ela não reabre V604–V613, não implementa
correção de câmera e não tenta reproduzir PC. O único objetivo é obter unidades
Touch-versus-relay comparáveis sem alterar qualquer uma das duas rotas.

Relay continua significando somente:

```text
V604 OnMouseMoved(same real Touch UserInputObject)
```

Não existe alegação de MouseMovement PC nativo.

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

## Referência PC externa

O trecho aproximadamente `20,0s–24,0s` do vídeo PC Legacy continua apenas como
referência qualitativa de uma região Head/upper-torso visualmente estável em
rotações grandes. Ele não define pivot, subject, threshold ou equivalência PC.

```text
externalPCReferenceUsed = true
externalPCReferenceWindow = approximately 20.0s-24.0s
pcEquivalenceClaimAllowed = false
```

## Painel mobile

O painel mostra em tempo real:

- phase/window e state;
- validSamples;
- pitchValidSamples pertencentes a segmentos elegíveis;
- usableMatchedSamples;
- yawCoverage Touch/relay;
- matchingCoverage;
- correlationErrors e uiErrors;
- orientação qualitativa de cobertura.

Ele não pede pixels e não transforma input.

## Teste em uma sessão

1. Execute `Loader.lua` no Delta.
2. Toque **INICIAR**.
3. Toque **1 • A1 TOUCH**; espere `active`.
4. Parado e sem joystick, faça rotações principalmente horizontais por ~15 s.
5. Toque **2 • B1 RELAY** e repita após `active`.
6. Toque **3 • B2 RELAY** e repita após `active`.
7. Toque **4 • A2 TOUCH** e repita após `active`.
8. Observe `usableMatchedSamples`; a meta mínima é 12.
9. Se o painel pedir “mais lento”, reduza apenas naturalmente a velocidade do
   gesto; o script não muda o input.
10. Toque **PARAR**.
11. Toque **COPIAR REPORT COMPLETO** e só saia após `REPORT COPIADO`.

## Segurança

A V614 não escreve Camera/Focus/RootPart/PrimaryPart/Head CFrame, não altera
CameraSubject, gain, sensitivity, física, PreferredInput, MouseBehavior,
RotationType ou AutoRotate. Não usa `UpdateMouseBehavior`, VirtualInput,
`firesignal` ou UserInputObject sintético.

V604 ownership/relay e V500 fail-open são preservados. V20, V500 e V604 devem
permanecer byte-identical.
