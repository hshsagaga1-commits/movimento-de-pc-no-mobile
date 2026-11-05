# PC Movement V3.2 adaptativo

Candidata derivada da V3.1 preservada em `62269b83bb05f3fd5eca76f5eeb7102555afc241`. O pacote incorpora o caminho de teclado e câmera da V3.1 que realmente era baixado de `classic-wasd-experiment` em `3a50d72`. O cursor e o alcance visual partem da correção posterior `a48741c`. A V3.2 anterior de 02/11 foi consultada como histórico de Assist.

## Instalação no Delta

Remova o AutoExecute antigo de **movimento** e use uma destas formas.

- Salve [`PC_Movement_V32.lua`](https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v32-adaptive-20261105/PC_Movement_V32.lua) na pasta AutoExecute.
- Ou use a linha abaixo como o único AutoExecute de movimento.

```lua
assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v32-adaptive-20261105/PC_Movement_V32.lua", true)))()
```

O arquivo contém os módulos de código completos. Pode manter o AutoExecute do macro separado. Se executar a V3.2 novamente, ela retorna a sessão ativa. Para parar e liberar teclas, toques, conexões e UI, execute `getgenv().PCMovementV32.Stop()`. Para iniciar depois de parar, execute novamente o loader. `getgenv().PCMovementV32.GetState()` mostra a origem do estado de postura, o acorde ativo e o resultado da seleção do controlador em `pcLock`.

## Joystick

| Região | Em pé | Agachado ou emote |
| --- | --- | --- |
| Frente | W | W no eixo. W+A+D no setor frontal estreito herdado |
| Lado e diagonal frontal esquerda | W+A | A |
| Lado e diagonal frontal direita | W+D | D |
| Trás | S | S |
| Diagonais traseiras | A+S / S+D | A+S / S+D |

O setor lateral direto preserva a ordem de pressionar a nova tecla antes de soltar a antiga. No arco frontal, a passagem rápida esquerda/direita tem a etapa sobreposta `W+A+D` em pé e `A+D` no modo baixo, sem adicionar W durante a troca nesse modo. Um novo alvo ou uma mudança de postura cancela a etapa antiga. O raio lógico, os setores originais e o rastreamento livre do dedo continuam sendo a base. O centro da bolinha alcança a borda visual.

A postura vem de flags explícitas no personagem ou Humanoid, do `ControlsGui/PCFrame/Stand` documentado no probe do Legacy, de animações com nome identificável e, para agachar, do evento nativo de entrada `PlayerScripts.Events.KeybindUsed` registrado no histórico. A leitura do evento aceita apenas `Crouch` com valor booleano. Flags explícitas têm prioridade sobre os fallbacks. Sem evidência, a V3.2 usa o modo em pé. Animações genéricas, sem flag ou nome reconhecível, podem deixar um emote nesse modo. O detector ignora critérios genéricos como prioridade, duração e loop da animação.

## Desempenho e ciclo de vida

- O cálculo dos setores roda em mudanças de toque ou postura e no vencimento da tolerância central. Um acorde já aplicado dispensa reprocessamento de teclas. A bolinha só recebe novas posições durante movimento ou enquanto a suavização converge.
- O pulso Space de 200 ms continua com o mesmo par soltar/pressionar imediato e por Heartbeat durante a janela. Uma conexão atende todos os toques sucessivos dentro da janela. Não há coroutine por pulo.
- A interface é montada uma vez por sessão. Se um controle for removido, a V3.2 solta suas teclas imediatamente e agenda a recuperação do overlay, sem reinstalar câmera ou controlador. Conexões, hooks próprios, captura e tarefas de recuperação são encerrados no Stop.
- O bootstrap espera PlayerGui e PlayerModule de forma limitada e pode ser cancelado. Mantém o bloqueio do controlador de teclado e devolve a identidade móvel ao HUD depois da descoberta. Os hooks temporários de capacidade são retirados nesse ponto. O status oculto não é reescrito a cada quadro.
- O Assist leve mantém a orientação e o orçamento da V3.1, com intervalo mínimo de 50 ms por amostra e até 40 raios. Lê o bridge sem criar uma tabela por quadro e reaproveita a classificação de uma mesma peça dentro de cada amostra. A variante leve não escreve velocidade. O modo histórico de Assist ainda está disponível com `getgenv().PCMovementV32.SetAssistMode("original")`, e `"light"` restaura o padrão.

## Resultados verificáveis

```sh
LUAU_BIN=/caminho/luau LUAU_COMPILE=/caminho/luau-compile python3 tools/check_v32.py --bench
LUAU_BIN=/caminho/luau LUAU_COMPILE=/caminho/luau-compile python3 tools/check_v31_preserved.py
```

Quatro programas Luau da V3.2 e cinco da V3.1 passaram. A validação reproduz o arquivo completo com o gerador, compila o caminho carregado e confere os 125 arquivos da base preservada. Os testes incluem setores, transições, reversão de direção, pulo durante viradas, captura independente da câmera, 40 reexecuções e 20 ciclos Stop/início, respawn com componentes atrasados, cancelamento do seed do teclado, reparo durante gesto e limpeza de conexões. Os casos de macro usam entrada e hooks simulados.

| Cenário | V3.1 | V3.2 | Avaliações de setor V3.1 → V3.2 |
| --- | ---: | ---: | ---: |
| Sem toque | 61,51 ms | 48,99 ms | 12.000 → 0 |
| Dedo parado na lateral | 194,56 ms | 165,91 ms | 12.001 → 1 |
| Viradas, pulos e grade | 977,63 ms | 503,01 ms | 24.001 → 12.001 |

No teste de viradas, as duas versões emitiram 10.075 pulsos de pulo e fizeram 3.403 amostras, 110.598 raycasts e 1.702 consultas de sobreposição. As escritas de posição da bolinha com o dedo parado passaram de 12.002 para 1.

O benchmark roda o bridge, o visual e o Assist leve em Luau oficial (`e3275c2`), com serviços Roblox simulados. Cada cenário executa 12.000 quadros por versão, sete vezes, alternando a ordem. Os tempos são medianas no computador, em milissegundos acumulados. O cenário com grade reproduz consultas a peças simuladas. Renderização, executor, física de contato, GPU e shaders ficam fora dessa medição.

## Verificação física no iPhone 11

Teste a V3.1 e a V3.2 no mesmo mapa e na mesma área, com o mesmo modo gráfico e em condições térmicas parecidas. Em cada versão, faça viradas rápidas com e sem pulo, longe e perto das grades. Compare com shaders desligados e ligados, mantendo o restante igual. Registre FPS e, se disponível, tempo de quadro. Confira também agachamento e emotes com o macro ativo, a câmera com outro dedo, o BHOP, o respawn e MEMEDASH.

Para a captura de diagnóstico, defina `getgenv().PCMovementV32Config={Profile=true}` antes de carregar. Quando disponíveis, as marcas do MicroProfiler aparecem como `PC Movement V3.2 / Joystick` e `PC Movement V3.2 / Assist scan`. `SetDiagnostics(true)` e `ExportDiagnostics()` registram a sequência de contatos e o estado do bridge sem alterar a física do Assist leve.

O macro externo fornecido está ofuscado. A cópia analisada foi lida estaticamente e não é incluída no pacote. O bridge de toque emite W/A/S/D e Space. LeftControl só é usado no fallback de seleção de teclado que já existia na V3.1. As comparações disponíveis verificam que nenhum clique, atalho de emote ou chamada ao macro foi introduzido. O funcionamento do macro real, a cobertura de animações sem rótulo, a velocidade lateral, a física, os shaders e a queda de 20 FPS ainda precisam de execução no aparelho.

[Desempenho no Roblox](https://create.roblox.com/docs/performance-optimization/improve) · [RunService](https://create.roblox.com/docs/reference/engine/classes/RunService) · [UserInputService](https://create.roblox.com/docs/reference/engine/classes/UserInputService) · [Scheduler](https://create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler) · [Teste no aparelho](https://create.roblox.com/docs/performance-optimization/test-on-hardware)
