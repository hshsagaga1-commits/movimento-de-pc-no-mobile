# Diagnóstico temporário: macro Evade + joystick V3.1

O arquivo `Evade/Legecy` informado pelo usuário, blob `80f5a1f11410e8ceff3304166d401a74dda677e8`, é fortemente ofuscado em uma linha de 126 mil caracteres. Não foi possível identificar estaticamente qual handler interpreta os toques, teclas e cliques. No bridge da V3.1, os únicos envios diretos de `VirtualInputManager` são `SendKeyEvent` de W/A/S/D e Space; não há envio direto de clique de mouse. Isso ainda não identifica o comportamento do executor ou do macro dentro do Evade.

Este branch contém **apenas uma ferramenta temporária de observação com painel mobile**. A V3.1, suas correções de cursor e bolinha, o macro original e o MEMEDASH permanecem intactos. Nenhum deles é carregado pelo diagnóstico; use seus próprios loaders atuais normalmente.

## Como coletar uma reprodução

1. Inicie o joystick V3.1 preservado e o macro original como sempre faz.
2. Execute temporariamente o [PCMovementV31MacroProbe_AUTOEXECUTE.lua](PCMovementV31MacroProbe_AUTOEXECUTE.lua), ou cole a linha abaixo no Delta:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v31-macro-probe-mobile-20261102/PCMovementV31MacroProbe_AUTOEXECUTE.lua?_cb="..game:GetService("HttpService"):GenerateGUID(false),true))()
```

3. Aparece **CARREGANDO...**; quando o painel mostrar **ATIVO • registrando**, movimente o joystick até o emote ser acionado sem intenção. Toque em **MARCAR BUG**, depois em **COPIAR LOG**. A tela confirma **COPIADO!**.
4. Cole **o texto inteiro** do relatório na conversa. Se aparecer **ERRO AO COPIAR**, use **SALVAR ARQUIVO** quando disponível e encontre `PCMovementV31MacroProbeLog.txt` nos arquivos do Delta. Toque em **ENCERRAR** para desativar o diagnóstico e remover o painel. Reexecutar o loader inicia um relatório vazio.

O painel inicia no canto superior direito e é arrastável pelo cabeçalho; o arrasto permanece na metade direita, longe do joystick. O relatório mostra o tipo de entrada, tecla, coordenadas, dedo dono do joystick (`owner=joystick`), estado do chord, contadores `keysSent`/`jumpPulses` e até três objetos de interface sob cada toque, tanto em `PlayerGui` (`gui=`) quanto em `CoreGui` (`core=`), se este estiver acessível. `MARK` usa a hora do toque no botão; não detecta automaticamente a ativação do emote. `UserInputService` pode não receber todos os eventos internos do executor. Coincidência de horários sozinha não prova causalidade.

Posições repetidas do dedo são limitadas a um registro por 80 ms por grupo; mudanças de combinação, de teclas enviadas ou de pulsos de pulo sempre são registradas. O relatório conserva no máximo 320 entradas. A consulta de objetos da interface ocorre apenas no início de um toque. O diagnóstico não envia entradas virtuais, não bloqueia eventos, não altera o cursor/câmera/física e não envia o relatório pela rede. A cópia usa a área de transferência somente no botão **COPIAR LOG**; um arquivo local só é salvo no botão de fallback. Evite abrir o chat ou digitar informações pessoais durante a coleta, pois o relatório inclui nomes das teclas recebidas.

Testes offline em Luau verificam separação dos dedos de câmera/joystick, painel por toque e arrasto, feedback de cópia, fallback de arquivo, limpeza, loader isolado e invariância byte a byte de todos os arquivos da V3.1 publicada. Ainda é necessário executar no Delta para conferir a interface real e relacionar o relatório ao emote.
