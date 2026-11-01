# V3.1 preservada — ajustes separados no Assist

Base: `ce4eb8b`, da branch `feature/pc-movement-assist-v31-contact-hop`. A nova branch é `feature/pc-movement-v31-preserved-20261101`. Ela parte da original, sem utilizar o motor ou os controles da reconstrução anterior.

## Usar

Deixe apenas `PC_Movement_V31_Preserved_AUTOEXECUTE.lua` como AutoExecute de movimento. Esse arquivo pequeno chama `CombinedJoystickAssistV31PreservedLoader.lua` com uma URL única por execução. Os módulos baixados também recebem GUID para evitar cache.

O loader encerra uma reconstrução anterior ainda ativa e chama o **`PCModeLockV3.lua` original**, no snapshot V3.1. Esse bootstrap mantém as mesmas dependências de antes: ramo `classic-wasd-experiment` e bridge do ramo V3. Não há nova seleção de Keyboard, novo hook, novo joystick nem outro sistema de pulo.

Todos os **112 arquivos originais ficam intactos**, incluindo os bootstraps, o bridge, as imagens/crops, dimensões, posicionamento, raio de movimento, teclas, sequências A/D e câmera. A versão original usa raio mínimo de 46 px no toque; o knob pode avançar visualmente além da borda do círculo, como antes. As configurações/editor externo continuam sob o mesmo ciclo de vida da V3.1, inclusive sua recriação original em reset de UI.

## Alteração desta rodada

A única mudança de comportamento está no módulo separado `LegacyGridContactAssistV31Preserved.lua`, derivado do Assist V3.1:

- Mantém `intentFromChord`, `visualFacingIntent` e a orientação suave do personagem da V3.1. O teclado e sua troca A/D não são reprogramados, nem recebem regras aéreas novas.
- Retira a correção horizontal para dentro da grade, a reprojeção da velocidade e os impulsos verticais fabricados pelo Assist antigo. Assim o nosso Assist deixa de frear/puxar o BHOP nos contatos. Isso não garante conservação de velocidade pela física do jogo.
- Procura oportunidades numa área local um pouco maior; diferencia proximidade, histórico de contato e contato atual observado em partes colidíveis do corpo. Respeita grupos de colisão nas consultas.
- Corrige o ramo inalcançável das barras horizontais. Rejeita pisos largos, partes de personagens, Truss genérico, decoração não colidível e MeshPart sem outras evidências. Classificação por nome/material/geometria continua heurística, sem validação em todos os mapas.
- Limita a amostragem a 20 Hz, até 40 raycasts por amostragem; consultas amplas a cada 75 ms, até 48 candidatos e apenas oito verificações por raio. Contato físico confirmado pode dispensar todos os raycasts daquela amostragem. Não é uma medição de desempenho no aparelho.

Fora dessa retirada de interferências do Assist, o BHOP/controle aéreo é o da versão anterior. Não foram inseridos aceleradores, outro mapeamento ou outro proprietário do Space.

## Micro-hop

O pulo de 200 ms do bridge original é mantido. O ajuste não compete com seus pulsos de Space.

O vídeo mostra aproximação/saída de grades e trechos aéreos, mas não informa a origem do pequeno impulso vertical. Nesta etapa, o módulo registra mudanças verticais, contatos físicos e pulsos do pulo antigo para investigar a sequência. **A mecânica exata do micro-hop ainda não foi reproduzida nem validada no Roblox.** Os saltos artificiais do Assist antigo não são descritos como física nativa.

## Voltar somente o Assist ao original

Sem reinstalar joystick/teclado/câmera:

```lua
getgenv().PCMovementAssistV31Preserved.SetAssistMode("original")
```

Para voltar ao ajuste:

```lua
getgenv().PCMovementAssistV31Preserved.SetAssistMode("light")
```

O modo `original` executa o arquivo original intacto, com sua aderência e seus impulsos antigos. Se a carga do ajuste falhar, o loader tenta restaurar esse Assist original. `PCMovementAssistV31` permanece como alias de compatibilidade; `Stop()` encerra a versão e seu observador de recuperação de UI. A instalação é serializada: se uma carga original estiver suspensa em rede/WaitForChild, uma versão seguinte aguarda sua conclusão/limpeza; uma carga cancelada não é adotada como sucesso. A cadência original de recuperação, inclusive a pausa de 250 ms, foi mantida.

## Diagnóstico sem painel

```lua
local pc = getgenv().PCMovementAssistV31Preserved
pc.SetDiagnostics(true)
-- Reproduza o contato/troca de direção por alguns segundos.
local ok, caminho, json = pc.ExportDiagnostics()
print(ok, caminho) -- PCMovement_V31_Preserved_Log.json
```

Desligado por padrão. Até 160 eventos em memória. O arquivo reúne estado do Assist, sinais escalares do bridge/PC lock/wake/câmera, velocidades lidas, evidência de contato e mudanças verticais próximas a grades. Se o Delta não fornecer `writefile`, o terceiro retorno contém o JSON. Nenhum log identifica com certeza a origem de um impulso ou qual outro script alterou a velocidade.

## Verificação

```bash
LUAU_BIN=/caminho/luau LUAU_COMPILE=/caminho/luau-compile python3 tools/check_v31_preserved.py
```

Passaram os testes offline do bridge/visual original, pulo original de 200 ms, sequências A/D, extensão visual do knob, comparação Assist antigo/ajustado, contato versus proximidade, rejeições do sensor, limites de consultas, logs, Stop e reversão do Assist sem reinstalar PC/UI. Testes com corrotinas também cobrem Stop no meio de uma carga de Assist e reexecução durante uma recuperação de PC suspensa. Os testes executam os scripts de produção na CLI Luau com serviços Roblox simulados. Os arquivos do caminho carregado compilam.

Uma checagem exploratória de todos os arquivos históricos também encontrou um erro **preexistente em `LegacyProbeV2.lua:225`**. Esse probe não pertence ao caminho carregado e foi deixado intacto. O verificador compila os módulos usados nesta entrega e compara todos os originais byte a byte.

**Pendente no aparelho:** confirmar que a rota PC continua ativa no Delta instalado, testar os mapas e o BHOP com/sem contato, observar o micro-hop e medir FPS. Sucesso offline não é validação da física ou dos hooks no iOS. A referência funcional continua sendo a V3.1 que o usuário já testou.
