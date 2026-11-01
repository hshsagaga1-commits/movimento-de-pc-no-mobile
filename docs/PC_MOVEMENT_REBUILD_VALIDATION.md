# Análise de referência e validação

## Vídeo anexado

`export_1793530456912(1).mp4`: 17,367 s, vídeo H.264, 896×512, 30 fps; gameplay até aproximadamente 14,3 s. Inspeção por sequência de quadros a 2 fps e ampliações de trechos exteriores/interiores a 5 fps. Os últimos segundos são a vinheta TikTok.

- **~0–3,9 s:** passarela externa, bancos, cobertura verde e guarda-corpos. O personagem descreve arcos, aproxima-se de bordas/grades e aparece afastado delas em trechos consecutivos. A câmera gira muito; deslocamento na tela não informa sozinho a direção física. A troca de avatar/enquadramento no final impede assumir continuidade de uma única manobra.
- **~4–8,8 s:** área externa com passarelas, árvore e bordas. Há sucessivas passagens pelo limite elevado e afastamentos sobre a região aberta. A sequência sustenta priorizar controle lateral contínuo e saída livre, sem aderência constante.
- **~8,9–14,3 s:** área interna com madeira, barras/guarda-corpos, cadeiras e limites elevados. Há passagens repetidas junto às estruturas e trechos em que o personagem ocupa a região aberta. Oclusões pelo cenário e rotação da câmera tornam ambíguos os instantes exatos de apoio e a altura física.

**Visível:** arcos rápidos, aproximação/afastamento, orientação variável, contatos aparentemente breves, continuidade visual de movimento e trechos sem apoio visual. **Não comprovado pela gravação:** teclas pressionadas, estado interno de crouch/emote, velocidade mundial, normal de contato, aceitação de um pulo ou origem de cada impulso vertical. A aparência de animação não é usada como prova de BHOP, emote ou técnica específica.

W+A/W/W+D/S em pé e A/D sem W durante BHOP/emote são requisitos fornecidos pelo usuário. Não são apresentados como teclas extraídas do vídeo. A técnica exata do micro-hop continua pendente de observação no jogo.

## Auditoria do histórico

Base da reconstrução: `ce4eb8b`, em `feature/pc-movement-assist-v31-contact-hop`. Foram examinados V6/V3 de teclado, bootstraps V5/V6/V3, loaders combinados e os assists V1/V3/V3.1. O AutoExecute V3.1 entregue anteriormente é um loader de quatro linhas para `CombinedJoystickAssistV31Loader.lua`; não contém outro motor escondido.

- `PCKeyboardTouchBridgeV6.lua` e V3: em uma região frontal, pequenos desvios retornam W+A+D; inversões podem agendar etapas W+A / W+A+D / W+D, com intervalo de 16 ms por etapa. Não distinguem os estados pedidos nesta reconstrução.
- `LegacyGridContactAssistV31.lua:369`: projeta e escreve a velocidade horizontal, adiciona componente para dentro da superfície e gera velocidade lateral a partir de WalkSpeed. A inversão com contato mantido transforma a interpolação em um fator que pode deixar apenas 30% da velocidade anterior.
- V3.1 também altera Y diretamente em dois caminhos de hop. Um deles aceita personagem no ar. A reconstrução não carrega nenhum desses caminhos.
- O contato antigo aceita proximidade de raycast e histórico de contato. Peças nomeadas podiam escapar da validação CanCollide. O ramo para barras horizontais fica depois de uma rejeição que exige altura de barra vertical, tornando-o inalcançável.
- O Stop V3.1 compara a versão publicada contra outra string e pode deixar um global obsoleto. O novo início cancela os tokens e limpa esse global explicitamente.
- Os loaders antigos encadeiam downloads de branches diferentes. O novo bundle contém toda a implementação, sem executar essa cadeia.

Esses são defeitos demonstráveis no código; eles não medem quanto da desaceleração total observada no jogo veio de cada defeito.

## Testes offline executáveis

Comando completo: `LUAU_COMPILE=/caminho/luau-compile python3 tools/check_rebuild.py`.

- Núcleo: combinações exigidas, modo lateral, BHOP invertido observado, estados sobrepostos, mudança de modo com dedo mantido, intensidade/ângulo, neutro, inativo, morte, troca A/D e retries de teclas.
- Pulo: um pulso por toque, buffer de 200 ms, segurar para novo pedido no pouso, cooldown, nenhum pedido assistido repetido no ar e respeito ao bloqueio de pulo.
- Sensor: proximidade diferente de contato, contato colidível atual, retirada de contato, chão/parede/decoração/Truss/Mesh anônimo, fileira de barras, rejeição de pernas de mobiliário em triângulo, rate limit e respawn.
- Apresentação: sprites/crops exatos, layout pequeno, resposta visual independente, regiões de toque, alterações externas de tamanho/posição e atributo de bloqueio preservados em recarga.
- Integração: entrada no mesmo evento, retirada de W ao ficar no ar, mudança A/D, background/foco, morte, desligar/ligar, migração V3.1, provedor de emote, parte do corpo carregada depois do spawn e apenas um loop após recarga.
- Regressões da revisão: Cancel/End de dedos de pulo e movimento, InputEnded perdido, vários dedos no pulo, câmera substituída com dedo mantido, remoção isolada do Knob, rollback de inicialização, parada por erro de callback e reenvio de entradas após reativar o Keyboard.
- Rota mobile: KeyboardEnabled falso fora da ativação, capacidade temporária durante a ativação mesmo com identidade de executor, preservação de hook posterior e respeito tanto a `disabled` quanto a `controlsEnabled`.
- Empacotamento: bundle corresponde às fontes, compilação Luau, ausência de escritores físicos e arquivos históricos intactos.

A suíte de comportamento foi executada em Lua e novamente na CLI Luau, incorporando as mesmas fontes e fixtures sem reescrever a lógica. Continuam sendo testes offline com serviços simulados.

## Roteiro ainda necessário dentro do Roblox/Delta

1. Abrir somente o novo AutoExecute no iPhone 11. Confirmar `route.ready=true`, três métodos de câmera instalados ou explicar qual câmera específica do jogo é usada. Testar câmera e joystick com dedos separados, cruzando lados, soltando fora do botão e abrindo chat/menu.
2. No chão, conferir as quatro combinações no `GetState().chord`, inclusive pequenas mudanças do polegar. Agachar/parar de agachar sem soltar o joystick; confirmar o sinal real e sua fonte. Se a fonte permanecer `unknown`, coletar `Probe()` em cada estado.
3. Saltar e inverter a câmera/orientação; verificar que W não reaparece em voo e que A/D trocam imediatamente. Comparar o resultado contra teclado físico no mesmo mapa e condição. A ausência de escritores de velocidade não garante que a física nativa mantenha a mesma velocidade.
4. Ativar cada emote móvel relevante. Confirmar atributo/BoolValue ou ID exato, encerrar o emote e verificar a volta imediata ao estado correto. Nenhum teste offline confirma todos os emotes do Evade.
5. Nas estruturas dos três trechos do vídeo, comparar `nearby`, `gridContact`, `evidence` e `part`. Aproximar sem tocar, encostar, sair, inverter e voltar. Conferir falso positivo em paredes, chão, cadeiras e escadas. Desativar inferência geométrica para comparar.
6. Com intenção de pulo ativa, conferir o pedido único nativo ao pousar/contatar e a resposta do jogo. Medir a origem/altura do micro-hop antes de qualquer ajuste. Se um contato vertical no ar permitir uma mecânica especial, identificar seu código/entrada real antes de implementá-la; não substituir por velocidade forçada.
7. Testar respawn, troca de mapa, destruição/recriação da UI, morte, app em background, erro de transporte e recarga do arquivo. Conferir ausência de teclas presas e interferência de outros AutoExecutes.
8. Medir FPS, tempo por atualização, número de consultas e bateria no aparelho com diagnóstico ligado/desligado. Os limites de frequência são implementados; o desempenho no iPhone ainda não foi medido.

## Fontes técnicas primárias consultadas

- [Roblox Humanoid: FloorMaterial, estado e Jump](https://create.roblox.com/docs/reference/engine/classes/Humanoid)
- [Roblox RaycastParams](https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams)
- [Roblox WorldRoot e consultas de colisão](https://create.roblox.com/docs/reference/engine/classes/WorldRoot)
- [Roblox PlayerModule/ControlModule](https://github.com/Roblox/avatar/blob/main/ReferenceBodyCreator/StarterPlayerScripts/PlayerModule/ControlModule/init.lua)

Essas fontes descrevem a engine; não documentam a implementação privada de Evade nem as capacidades específicas do Delta instalado no aparelho.
