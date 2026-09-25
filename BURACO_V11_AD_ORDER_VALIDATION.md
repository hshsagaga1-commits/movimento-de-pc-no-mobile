# Buraco Legacy — validação da correção de ordem A/D

Base remota antes desta publicação equivalente: `97f5016ce6c885935fae8a5f0a11bf27ab721b5c`.

## Escopo

Esta revisão mantém a câmera funcional da V1.1 intacta e limita a alteração ao agendamento do bridge de teclado:

- refresh contínuo de W/A/S/D: `RenderPriority.Input - 1` (99);
- leitura normal do ControlModule: `RenderPriority.Input` (100);
- serviço do buffer de pulo: permanece em `RenderPriority.Input + 8` (108).

Não há alteração de gain, chord, latch, tempos de pulo, `Camera.CFrame`, `Camera.Focus`, `RootPart.CFrame`, MouseBehavior, RotationType, FOV, zoom ou mouse-lock offset.

## Limite importante

O helper preservado `PCKeyboardControllerWakeV5.lua` também roda em `Input-1`. Roblox não fornece, neste material, uma ordem estável demonstrada entre dois callbacks distintos registrados com a mesma prioridade. Portanto:

- está corrigido o descompasso comprovado `Input+8 -> Input` da emissão contínua de W/A/S/D;
- não está provado que o callback de wake sempre execute antes do callback de refresh quando ambos caem em `Input-1`;
- isso é um limite de ordenação interna, não justificativa para alterar câmera ou personagem.

## Buraco

A causa da separação visual do Buraco durante emote continua **não provada**. Esta correção é apenas para a ordem de A/D e não deve ser apresentada como correção do acoplamento Buraco↔personagem.

A V1.1 original e os checkpoints V20, V500 e V604 não são modificados por esta sequência.
