# PC Movement Rebuild — Evade no iOS

Reconstrução do motor de entradas, em branch separada da V3.1. O arquivo de uso é **`PC_Movement_Rebuild_AUTOEXECUTE.lua`**. Ele contém os seis módulos e não baixa nenhum script durante a execução.

## Usar no Delta

1. Retire o AutoExecute antigo de movimento/Assist dessa pasta. Deixe apenas uma versão ativa.
2. Coloque `PC_Movement_Rebuild_AUTOEXECUTE.lua` no AutoExecute e entre no Evade. Para migrar uma sessão já aberta, execute esse arquivo uma vez.
3. Use o mesmo joystick e PCJump. Segurar PCJump mantém a intenção de BHOP; o motor pede outro pulo nativo no pouso. Soltar o botão encerra essa intenção, preservando apenas o buffer curto do toque.

`PCMovementRebuildLoader.lua` é uma alternativa pequena que baixa somente o arquivo completo desta branch. Use **um dos dois**, nunca os dois juntos. A versão completa é a entrega principal e funciona sem depender do GitHub no momento da execução.

## Comportamento implementado

- Em pé no chão: W+A, W, W+D ou S. Lateral puro do joystick corresponde à diagonal com W; a região traseira corresponde a S.
- Agachado, em movimento aéreo, emote identificado ou contato físico com grade: somente A/D. Levar o joystick para frente nesses estados não injeta W.
- Todo movimento aéreo usa a política lateral, inclusive com animação em pé. A classificação de BHOP/inversão é observacional e não muda a física do jogo.
- A/D troca no próprio evento de toque, sem fila de combinações intermediárias e sem espera entre comandos. Os eventos individuais de teclado não são uma transação atômica da engine; o lote não mantém uma combinação intermediária por um frame.
- Não há escrita em velocidade, impulso, CFrame, WalkSpeed, JumpPower, HipHeight, colisão ou orientação do personagem. A velocidade resultante continua sendo decidida pelo jogo.
- Um único gerenciador controla W/A/S/D/Space. A seleção do Keyboard de PlayerModule preserva os controles globais desabilitados pelo jogo. A compatibilidade de hooks e input sintético com o Delta precisa de teste no aparelho.

## Interface e câmera

Os nomes `PCKeyboardTouchBridgeV52Overlay`, `PCJoystick`, `Knob` e `PCJump`, os sprites Roblox e as fórmulas de layout pequeno/grande foram mantidos. A suavização de 40 ms movimenta somente a imagem do knob; as teclas recebem a posição bruta imediatamente.

A recarga da reconstrução mantém as mesmas instâncias de UI, tamanhos, posições e atributos. Ao migrar a V3.1, o motor copia a apresentação antes de chamar o Stop antigo, que a destrói. Isso preserva propriedades e atributos, inclusive ajustes externos de posição/tamanho/bloqueio. Conexões Lua instaladas por editores externos não são copiáveis pelo `Clone`; esses editores precisam acompanhar a recriação da UI, como nos resets anteriores. A branch original não contém um botão próprio de bloqueio de posição: o bloqueio do modo PC continua disponível por `PCModeLock.SetEnabled`.

Cada dedo capturado fica separado da câmera por identidade durante seu ciclo completo. Outro dedo continua disponível para a câmera, inclusive ao atravessar a metade da tela. A câmera, sua sensibilidade e seu CFrame não são modificados.

## Grades e pequeno salto

O sensor amplia a descoberta local, sem aumentar o corpo nem criar colisores. Ele diferencia proximidade de contato real obtido das peças colidíveis do personagem e respeita os grupos de colisão. Chão largo, parede sem evidência de grade, decoração não colidível, outro personagem, MeshPart anônimo e Truss genérico não são tratados como grade.

Nomes/tags específicos e fileiras de pelo menos três barras paralelas e alinhadas fornecem evidência. A geometria continua sendo uma heurística: não existe no repositório uma API oficial que identifique todas as grades do Evade. Peças anônimas podem deixar de ser detectadas; inferência geométrica pode ser desligada na configuração. Não foi afirmado que todos os mapas foram reconhecidos.

O Assist não puxa, não projeta a velocidade contra a grade e não trava a saída. No momento de um pulo buffered, consulta novamente o contato físico. O salto é um pedido normal de Space, com intenção do jogador, personagem no chão, cooldown e um pedido por pouso. Contato/proximidade no ar não fabrica um segundo salto.

**O micro-hop do vídeo não está validado.** O vídeo não informa de onde vem seu impulso vertical. Um pedido nativo de pulo não garante a mesma altura curta. Não há uma implementação substituta que force essa altura; confirmar e reproduzir a mecânica exata requer instrumentação no Roblox.

## Estados específicos do Evade

A observação física usa FloorMaterial, estado do Humanoid, saúde, ancoragem e velocidade lida. Para agachamento/emote no chão, tenta booleanos explícitos em atributos/BoolValues, e a convenção histórica `ControlsGui/PCFrame/Stand.Visible` para agachamento. Essa convenção e os nomes possíveis de atributos precisam ser confirmados na versão do jogo. Animação de corpo, HipHeight e velocidade não são usadas para inventar um emote/agachamento.

Quando não há sinal, o diagnóstico indica `unknown`. A movimentação aérea continua lateral mesmo com esses sinais desconhecidos. Um provedor permite integrar um sinal confirmado sem reescrever o motor:

```lua
getgenv().PCMovementRebuild.SetStateProvider(function(context)
    -- Retorne somente booleanos provenientes de um estado real confirmado.
    return {crouched = context.character:GetAttribute("Crouching")}
end)
```

## Configuração e diagnóstico opcional

Antes do arquivo principal, se necessário:

```lua
getgenv().PCMovementRebuildConfig = {
    SwapAD = false, -- true troca as teclas produzidas por esquerda/direita
    Diagnostics = false,
    ContactJump = true, -- identifica o buffer nativo em contato; nunca força impulso
    AllowInferredGrids = true,
    UseLegacyStandIndicator = true,
    -- EmoteAnimationIds = {"ID_EXATO_CONFIRMADO"},
    -- GridTags = {"Fence", "Railing", "Grid"},
}
```

Durante a sessão:

```lua
local pc = getgenv().PCMovementRebuild
pc.SetDiagnostics(true)
-- Reproduza a perda de velocidade ou o contato por alguns segundos.
local ok, caminho, texto = pc.ExportDiagnostics() -- PCMovementRebuild_Log.json
print(ok, caminho)
```

Os logs ficam desligados por padrão. Ativos, guardam até 180 eventos em memória, com amostras a 10 Hz, mudanças de teclas/estado, velocidades lidas, fontes dos estados, evidência de grade, pedidos de Space e quedas de velocidade. `ExportDiagnostics` tenta gravar pelo `writefile` do Delta e devolve o JSON se essa função não estiver disponível. `Probe()` retorna os sinais e IDs de animação observados para confirmar a integração do jogo.

Os logs distinguem falhas do nosso transporte/rota de uma desaceleração sem causa atribuída. **Não conseguem apontar com certeza qual script externo mudou a velocidade.** Pedir Space também não prova que o jogo aceitou o salto. O código registra essa aceitação como não confirmada.

Outros comandos: `pc.GetState()`, `pc.GetLogs()`, `pc.SetSwapAD(true)`, `pc.SetEnabled(false)` e `pc.Stop()`. O alias `getgenv().PCModeLock.SetEnabled(...)` foi mantido.

## Verificação executada e limites

`LUAU_COMPILE=/caminho/luau-compile python3 tools/check_rebuild.py` verifica o bundle determinístico, executa todos os testes offline, procura escritores de física/dependências HTTP e compara os 112 arquivos históricos com o commit `ce4eb8b`. O compilador Luau valida os seis módulos, o bundle e o loader.

Os testes exercitam as funções de produção, tanto em Lua quanto na CLI Luau quando ela acompanha o compilador. Os serviços e objetos Roblox usados pelos testes de integração são substitutos locais, portanto esses resultados não validam o runtime Roblox, a física de Evade, o sistema de input do Delta nem desempenho real no iPhone 11. O benchmark de 100 mil atualizações mede apenas o núcleo no host de desenvolvimento.

Orçamento configurado: descoberta a até 12 Hz/48 peças, contato a até 20 Hz com até oito corpos colidíveis consultados, mais confirmação no momento elegível de pulo. Nenhum raycast por frame, nenhuma busca global do mapa e nenhum loop antigo é carregado. Não equivale a uma medição de FPS/bateria no celular.

O roteiro necessário no aparelho e a análise do vídeo estão em `docs/PC_MOVEMENT_REBUILD_VALIDATION.md`.
