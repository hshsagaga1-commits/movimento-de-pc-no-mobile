# Diagnóstico temporário: macro Evade + joystick V3.1

O arquivo `Evade/Legecy` informado pelo usuário, blob `80f5a1f11410e8ceff3304166d401a74dda677e8`, é fortemente ofuscado em uma linha de 126 mil caracteres. Não foi possível identificar estaticamente qual handler interpreta os toques, teclas e cliques. No bridge da V3.1, os únicos envios diretos de `VirtualInputManager` são `SendKeyEvent` de W/A/S/D e Space; não há envio direto de clique de mouse. Isso ainda não identifica o comportamento do executor ou do macro dentro do Evade.

Este branch contém **apenas uma ferramenta temporária de observação com painel mobile**. A V3.1, suas correções de cursor e bolinha, o macro original e o MEMEDASH permanecem intactos. Nenhum deles é carregado pelo diagnóstico; use seus próprios loaders atuais normalmente.

## Como coletar uma reprodução

1. Inicie o joystick V3.1 preservado e o macro original como sempre faz.
2. Execute temporariamente o [PCMovementV31MacroProbe_AUTOEXECUTE.lua](PCMovementV31MacroProbe_AUTOEXECUTE.lua), ou cole a linha abaixo no Delta:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v31-macro-probe-export-ios-20261102/PCMovementV31MacroProbe_AUTOEXECUTE.lua?_cb="..game:GetService("HttpService"):GenerateGUID(false),true))()
```

3. Aparece **CARREGANDO...**; quando o painel mostrar **ATIVO • registrando**, movimente o joystick até o emote ser acionado sem intenção e toque em **MARCAR BUG**.
4. Toque em **COPIAR LOG**. A mensagem **CÓPIA SOLICITADA** quer dizer apenas que a função do executor retornou sem erro; **não confirma** que o iOS recebeu o texto. Confira em outro campo antes de depender dessa cópia.
5. **SALVAR LOG** fica disponível mesmo sem tentar a cópia. Quando `writefile` existe, grava o relatório completo no caminho **relativo ao espaço de arquivos do executor** `PCMovementV31MacroProbeLog.txt`. O painel mostra nome e caminho. Se `readfile` também existir e devolver exatamente os mesmos bytes, mostra **ARQUIVO VERIFICADO**; sem leitura de volta, mostra **SALVAMENTO SOLICITADO**. O caminho absoluto do sandbox do Delta no iOS não é exposto por essas funções.
6. **VER LOG** abre uma caixa de texto com o relatório. Mantenha o dedo no texto e use a seleção/cópia do iOS, se o Delta permitir. Relatórios grandes aparecem em páginas; use **<** e **>** e copie cada página, ou prefira o arquivo `.txt` para obter tudo de uma vez. Toque em **ENCERRAR** quando terminar. Reexecutar o loader inicia um relatório vazio.

O painel inicia no canto superior direito e é arrastável pelo cabeçalho; o arrasto permanece na metade direita, longe do joystick. O relatório mostra o tipo de entrada, tecla, coordenadas, dedo dono do joystick (`owner=joystick`), estado do chord, contadores `keysSent`/`jumpPulses` e até três objetos de interface sob cada toque, tanto em `PlayerGui` (`gui=`) quanto em `CoreGui` (`core=`), se este estiver acessível. `MARK` usa a hora do toque no botão; não detecta automaticamente a ativação do emote. `UserInputService` pode não receber todos os eventos internos do executor. Coincidência de horários sozinha não prova causalidade.

Posições repetidas do dedo são limitadas a um registro por 80 ms por grupo; mudanças de combinação, de teclas enviadas ou de pulsos de pulo sempre são registradas. O relatório conserva no máximo 320 entradas. A consulta de objetos da interface ocorre apenas no início de um toque. O diagnóstico não envia entradas virtuais, não bloqueia eventos, não altera o cursor/câmera/física e não envia o relatório pela rede. A cópia usa a área de transferência somente no botão **COPIAR LOG**; um arquivo local só é gravado ao tocar em **SALVAR LOG**. Nenhuma tentativa de exportação limpa o relatório na memória. Evite abrir o chat ou digitar informações pessoais durante a coleta, pois o relatório inclui nomes das teclas recebidas.

Testes offline em Luau verificam separação dos dedos de câmera/joystick, painel por toque e arrasto, status honesto do clipboard, gravação e leitura de volta quando disponível, conteúdo integral das páginas, limpeza, loader isolado e invariância byte a byte de todos os arquivos da V3.1 publicada. Ainda é necessário executar no Delta para confirmar acesso ao arquivo no iPhone, seleção de texto na interface real e relação do relatório com o emote.
