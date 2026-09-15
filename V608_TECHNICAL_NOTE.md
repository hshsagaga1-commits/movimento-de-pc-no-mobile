# V608 — Lock-State Writer Trace

## Escopo único

A V608 continua diretamente da discrepância observada entre os relatórios:

| Estado final | V606 | V607 |
|---|---:|---:|
| `inMouseLockedMode` | `true` | `false` |
| `GetIsMouseLocked()` | `true` | `false` |
| `mouseLockOffset` | `(2, 0.5, 0)` | `(0, 0, 0)` |

Ela não volta a investigar ownership, relay, composição downstream, yaw,
MouseLockController ou sensibilidade. A única pergunta é qual código escreveu
esses estados e em qual ordem relativa a `CameraModule.Update`.

## Auditoria estática já fechada

Há dois writers ativos possíveis na arquitetura preservada.

### 1. V500 no `Camera-2`

`PCMovementV500_ScrapFusion.lua` instala
`__PCMovementV500CameraOnlyPre` em `RenderPriority.Camera - 2`.

No estado normal, ela chama:

```lua
controller:SetIsMouseLocked(true)
controller:SetMouseLockOffset(Vector3.new(2, 0.5, 0))
```

O offset pode ser zero durante emote. Quando `shouldRelease()` abre, a V500
chama explicitamente:

```lua
controller:SetIsMouseLocked(false)
controller:SetMouseLockOffset(Vector3.zero)
```

Os motivos de release são: `PCMovementEnabled == false`, camera-only lock da
V500 desabilitado, Humanoid ausente/morto, `PlatformStand`, `Physics`,
`Ragdoll` ou `FallingDown`.

### 2. Bloco custom do Evade dentro de `CameraModule.Update`

A função já identificada contém conjuntamente:

```text
PlayerScripts | ShiftLockEnabled | Character | PrimaryPart | ToOrientation |
CFrame | math | abs | SetIsMouseLocked
```

Esse bloco chama `SetIsMouseLocked(ShiftLockEnabled.Value)`. Sua assinatura não
contém `SetMouseLockOffset`; portanto ele pode sobrescrever o booleano de lock,
mas não explica sozinho a mudança do offset para zero.

### Writers excluídos

- V606 apenas instalava wrappers observacionais e encaminhava os argumentos.
- V607 não chamava nenhum dos quatro métodos investigados.
- V500 desregistra `__PCMovementV20NativeHardCenter` e
  `__PCMovementPersistentLock`; assim, esses dois writers antigos não ficam
  ativos ao lado do callback `Camera-2` da V500.
- V604 não escreve lock/offset.

## Lacuna do relatório V606

A V606 contou chamadas à função herdada de BaseCamera, mas não registrou se
`self` era o `activeCameraController` no momento da chamada. Seu relatório
terminou com `lastOutsideOffsetArg = (0,0,0)` e, ao mesmo tempo,
`lastGetOffsetReturn = (2,0.5,0)`. Sem identidade de `self`, caller stack e
ordem global, esses dados não bastavam para atribuir a transição.

A V608 corrige somente essa lacuna.

## Instrumentação runtime

A lista de hooks é fechada:

- `CameraModule.Update`;
- `BaseCamera.SetIsMouseLocked`;
- `BaseCamera.SetMouseLockOffset`;
- `BaseCamera.GetIsMouseLocked`;
- `BaseCamera.GetMouseLockOffset`.

Para cada chamada existente, o relatório registra:

- serial global do evento e frame;
- antes de ou dentro de `CameraModule.Update`;
- `checkcaller()` (`game`, `executor` ou indisponível);
- `getcallingscript()` e stack de `debug.info`, quando o Delta expõe ambos;
- `self == activeCameraController`;
- argumento/retorno e estado antes/depois;
- `ShiftLockEnabled.Value`;
- estado do Humanoid e motivo read-only equivalente a `V500.shouldRelease()`.

As sequências por frame devem distinguir, por exemplo:

```text
V500 SetIs -> V500 SetOffset -> CameraModule.Update enter
    -> GetIs -> GetOffset -> Evade SetIs -> CameraModule.Update exit
```

O relatório só marca `v500RuntimeWriterProven = true` quando as chamadas:

1. vêm do executor, fora do Update;
2. usam o controller ativo;
3. aparecem na cadência anterior ao Update;
4. concordam com o estado normal/release observado.

`customCameraUpdateWriterProven` exige chamadas do jogo dentro do Update, no
controller ativo, com argumento igual a `ShiftLockEnabled.Value` e zero
divergências.

## Como interpretar o resultado

- Se `discrepancyConclusion` apontar `V500 CAMERA_PRE_BIND release branch`, a
  origem de `false + zero` foi provada junto com o motivo exato.
- Se o último lock vier do bloco custom com `ShiftLockEnabled=false`, mas o
  último offset vier da V500, o relatório separará os dois writers.
- Se o estado final mudar sem uma chamada observada no controller ativo, a V608
  não inventará autoria: reportará write direto, estado anterior à coleta ou
  origem ainda não observada.
- Se o teste terminar em `true + (2,0.5,0)`, a discrepância V607 não foi
  reproduzida naquela sessão; a rota normal ainda pode ser provada sem mudar
  estado algum.

## Teste mobile em uma única sessão

Não saia do Roblox até copiar o relatório.

1. Execute `Loader.lua` uma vez.
2. Faça joystick + câmera simultaneamente para manter a validação da V604.
3. Ligue **RELAY V604**. Se for recusado, repita o gesto simultâneo.
4. Toque em **INICIAR**.
5. Jogue normalmente por aproximadamente 15 segundos.
6. Se for possível sem interromper a sessão, inclua uma transição real de
   queda/downed/respawn; isso testa o branch de release, mas não é obrigatório.
7. Toque em **PARAR**.
8. Toque em **COPIAR REPORT COMPLETO**.
9. Só saia quando aparecer `REPORT COPIADO. Agora pode sair e colar.`

**EMERGÊNCIA • RELAY OFF / V500** para a coleta e desliga apenas o relay V604.
Não existe Phase 2 nem experimento de mutação na V608.

## Segurança

A V608 não chama setters/getters para simular estado e não chama
`UpdateMouseBehavior`. Ela não força `PreferredInput`, `MouseBehavior` ou
`RotationType`; não escreve `Camera.CFrame` ou `HumanoidRootPart.CFrame`; não
altera `AutoRotate`, sensibilidade, ganho, WalkSpeed ou física; e não cria
input sintético, `firesignal` ou VirtualInput.

Todos os hooks encaminham a chamada original e são restaurados antes do cleanup
da V604/V500. O relay/ownership V604 e o fail-open V500 permanecem intactos.

`PCMovementV20_STABLE.lua` deve permanecer byte-identical com SHA-256:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
