# PC Movement V3.2 adaptativo

Base obrigatória `62269b83bb05f3fd5eca76f5eeb7102555afc241`. O caminho que a V3.1 realmente carrega combina esse Assist, o bridge do snapshot V3 e o bootstrap, visual e gate de câmera de `classic-wasd-experiment`. Os ajustes de cursor e alcance visual vêm da entrega visual posterior.

1. Reproduzir V3.1 na CLI Luau, inclusive o traço de teclas, e acrescentar cenários que falham na base.
2. Derivar o bridge da V3.1. Manter setores, raio lógico, captura e prioridade. Resolver o mapeamento com acordes compartilhados, preservar a sobreposição no arco frontal e invalidar etapas antigas na mudança de modo/direção. Usar uma conexão ativa durante cada janela de pulo.
3. Observar atributos e valores explícitos de postura, o Stand documentado pelo probe Legacy e nomes de animação que identifiquem explicitamente agachamento ou emote. Conservar o modo em pé como padrão quando o cliente não fornece sinais.
4. Empacotar o bootstrap real, o gate, o visual e o Assist com revisões fixas. Evitar a montagem dos dois joysticks descartados pela V3.1. Conservar as verificações do controlador e atualizar os textos somente quando mudam. O Assist leve conserva a cadência e o orçamento de consultas, reaproveita estruturas e usa leituras escalares do bridge.
5. Testar carga, recarga, cancelamento, respawn, gestos simultâneos e stress no bundle publicado. Medir a CLI e contadores separadamente de um futuro perfil do Roblox no iPhone.
