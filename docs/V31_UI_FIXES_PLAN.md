# V3.1: correções visuais isoladas e investigação do macro

Base funcional confirmada pelo usuário: branch feature/pc-movement-v31-preserved-20261101, commit 62269b83bb05f3fd5eca76f5eeb7102555afc241. Novo branch: feature/pc-movement-v31-ui-fixes-20261102.

## Escopo fechado

- [x] Ocultar somente UserInputService.MouseIconEnabled, com limpeza/restauração e reaplicação após alterações do jogo. Não tocar MouseEnabled, TouchEnabled, MouseBehavior, sensibilidade, câmera ou eventos simulados.
- [x] Trocar só o limite visual de setKnobFromPosition pelo raio do círculo renderizado. A fonte primária Roblox/avatar TouchThumbstick usa AbsoluteSize.x/2; este joystick tem círculo quadrado e usa o menor eixo para não ultrapassar um redimensionamento não quadrado. Manter raio lógico, mapeamento, estágios A/D, spring existente de 40ms e pulo de 200ms iguais.
- [x] Direcionar o bootstrap V3.1 existente para a cópia do bridge neste novo branch, sem substituir o mecanismo que o usuário validou. Assist inteiro e todos os bootstraps de teclado/câmera permanecem intactos, exceto pelo endereço necessário em PCModeLockV3.
- [x] Verificar por traços de eventos que o cálculo visual não altera as teclas; testar cursor, respawn, reset de propriedade, reexecução/Stop e falha da carga visual.
- [ ] Publicar apenas o branch novo e entregar o mesmo estilo de loader sem cache.

## Macro: limite conhecido antes de editar

O bridge V3 envia SendKeyEvent de W/A/S/D/Space. Não há SendMouseButtonEvent, Activate, firesignal ou chamada de emote no bridge. Macro externo não está no repositório. Contexto anterior identifica um Macro Circular V3 FAST, mas não retorna código ou URL verificável. O repositório separado FloatingMacroG contém um macro de pontos acionado por G, sem confirmação de que seja o macro ativo. Foi apenas lido, sem alterações.

Correção explícita de escopo do usuário: MEMEDASH foi usado para diagnósticos e não é o alvo. Nenhum arquivo MEMEDASH é alterado, carregado ou integrado ao joystick. A investigação não usa o diagnóstico como substituto do macro real.

Portanto, não interceptar entradas globalmente, não desabilitar cliques, não alterar o macro por nomes adivinhados e não anunciar o conflito como resolvido. Para rastrear o gatilho real é necessário o loader ou .lua do macro usado no aparelho. Possibilidades (tecla interpretada como ativação, toque fora da origem, sobreposição ou clique sintetizado pelo macro) são hipóteses, não diagnóstico confirmado.

O trabalho independente de cursor/knob segue até a entrega concreta. A correção do macro fica explicitamente pendente do código externo se ele não chegar durante esta execução.
