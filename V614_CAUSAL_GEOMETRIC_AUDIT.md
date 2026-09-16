# V614 — Auditoria causal/geométrica pós-runtime

## Escopo e imutabilidade

Esta auditoria continua do runtime **V614 Acquisition R2** já concluído. Ela não
reabre V604–V613, não cria V615 e não modifica o runtime, Loader, gain,
sensitivity, ownership, matching, calipers ou pitch thresholds.

Evidência primária:

```text
arquivo = PC MOVEMENT V614 REPORT =(1).md
SHA-256 = f4828f4f30ad093e1423d5707268514dd127053ada237eaa6f486c73deda773a
linhas = 2038
accepted per-frame samples = 1312
eligible non-overlapping segments = 64
matched segment pairs = 14
```

A reconstrução é reproduzível por `V614_CAUSAL_GEOMETRY_AUDIT.py` e usa apenas
campos existentes no relatório. O corpus PC/mobile permanece uma referência
qualitativa independente; nenhum pixel externo entrou em threshold ou cálculo.

Imutabilidade verificada antes do commit:

```text
V614 runtime SHA-256 = feaecc0a44ceff03d7e516cc90859685c0c35e720af5535b996bc317d919e5f0
Loader SHA-256       = bbc8d49d40a1665f9501c0631b748f2d2a5b97f77417904cd7327bccf0b731af
V20 SHA-256          = 634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
V500 SHA-256         = 5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096
V604 SHA-256         = 19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571
```

## Resultado estatístico reproduzido

A auditoria reproduziu os endpoints dos 14 pares:

- Head horizontal: Touch `0,0155291`, relay `0,0096671`, estimativa pareada
  `-0,00458741`, CI95 `[-0,0126739, -0,00242216]`;
- Primary horizontal: estimativa `0,00000076`, CI incluindo zero;
- subject horizontal: estimativa `-0,00000039`, CI incluindo zero;
- relay apresentou menor deslocamento horizontal da Head em 11/14 pares;
- três pares (1, 3 e 4) tiveram o sentido oposto, portanto o efeito não é uma
  regra determinística por segmento.

Isso confirma uma diferença **route-conditioned nesta sessão**, não uma
equivalência relay↔PC e ainda não uma causa de O BURACO™.

## Decomposição matemática exata

Para cada frame `i`, a V614 registrou a projeção antes (`xᵢ⁻`) e depois (`xᵢ⁺`)
de `Controller.Update`. Em qualquer segmento consecutivo:

```text
Δx endpoint
= Σ(xᵢ⁺ − xᵢ⁻)                    [C: transformação dentro do camera update]
 + Σ(xᵢ₊₁⁻ − xᵢ⁺)                 [R: mudança entre frames]
```

A identidade foi verificada para Head, PrimaryPart e subject em todos os 28
segmentos pareados:

```text
max arithmetic residual = 0
camera yaw boundary gap max = 0°
camera pitch boundary gap max = 0°
PrimaryPart inter-frame horizontal term = 0 nas duas rotas
subject inter-frame horizontal term = 0 nas duas rotas
```

Logo, nos limites entre frames usados nesta decomposição, o estado angular da
câmera é contínuo e PrimaryPart/subject não se deslocam horizontalmente. O termo
inter-frame não é uma transformação escondida observada da câmera: ele fica
concentrado na geometria relativa da Head, incluindo sua mudança de profundidade.

## O cancelamento encontrado

Valores abaixo são médias absolutas normalizadas por yaw aplicado, exceto onde
indicado:

| Medida | Touch | Relay |
|---|---:|---:|
| Duração do segmento | 77,384 ms | 180,885 ms |
| Frames por segmento | 4,643 | 10,857 |
| Yaw rate | 919,198°/s | 364,902°/s |
| `|C|/yaw`, Head dentro do update | 0,078520 px/° | 0,104357 px/° |
| `|R|/yaw`, Head entre frames | 0,062991 px/° | 0,102823 px/° |
| Sobreposição efetivamente cancelada | 0,062991 px/° | 0,098757 px/° |
| Endpoint Head horizontal | 0,015529 px/° | 0,009667 px/° |
| Head↔subject net 3D | 0,113680 studs | 0,190493 studs |
| Head↔subject path 3D | 0,117046 studs | 0,203935 studs |
| `|Δdepth Head|` | 0,017857 studs | 0,051689 studs |

`C` e `R` tiveram sinais opostos em 14/14 segmentos Touch e 13/14 relay. A
Head relativa ao rig se projetou contra a direção produzida pelo camera update.
O relay teve maior cancelamento em 9/14 pares; entre os 11 pares nos quais a
Head relay terminou mais estável, 8 também tiveram maior cancelamento relay e 9
tiveram maior mudança 3D Head↔rig.

Isto resolve a aparente contradição agregada: **maior mudança 3D da Head pode
produzir menor deslocamento horizontal final quando sua projeção cancela o
deslocamento provocado durante a rotação da câmera**.

## Revisão par a par

`ΔHead H` é relay menos Touch. `C` é o termo dentro do update; `R` é o termo
inter-frame Head-relative. `cancel` é a sobreposição removida entre termos de
sinais opostos. Todos os termos horizontais estão em px/°.

| Par | ΔHead H R−T | ms T/R | rig net T/R | C T/R | R T/R | cancel T/R | gap yaw inicial |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | +0,010643 | 66,6/149,5 | 0,070/0,265 | -0,055/-0,166 | +0,041/+0,141 | 0,041/0,141 | 43,9° |
| 2 | -0,004798 | 116,9/216,8 | 0,094/0,259 | +0,061/+0,134 | -0,051/-0,138 | 0,051/0,134 | 177,3° |
| 3 | +0,001112 | 83,3/133,2 | 0,101/0,022 | -0,064/+0,005 | +0,057/-0,013 | 0,057/0,005 | 123,5° |
| 4 | +0,012364 | 83,2/183,7 | 0,096/0,105 | +0,062/-0,013 | -0,051/-0,010 | 0,051/0,000 | 104,3° |
| 5 | -0,003749 | 100,2/166,3 | 0,132/0,070 | -0,084/-0,015 | +0,072/+0,022 | 0,072/0,015 | 111,7° |
| 6 | -0,002422 | 101,5/167,2 | 0,159/0,168 | +0,102/+0,091 | -0,093/-0,098 | 0,093/0,091 | 7,8° |
| 7 | -0,004377 | 82,9/148,7 | 0,109/0,225 | +0,073/+0,124 | -0,061/-0,131 | 0,061/0,124 | 126,2° |
| 8 | -0,003008 | 117,3/134,2 | 0,091/0,230 | +0,059/+0,126 | -0,049/-0,132 | 0,049/0,126 | 67,3° |
| 9 | -0,010197 | 65,3/183,3 | 0,212/0,197 | +0,129/+0,108 | -0,114/-0,113 | 0,114/0,108 | 77,6° |
| 10 | -0,021410 | 49,8/233,4 | 0,140/0,185 | -0,103/-0,114 | +0,071/+0,104 | 0,071/0,104 | 146,7° |
| 11 | -0,024587 | 50,2/166,7 | 0,110/0,176 | -0,100/-0,120 | +0,064/+0,109 | 0,064/0,109 | 137,0° |
| 12 | -0,012674 | 49,9/183,2 | 0,102/0,207 | +0,076/+0,123 | -0,060/-0,119 | 0,060/0,119 | 2,0° |
| 13 | -0,006322 | 49,4/217,5 | 0,067/0,384 | -0,058/-0,225 | +0,038/+0,212 | 0,038/0,212 | 43,1° |
| 14 | -0,012645 | 66,8/248,8 | 0,109/0,175 | +0,075/+0,099 | -0,059/-0,097 | 0,059/0,097 | 156,1° |

## O que cada hipótese suporta

### Geometria/pose do rig

É suportado que o endpoint da Head resulta da geometria relativa Head↔rig. O
termo inter-frame é nulo para PrimaryPart e subject, mas não para Head, e explica
aritmeticamente o cancelamento sem residual.

O relatório não registrou `PrimaryPart.CFrame`/orientação, `Head.CFrame` relativo
ao PrimaryPart, `Neck.Transform`, `Waist/RootJoint.Transform` nem tracks do
Animator. Assim, não é possível separar:

- rotação do rig inteiro acompanhando a câmera;
- pose local do pescoço/torso;
- animação;
- combinação dessas fontes.

A conclusão correta é **relative Head/rig geometry**, não “animação provada”.

### Profundidade/projeção

Relay teve maior `|Δdepth Head|` em 13/14 pares. Entretanto:

- profundidade inicial média foi `6,12772` Touch e `6,17778` relay;
- a associação descritiva entre Head horizontal e `|Δdepth|` nos 28 segmentos
  foi fraca (`r=-0,124`);
- a diferença horizontal é muito maior que a pequena diferença de profundidade
  basal;
- o relatório não contém o `Camera.CFrame` completo por frame necessário para
  uma projeção contrafactual com a pose congelada.

Profundidade participa do termo Head-relative já medido, mas não foi demonstrada
como explicação suficiente ou independente.

### Estrutura temporal

Esta é a primeira divergência funcional concreta antes do endpoint geométrico:

- relay durou mais em 14/14 pares;
- relay usou em média 10,857 frames contra 4,643;
- relay teve maior mudança líquida Head↔rig em 11/14;
- relay teve maior `|Δdepth|` em 13/14;
- duração e Head horizontal tiveram associação descritiva `r=-0,515` nos 28
  segmentos.

O mesmo yaw acumulado foi observado durante janelas temporais muito diferentes.
Isso expôs o relay a mais evolução do rig entre updates e aumentou a oportunidade
de cancelamento. É uma explicação forte para a dissociação observada, mas ainda
um confundidor route-conditioned: a V614 não pareou duração, número de frames,
fase inicial do rig ou estado de animação.

### Estado inicial não pareado

Os calipers originais parearam yaw total/direção e pitch, corretamente para o
objetivo da V614, mas não parearam a fase geométrica inicial:

```text
camera yaw inicial gap: mean 94,602°, median 108,001°
Head-relative start-pose gap: mean 0,234810, median 0,274516 studs
Head screen-offset gap: mean 1,174181, median 0,895096 px
```

Somente os pares 6 e 12 tiveram gap inicial de camera yaw menor que 10°. Ambos
apontaram Head relay menor, mas duas unidades e poses ainda diferentes não
isolam causalidade. O CI da Head permanece válido como efeito pareado do desenho
executado, porém não transforma esse efeito em mecanismo nativo de input.

## Menor observação adicional necessária

Não é necessário abrir outro subsistema. Para distinguir as explicações dentro
da mesma fronteira geométrica, a menor extensão read-only seria registrar, nos
mesmos timestamps antes/depois de `Controller.Update`:

1. `Camera.CFrame` completo e FOV/viewport usados na projeção;
2. `PrimaryPart.CFrame:ToObjectSpace(Head.CFrame)`;
3. `Neck.Transform` e, quando existirem, `Waist.Transform`/`RootJoint.Transform`;
4. IDs, `TimePosition`, `WeightCurrent` e `Speed` dos tracks ativos do Animator.

Os itens 1–2 permitem reprojetar quatro contrafactuais: câmera móvel/pose fixa,
câmera fixa/pose móvel, ambos móveis e ambos fixos. Os itens 3–4 somente são
necessários para nomear a fonte como animação em vez de relative Head/rig
geometry. Nenhuma propriedade precisa ser escrita.

## Decisão

```text
headHorizontalEffectReplicated = true: all 14 audited pairs reproduce the V614 endpoint effect; this is audit reproduction, not an independent runtime replication
headEffectExplainedByRigPose = supported at relative Head/rig geometry level; root orientation vs local pose vs animation remains unproved
headEffectExplainedByProjectionDepth = partial contribution observed; sufficient/independent explanation unproved
headEffectExplainedByTemporalStructure = strongly supported as a route-conditioned acquisition confound; causal sufficiency unproved
unexplainedGeometricResidual = 0 for the measured screen-space identity; causal attribution residual remains unproved
firstConcreteGeometricDivergence = relay spans more frames/time for matched yaw, exposing a larger inter-frame Head-relative projection term that usually opposes the within-update camera term
causalMechanismProved = false
implementationTargetIdentified = false
v615Justified = false
astra6MaxJustified = false
```

Não existe base para implementar screen lock, alterar gain, prender Head ou
reproduzir o cancelamento. A V614 encontrou um endereço geométrico mensurável,
mas ainda não identificou a causa nativa que deveria ser reutilizada.
