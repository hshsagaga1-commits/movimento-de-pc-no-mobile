# V609 — Custom Evade Camera Block Trace

## Escopo fechado

A V609 não repete V604–V608. Ownership, relay, composição BaseCamera,
MouseLockController e writers de lock/offset são fatos de entrada.

O único alvo é o bloco custom dentro de `CameraModule.Update` identificado no
runtime do Evade pelos símbolos:

```text
PlayerScripts | ShiftLockEnabled | Character | PrimaryPart | ToOrientation |
CFrame | math | abs | SetIsMouseLocked
```

A probe responde somente o que esse bloco lê, chama, persiste e modifica; onde
ele roda em relação a `activeCameraController:Update()`; e se contém uma
diferença funcional Touch versus PC.

## Evidência herdada da V608

Em 2303/2303 frames, o bloco chamou `SetIsMouseLocked` no controller ativo com
argumento exatamente igual a `ShiftLockEnabled.Value`:

- `1801` chamadas com `true`;
- `502` chamadas com `false`;
- `0` divergências de argumento;
- `0` chamadas de `SetMouseLockOffset` dentro do Update.

A ordem observada foi:

```text
V500 Camera-2
  -> CameraModule.Update enter
  -> activeCameraController.Update
  -> BaseCamera GetIsMouseLocked / GetMouseLockOffset quando aplicável
  -> bloco custom SetIsMouseLocked(ShiftLockEnabled.Value)
  -> CameraModule.Update exit
```

A V609 começa diretamente no miolo custom entre a saída do controller e a saída
do módulo.

## Análise estática focada

Não existe scan amplo. A V609 examina apenas:

- constants e upvalues do `CameraModule.Update` já localizado;
- `Controller.Update`, só como fronteira de ordem;
- `Controller.SetIsMouseLocked`, só como ponto observável do bloco;
- a função `accelerate`, somente se encontrada diretamente na tabela já exposta
  como upvalue do `CameraModule.Update`.

Quando o Delta expõe `decompile`, a probe procura cada ocorrência de
`ShiftLockEnabled` no próprio ModuleScript, pontua somente as janelas que também
contêm os símbolos do bloco e escolhe a de maior evidência — dando peso extra a
`SetIsMouseLocked` e ao par `PrimaryPart`/`ToOrientation`. Só essa janela
limitada entra no relatório. Se não houver decompiler, a coleta continua pelos
caminhos runtime abaixo.

Tokens de input encontrados nas constants do `Update` inteiro são reportados
separadamente. `touchVsPCBranchFound` só usa tokens da janela focada; assim, um
token de outra parte da função não é atribuído indevidamente ao bloco custom.

## Fronteiras runtime

Cada frame é medido nestes pontos:

1. entrada de `CameraModule.Update`;
2. entrada e saída de `activeCameraController:Update()`;
3. entrada e saída do `SetIsMouseLocked` custom;
4. saída de `CameraModule.Update`.

Em cada fronteira são lidos, sem alteração:

- `ShiftLockEnabled.Value`;
- `Character.PrimaryPart.CFrame` e sua orientação;
- `CurrentCamera.CFrame` e `Focus`;
- CFrame/Focus retornados pelo controller;
- lock/offset crus do controller;
- `PreferredInput` e último tipo de input.

Isso separa mudanças do controller das mudanças que ocorrem no tail custom.
O relatório conta posição, rotação e yaw do PrimaryPart separadamente e mede se
o CFrame retornado pelo controller já foi aplicado à câmera antes do setter.
Também separa transformações observadas sob `PreferredInput.Touch` e
`PreferredInput.KeyboardAndMouse`, sem alterar nenhum dos dois estados.

## Locais e estado persistente

No momento exato em que o bloco chama `SetIsMouseLocked`, a V609 tenta localizar
o frame `CameraModule.Update` na stack e capturar os locals expostos por
`debug.getstack`/`debug.getlocal`. CFrames, vetores, números, booleanos e
Instances são registrados com tipo e valor; nenhuma variável é escrita.

Os upvalues do `CameraModule.Update` são comparados antes/depois de cada frame.
Isso verifica especificamente os valores já vistos pela V606:

- limites numéricos próximos de `-2π` e `2π`;
- tabela que contém `accelerate`;
- `Vector3` mutável que muda de posição entre execuções.

Se `accelerate` for alcançável diretamente, a função é envolvida de forma
observacional para registrar argumentos, retornos e ordem. A original sempre é
executada com os mesmos argumentos.

## Decisão e experimento

O experimento permanece bloqueado nesta build. A simples presença de
`PrimaryPart`, `ToOrientation` e `CFrame` não prova que existe uma transformação
segura para reutilizar.

`anchorRelevantTransformFound` somente pode ficar true após mudança rotacional
real do PrimaryPart no intervalo posterior ao controller. Mesmo nesse caso,
`experimentEligible` permanece false na V609: locals, condição e estado
persistente ainda precisam explicar completamente a transformação antes de
qualquer reprodução.

As linhas detalhadas são amostradas e limitadas para manter o relatório
copiável no Delta; todos os contadores continuam completos e `traceDropped`
informa quantas linhas excedentes foram omitidas.

O relatório termina obrigatoriamente com:

```text
customEvadeBlockSemantics
customEvadeBlockWrites
customEvadeBlockState
touchVsPCBranchFound
anchorRelevantTransformFound
firstFunctionalDivergence
experimentEligible
```

## Teste mobile em uma única sessão

Não saia do Roblox antes de copiar o relatório.

1. Execute `Loader.lua` uma vez.
2. Faça joystick + câmera simultaneamente para manter a prova V604.
3. Ligue **RELAY V604**. Se for recusado, repita o gesto simultâneo.
4. Toque em **INICIAR**.
5. Gire a câmera parado e depois andando por 20–30 segundos.
6. Inclua naturalmente momentos em que o estado do jogo faça
   `ShiftLockEnabled` alternar entre `true` e `false`, se isso ocorrer.
7. Toque em **PARAR**.
8. Toque em **COPIAR REPORT COMPLETO**.
9. Só saia quando aparecer `REPORT COPIADO. Agora pode sair e colar.`

Ao tocar **PARAR**, todos os hooks da V609 são restaurados imediatamente. O
botão **EMERGÊNCIA** também para a coleta e desliga apenas o relay, deixando a
V500 disponível.

## Segurança

A V609 não chama o bloco custom, não escreve `Camera.CFrame`,
`HumanoidRootPart.CFrame` ou `PrimaryPart.CFrame`, não força `PreferredInput`,
`MouseBehavior`, `RotationType` ou `AutoRotate`, não muda sensibilidade, ganho,
WalkSpeed ou física e não usa input sintético, VirtualInput ou `firesignal`.

V604 e V500 permanecem byte-identical. `PCMovementV20_STABLE.lua` permanece
byte-identical com SHA-256:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
