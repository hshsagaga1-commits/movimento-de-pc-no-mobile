# Diagnóstico isolado do conflito entre a V3.1 e o macro Evade

Base funcional: `feature/pc-movement-v31-ui-fixes-20261102`, commit `a48741ca0f7b86f7a2c2631778ee5a86691b180f`.

O usuário identificou como macro ativo `https://github.com/StyearX/solasmotaryx/blob/main/Evade/Legecy`, blob `80f5a1f11410e8ceff3304166d401a74dda677e8`. A fonte recebida tem 126395 caracteres em duas linhas e ofusca os nomes de APIs, teclas, handlers e botões. A simples ausência de `SendMouseButtonEvent` no texto visível não comprova que o macro não o utiliza.

O bridge da V3.1 chama `VirtualInputManager:SendKeyEvent` para W/A/S/D e Space e não chama diretamente `SendMouseButtonEvent`. O monitor deve comparar eventos efetivamente recebidos por `UserInputService` com o dedo dono do joystick e com os objetos de GUI sob cada toque. Em Delta, entradas do executor e chamadas internas ofuscadas ainda podem não ser observáveis por essas APIs: o relatório indica correlação, não prova definitiva da causa.

Como a causa não foi confirmada e não há execução real em Delta aqui, implementar **somente** um diagnóstico temporário e independente. Não modificar nenhum arquivo da V3.1, seu loader, MEMEDASH ou o macro original. Não interceptar, consumir, reenviar, bloquear nem alterar eventos; somente ouvir. Sem novas interfaces, simulação de clique, alteração de física ou processamento a cada frame. Expor API `getgenv().PCMovementV31MacroProbe` com `Mark(label)`, `GetReport()`, `CopyReport()` e `Stop()`. Relatório limitado em memória, sem envio pela rede nem arquivo escrito automaticamente. Limpeza/restauração ao reexecutar e parar. Um loader avulso sem cache permite usar o diagnóstico junto com os dois scripts já usados, sem substituí-los.

Verificação offline em Luau: preservar byte a byte a V3.1 da base, reproduzir toques em duas regiões, teclas, eventual clique de mouse, uma mudança rápida de direção, marcação e desconexão. Não apresentar o conflito como corrigido antes de observar os dados do iPhone/Delta.
