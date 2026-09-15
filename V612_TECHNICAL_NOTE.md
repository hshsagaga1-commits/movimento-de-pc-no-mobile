# V612 — Paired Standing Screen-Drift Control

## Escopo fechado

A V612 continua diretamente da limitação decisiva da V611. Ela não procura
novo mecanismo e não reabre V604–V611. O único teste é:

```text
FASE A: Touch nativo + personagem parado
FASE B: relay V604 + personagem parado
```

O objetivo é decidir se trocar o pipeline de input causa diferença geométrica
de screen-space quando o movimento world-space do personagem é excluído.
`experimentEligible` permanece `false`; nenhuma correção é implementada.

## Reutilização da prova V604 sem novo joystick

O arquivo `PCMovementV604_MultitouchOwnershipProbe.lua` permanece byte-identical.
Para uma execução nova não exigir outra prova humana joystick+câmera, a V612
aceita explicitamente a prova V604 já validada e altera apenas a inicialização
runtime do booleano/status dessa prova na cópia carregada em memória.

Todo o comportamento por evento continua sendo o da V604:

- joystick é identificado pela identidade real do movement controller;
- câmera é identificada por `fingerTouches[input] == false`;
- conflito continua desabilitando o relay;
- Touch de câmera preserva bookkeeping/pinch;
- `OnMouseMoved` recebe o mesmo `UserInputObject` Touch real;
- V500 continua fail-open.

O relatório expõe `persistedOwnershipProofAccepted` e as duas substituições
exatas de inicialização. Nenhum `UserInputObject` é criado ou simulado.

## Critério de standing

Após selecionar cada fase, a V612 espera `1.50 s` e depois exige 12 frames
consecutivos que satisfaçam simultaneamente:

- `PrimaryPart.AssemblyLinearVelocity.Magnitude <= 0.15` stud/s;
- delta world-space do PrimaryPart entre entradas de `CameraModule.Update`
  `<= max(0.004, dt * 0.15)` stud;
- `Humanoid.MoveDirection.Magnitude <= 0.01`;
- nenhuma identidade de joystick V604 ativa, quando a leitura estiver
  disponível.

Esses valores são somente lidos. Se movimento for detectado durante a coleta,
o frame é rejeitado e a janela entra numa curta reestabilização de `0.35 s`.

Uma amostra válida ainda exige:

- escrita de câmera da rota correta para a fase;
- yaw observado do `CurrentCamera` e yaw retornado pelo controller ambos
  `>= 0.05°`;
- PrimaryPart e Head visíveis nas projeções observada e retornada.

O limite mínimo de yaw evita dividir deslocamento por ruído numérico próximo de
zero. O denominador nunca é delta do dedo: projeção observada usa yaw realmente
observado; projeção do CFrame retornado usa o yaw desse retorno.

## Distribuições e matching

Por fase são registrados:

- frames válidos e rejeitados;
- yaw aplicado e deslocamentos PrimaryPart/Head;
- px por grau observado e contra o CFrame retornado;
- posição do subject e distâncias para PrimaryPart/Head;
- magnitude do mouse-lock world offset;
- residual do Focus;
- mean, median, p95 e max das distribuições aplicáveis.

Os buckets não usam limites escolhidos para favorecer uma hipótese. Depois das
duas fases, a V612 encontra o suporte compartilhado entre os percentis 5% e 95%
das duas distribuições de yaw. Dentro desse intervalo comum, calcula os
percentis combinados 33% e 67% e forma buckets `small`, `medium` e `large`. Um
bucket só entra na decisão com pelo menos 25 amostras de cada fase.

## Regra de decisão

A decisão requer no mínimo:

- 120 amostras standing válidas em cada fase;
- balanço `min(samples)/max(samples) >= 0.65`;
- pelo menos dois buckets de yaw comparáveis.

`supported` exige diferença de medianas de pelo menos 20% em PrimaryPart
observado e retornado, pelo menos 15% em Head observado e retornado, em dois
buckets ou mais e com direção consistente.

`not-supported` exige diferença agregada de no máximo 10% para PrimaryPart,
15% para Head e equivalência em todos os buckets comparáveis.

Qualquer resultado intermediário ou amostragem insuficiente produz `unproved`.
O relay não é interpretado como MouseMovement PC nativo.

## Teste no iPhone + Delta — uma sessão

1. Execute `Loader.lua`.
2. Toque **INICIAR**.
3. Toque **FASE A • TOUCH PARADO**.
4. Não use o joystick. Aguarde o painel mostrar `active`/coleta ativa.
5. Mantendo o personagem parado, gire continuamente a câmera por cerca de 15 s.
6. Toque **FASE B • RELAY PARADO**.
7. Continue sem joystick; aguarde novamente a estabilização terminar.
8. Repita giros semelhantes por cerca de 15 s.
9. Confirme no painel que A e B têm amostras válidas.
10. Toque **PARAR** e depois **COPIAR REPORT COMPLETO**.
11. Só saia do Roblox após `REPORT COPIADO`.

**EMERGÊNCIA** restaura os hooks V612, desliga o relay e deixa V500 ativo.

## Segurança

A V612 não:

- escreve Camera/RootPart/PrimaryPart/Head CFrame ou Focus;
- altera CameraSubject, sensitivity, gain ou física;
- força PreferredInput, MouseBehavior, RotationType ou AutoRotate;
- usa VirtualInput, `firesignal`, input sintético ou `UpdateMouseBehavior`;
- implementa feedback ou correção artificial de screen-space;
- cria V613.

Hashes protegidos esperados:

```text
V20  634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
V500 5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096
V604 19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571
```
