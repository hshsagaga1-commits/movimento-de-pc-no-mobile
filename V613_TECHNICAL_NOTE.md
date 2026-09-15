# V613 — Axis, Pitch, and Relative Rig Geometry

## Escopo fechado

A V613 continua diretamente da V612 e da auditoria pós-V612. Ela não reabre
ownership, mouse-lock, offset/focus, MouseLockController, writers, o bloco
custom do Evade ou a semântica já reconstruída de `rotateInput`.

O único objetivo é explicar a assimetria observada na V612:

```text
PrimaryPart: diferença descritiva forte em yaw medium/large
Head:        diferença horizontal/2D pouco corroborante
```

A V613 continua estritamente observacional e compara duas janelas standing:

```text
FASE A: Touch nativo
FASE B: relay V604 OnMouseMoved(same real Touch UserInputObject)
```

Relay não é chamado de MouseMovement PC nativo.

## Referência visual PC externa

Foi inspecionado o trecho aproximadamente `20.0s–24.0s` do vídeo PC Legacy
fornecido durante a implementação. Nele, rotações fortes mudam drasticamente a
orientação do cenário enquanto uma região próxima da Head/upper torso aparenta
alta estabilidade em screen-space.

Isso é registrado somente como referência qualitativa externa:

- não prova que Head é o pivot;
- não prova equivalência PC;
- não calibra thresholds;
- não entra no decision gate;
- não substitui nenhuma leitura runtime mobile.

Por causa dessa referência, V613 também projeta o `subject` e compara a
estabilidade X/Y/2D de Head, PrimaryPart e subject. O relatório apenas informa
qual ponto mobile apresentou menor deslocamento normalizado; a comparação com
o vídeo continua qualitativa.

## Standing preservado da V612

Cada fase usa exatamente:

- estabilização de `1.50 s`;
- 12 frames standing consecutivos;
- `AssemblyLinearVelocity.Magnitude <= 0.150` stud/s;
- delta world-space do PrimaryPart `<= max(0.004, dt*0.150)` stud;
- `Humanoid.MoveDirection.Magnitude <= 0.010`;
- ausência de identidade V604 de joystick, quando disponível;
- rota de input correspondente à fase;
- yaw observado e retornado `>= 0.050°`;
- PrimaryPart e Head on-screen nas quatro projeções exigidas.

## Medição por frame

Cada amostra aceita mantém no relatório completo:

- yaw e pitch aplicados, assinados e absolutos;
- `rotateInput` na entrada do controller;
- yaw/pitch da câmera antes/depois e do CFrame retornado;
- posições world-space de subject, PrimaryPart e Head;
- vetores subject→PrimaryPart, subject→Head e PrimaryPart→Head;
- mudança do vetor PrimaryPart→Head no frame;
- profundidade da Head relativa à câmera;
- X/Y screen-space antes/depois, deltas assinados e métricas por yaw;
- projeção X/Y equivalente do subject antes/depois;
- projeções observadas e projeções calculadas com o CFrame retornado, sem
  atribuí-lo à câmera.

`relative Head/rig geometry` é o único nome usado para movimento relativo do
rig. A V613 não o chama automaticamente de animação.

## Controle de pitch predefinido

A análise horizontal principal aceita somente frames com:

```text
abs(appliedPitchDeg) <= 0.35°
```

Esse threshold é constante no código e é definido antes da classificação.
As métricas verticais são reportadas tanto por yaw quanto por pitch quando
`abs(pitch) >= 0.05°`; a V613 não usa yaw sozinho para explicar deslocamento
vertical.

## Matching estreito de yaw

Após filtrar pitch, a V613 calcula o suporte compartilhado p05–p95 de
`abs(appliedYawDeg)` e usa bins fixos, ancorados em zero, de `0.50°`.

Um bin só entra na comparação principal quando:

- possui ao menos 20 amostras de cada fase;
- a diferença entre as medianas de yaw Touch/relay é `<= 0.15°`.

A qualidade global requer pelo menos três bins e 120 amostras matched por fase.
O relatório imprime, por fase e por bin, N, yaw mean/median/p05/p95, pitch
absoluto e assinado mean/median, medianas X/Y da PrimaryPart e Head e
diferenças relativas.
`validationReady` só fica verdadeiro quando esse matching global está bom, os
dois bootstraps horizontais puderam ser calculados e não houve erro de callback
ou correlação.

## Incerteza temporal

As métricas horizontais principais usam moving-block bootstrap:

```text
block size = 12 amostras temporalmente ordenadas
iterations = 400
statistic = median(relay) - median(touch)
CI = percentis 2.5% e 97.5%
```

O bootstrap é determinístico e não trata frames consecutivos como observações
independentes. Ele ainda não remove o limite de as fases ocorrerem em ordem
sequencial; essa limitação é impressa no relatório e impede a V613 de declarar
efeito causal conclusivo mesmo quando um intervalo não cruza zero.

As associações entre `Head deltaY`, pitch, delta vertical do vetor do rig e
mudança de profundidade são Pearson descritivas. `abs(r) >= 0.50` é um limiar
predefinido de associação, não um teste de causalidade nem uma alegação de
significância.

## Erros de correlação

A leitura opcional dos diagnósticos V604 usada pelo gate de joystick agora é
isolada por `pcall` e fail-open. `finalizeFrame` registra o estágio, traceback
quando disponível, origem agregada e se o frame falhou antes do commit.

Uma amostra só é marcada como committed depois de todas as leituras exigidas e
da gravação atômica dos campos. A V613 não tenta contornar capabilities do
executor.

## Segurança

A V613 não:

- escreve `Camera.CFrame`, `Camera.Focus`, RootPart, PrimaryPart ou Head CFrame;
- altera CameraSubject, mouse-lock offset, sensitivity, gain ou física;
- força PreferredInput, MouseBehavior, RotationType ou AutoRotate;
- chama `UpdateMouseBehavior`, `firesignal` ou VirtualInput;
- cria `UserInputObject` sintético;
- implementa correção de screen-space;
- cria V614.

V604 ownership/relay e V500 fail-open são reutilizados. V20, V500 e V604
permanecem byte-identical.

## Teste mobile — uma sessão

1. Execute `Loader.lua`.
2. Toque **INICIAR**.
3. Toque **FASE A • TOUCH PARADO**.
4. Não use joystick. Aguarde `active` e gire a câmera por cerca de 20 s,
   tentando fazer movimentos principalmente horizontais, mas sem fabricar
   velocidade específica.
5. Toque **FASE B • RELAY PARADO**.
6. Aguarde novamente `active` e repita por cerca de 20 s.
7. Procure obter pelo menos 120 amostras válidas em cada fase.
8. Toque **PARAR**.
9. Toque **COPIAR REPORT COMPLETO** e só depois saia do Roblox.

O relatório completo inclui dados por frame e pode levar alguns segundos para
ser montado/copied no iPhone.
