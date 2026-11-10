# Native Classic Lateral + Grid Assist V1 (Evade iOS)

**Status:** candidato experimental, publicado em branch isolada. Não validado no iPhone 11/Delta; não há alegação de inversão física instantânea ou de melhoria de FPS.

## O que este projeto faz

Mantém o Classic Thumbstick **nativo do Roblox**: TouchGui, frame, knob, área de toque, câmera, botão nativo de pulo, movimento para frente/trás e diagonais. Nenhum teclado PC/WASD, joysticks substitutos, toque artificial, Space ou escrita em WalkSpeed/AssemblyLinearVelocity.

- Intercepta somente o vetor de saída de `TouchThumbstick:GetMoveVector()` do controlador **clássico ativo**.
- Quando a intenção for **puramente lateral**, aplica magnitude horizontal 100% com deslocamento do dedo a partir de **20%** do raio visual, preservando o joystick nativo.
- Após manter uma lateral forte e começar a cruzar para a lateral oposta, aceita a intenção contrária a partir de ~**6,5%** do raio por uma janela curta (até 110 ms). Não inventa movimento antes de o dedo ultrapassar o centro.
- Preserva o vetor **nativo** ao soltar, quando o toque não está ativo, quando não é lateral pura, quando há entrada diagonal real ou quando outro tipo de joystick é selecionado.
- Anexa somente ao controlador Classic Thumbstick (módulo `TouchThumbstick`) quando este é reconhecido. Evita competir com outro controlador, e restaura o método original em Stop.
- Inclui o **Grid Assist light** da V3.1 preservada, adaptado para ler o analógico nativo; detecta contato/grades e orienta visualmente o avatar. NÃO empurra o personagem contra a grade, NÃO cria salto extra e NÃO escreve velocidade. O detector conserva o orçamento de raios da V3.1. 

**Limitação:** aumentar magnitude do comando lateral NÃO remove inércia física, aceleração, regras do Evade ou atraso da rede. Somente o teste no próprio jogo determina o resultado. A versão legada do PlayerModule é exigida; se a experiência ativar o novo Input Action System e não expuser o antigo GetControls, o plugin falha de forma segura e relata isso em `GetState()`.

## Como testar (Delta)

1. Em Configurações do Roblox, use **Classic Thumbstick / Joystick clássico**.
2. **Desative/remova do AutoExecute o PC Movement V3.1/V3.2, macros de movimento e outros sistemas de joystick**, para que somente um controle atue. O loader tenta encerrar a V3.1 preservada ativa, se detectar.
3. Rode SOMENTE:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/native-classic-lateral-assist-20261109/NativeClassicAssistV1Loader.lua"))()
```

Depois:

```lua
print(game:GetService("HttpService"):JSONEncode(getgenv().NativeClassicAssistCombo.GetState()))
```

Verifique `native.installed=true` e `native.active=true` quando estiver usando o joystick. Se `installed=false`, não presuma que houve melhoria: o acesso ao controlador nativo não foi obtido.

## Teste comparativo sugerido

No mesmo mapa e FPS, compare sem script e com script: segurar 100% esquerda, arrastar até 100% direita, sem tirar o dedo; repetir ao contrário; depois testar movimento diagonal e frente/trás, pulos e trimp/bhop. Se a câmera/joystick nativo desaparecer, encerre o script e reinicie a sessão sem loaders antigos.

## Desativar e diagnosticar

```lua
getgenv().NativeClassicAssistCombo.SetEnabled(false) -- desliga o modificador
getgenv().NativeClassicAssistCombo.SetEnabled(true)  -- reativa
getgenv().NativeClassicAssistCombo.SetAssistEnabled(false) -- testa a melhoria lateral sem Assist
getgenv().NativeClassicAssistCombo.SetAssistEnabled(true)  -- reativa somente o Assist
getgenv().NativeClassicAssistCombo.SetDiagnostics(true)
local ok,path,json=getgenv().NativeClassicAssistCombo.ExportDiagnostics()
print(ok,path,json)
getgenv().NativeClassicAssistCombo.Stop() -- encerra ambos e restaura o método nativo
```

Observação: desativar o modificador zera a intenção lida pelo Assist; `Stop()` desliga ambos.

## Escopo e rastreabilidade

- `NativeClassicLateralV1.lua`: módulo de entrada nativa (sem GUI).
- `NativeClassicGridAssistV1.lua`: cópia isolada, adaptada de `LegacyGridContactAssistV31Preserved.lua` sem alterá-lo.
- `NativeClassicAssistV1Loader.lua`: carga, parada, diagnósticos.
- Branch criada a partir de `feature/pc-movement-v31-preserved-20261101`. Os arquivos originais de PC Movement (inclusive V3.1/V3.2) não foram editados.

## Validação e próximos limites

Checagens estáticas: não inserir GUI, manipular `TouchGui.Enabled`, injetar teclas, alterar velocidade, criar pulos ou sobrescrever o código histórico. Casos de vetores previstos: A, D, inversão lateral, desvio diagonal, centro e soltar. Pendente: compilar em Luau/validar no cliente iOS, verificar se `TouchThumbstick:GetMoveVector` está acessível no Delta da versão instalada, testes de contato e FPS. Nenhum valor numérico de FPS foi medido.
