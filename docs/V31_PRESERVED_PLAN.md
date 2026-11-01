# V3.1 preservada — correção incremental

Base autorizada: ce4eb8b, branch original feature/pc-movement-assist-v31-contact-hop. Não usar nem herdar o motor rebuild.

## Limite da alteração

Os 112 arquivos da base ficam byte a byte iguais. Novo loader chama o PCModeLockV3 original e toda a cadeia anterior, sem alterar o bridge, os acordes, o pulo de 200 ms, o knob, a seleção de teclado, os hooks ou a câmera. Só o módulo separado de Assist recebe alterações. O clone anterior restringia o alcance visual do knob em telas pequenas; o novo loader volta ao cálculo original, inclusive o raio mínimo de 46 px.

## Etapas

- [x] Testar a execução do loader com uma rede controlada: ele precisa iniciar o bootstrap original e o Assist separado, e trocar Assist sem reinstalar PC/UI.
- [x] Testar o próprio módulo alterado com eventos e contatos controlados: A/D e velocidade horizontal intactos, sem força para dentro, não criar salto no ar, reconhecer barras horizontais, rejeitar pisos/decoração, respeitar orçamento de consultas e limpar corretamente.
- [x] Derivar um módulo do Assist V3.1: remover somente suas correções de velocidade/impulsos, manter o visual facing anterior, ampliar descoberta com consultas limitadas e registrar contato físico separado de proximidade.
- [x] Instrumentar micro-hop como investigação instrumentada: ler pulsos do pulo antigo e mudanças verticais perto de contato; não substituir a mecânica não confirmada por força nova nem competir com o Space do bridge.
- [x] Testar sintaxe Luau, comparação de todos os arquivos originais, integração de reload/Stop e reversão só do Assist. Revisão de código e publicação apenas da branch nova.

## Reversibilidade

Loader oferece SetAssistMode("original") para executar o LegacyGridContactAssistV31 original e SetAssistMode("light") para o ajuste, sem tocar teclado/UI. Se a carga do ajuste falhar, volta ao Assist original. A opção original também conserva as limitações físicas antigas e não é descrita como correção delas.

## Verificação e limites

A comparação de arquivos prova preservação de fonte; execução offline prova somente os cenários simulados. Física do Evade, reconhecimento dos mapas, mecânica exata do micro-hop e compatibilidade efetiva com o Delta exigem jogo no aparelho. O relato do usuário é a referência funcional da V3.1, superior ao sucesso dos testes offline da reconstrução.

## Registro da execução

- Limite respeitado: somente arquivos novos; nenhum dos 112 originais alterado. Novo branch nasce diretamente de ce4eb8b.
- O teste executa o bridge/visual original, inclusive acordes próximos ao eixo W e estágios W+D/W+A+D/W+A. O teste não redefine essas funções.
- A mesma cena controlada produz escrita de velocidade no Assist antigo e nenhuma no ajustado. Não é uma simulação completa da física do Evade.
- Limite visual original restaurado por reutilização da fonte, sem criação de controles alternativos.
- Diagnóstico testado também antes da primeira amostragem, quando não há contato.
- Compilação exploratória global: LegacyProbeV2.lua:225 já tem erro sintático na base. Preservado por estar fora da cadeia usada. A compilação dos módulos usados e toda a suíte Luau passam.
- A cadeia original contém dependências de ramos diferentes. Em especial, CameraTouchRightHalfGateV5 do classic-wasd-experiment difere do snapshot local V3.1; o loader preserva o endereço realmente utilizado pelo bootstrap, sem substituí-lo pelo arquivo do snapshot.
- Entrega: revisão de escopo/rollback concluída; publicação restrita à branch nova.

- Revisão de 7e322bb: os originais e o escopo foram confirmados. Um problema importante no loader foi reproduzido: chunk com yield podia instalar Assist depois de Stop.
- Correção: instalação serializada só no wrapper, geração verificada antes/depois do chunk, limpeza do resultado cancelado antes de liberar a instalação. Nenhum bootstrap nativo foi editado. Pausa original de 250 ms na recuperação restaurada.
- RED/GREEN: teste com corrotina demonstrou ressurreição após Stop antes da correção; agora cobre Assist ajustado/original e rerun durante reparo PC suspenso, preservando o novo dono. Toda a suíte passa.
- Cabeças remotas conferidas: V3.1 ce4eb8b; classic-wasd-experiment 3a50d72; V3 54b0a87. Continuam os mesmos endereços consumidos pelo bootstrap original.

- Verificação da correção em revisão local 6b53fdd: sem achados importantes/críticos restantes. Suíte completa e comparação dos 112 originais reexecutadas pelo revisor.
- Publicação por integração GitHub, pois o Git local não tem credencial de escrita. Commit público conserva a árvore verificada, com ce4eb8b como pai; os commits locais de revisão são preservados no checkout.
- Limites mantidos: não há teste real de Delta/iPhone/colisão do Evade; micro-hop é investigação, não impulso substituto anunciado como reproduzido.
