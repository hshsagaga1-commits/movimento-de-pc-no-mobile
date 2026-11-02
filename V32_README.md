# V3.2 incremental sobre a V3.1 funcional

Base: `feature/pc-movement-v31-ui-fixes-20261102` (`a48741ca0f7b86f7a2c2631778ee5a86691b180f`). Todos os arquivos dessa base continuam byte a byte iguais; esta branch adiciona um Assist e loader próprios. O diagnóstico do macro fica em branch separada e não é carregado aqui.

## Delta AutoExecute

Use somente o loader abaixo para a movimentação. O arquivo `PC_Movement_V32_AUTOEXECUTE.lua` contém a mesma linha:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/pc-movement-v32-v31-preserved-20261102/CombinedJoystickAssistV32Loader.lua?_cb="..game:GetService("HttpService"):GenerateGUID(false),true))()
```

O loader usa o `PCModeLockV3.lua` e o cursor da V3.1 visual já publicada. Esse bootstrap continua carregando o bridge funcional da mesma branch. O joystick e sua bolinha, as combinações W/A/S/D, a troca A/D, a câmera e o pulso de 200 ms não recebem código novo. Somente `LegacyGridContactAssistV32.lua` é novo no caminho ativo. As URLs internas também usam GUID para evitar cache.

## Ajustes internos

- A/D puro durante movimento aéreo não recebe mais rotação forçada de `HumanoidRootPart.CFrame` pelo Assist. Isso preserva a orientação invertida existente enquanto a física e as teclas originais continuam a controlar o movimento. Em pé no chão, a orientação V3.1 permanece.
- O sensor aceita a face superior de uma barra horizontal fina e colidível como **proximidade de grade**, sem rotulá-la como contato físico confirmado por um raio. Pisos largos continuam rejeitados. Não cria colisão, aderência ou impulso.
- Após um contato físico confirmado, uma mudança vertical nos 200 ms seguintes continua sendo observada mesmo se o dedo sair do joystick. Não faz raycasts nesse intervalo sem movimento e não envia Space.
- Nenhuma força ou velocidade é escrita pelo Assist. O limite anterior de consultas (20 amostras/s, no máximo 40 raios por amostra) permanece. O restante da detecção e o teclado PC ficam intactos.

O modo padrão é `light` (V3.2). Se o Assist V3.2 falhar ao carregar, o loader tenta o **Assist leve funcional da V3.1**, sem reinstalar o teclado. A API anterior ainda permite `SetAssistMode("v31")` para esse modo ou `SetAssistMode("original")` para o Assist V3.1 antigo com aderência. `Stop()` encerra somente a instância instalada. O loader da branch V3.1 anterior também permanece disponível para reversão integral.

## Limites e investigação

O vídeo de referência de 17,37 s (896×512, 30 fps) mostra contatos com barras e deslocamento no ar, mas não exibe estados de teclas, velocidade vertical ou a origem física do pequeno salto. Sem execução dentro do Evade no iPhone 11, seria especulação afirmar que o micro-hop resulta de Space, colisão, pulo permitido na borda ou outra mecânica. Por isso V3.2 **não inventa impulso vertical nem promete reproduzir o micro-hop**. O comportamento de emotes do macro ofuscado também não foi alterado ou declarado corrigido; o diagnóstico mobile permanece separado para a próxima reprodução intermitente.

Verificação offline: `tools/check_v32.py` executa o Assist novo e os testes de regressão, confirma que todos os arquivos V3.1 estão intactos, verifica limite de raycasts, ausência de escritas de velocidade e fallback do loader. O verificador V3.1 original (`tools/check_v31_ui_fixes.py`) também deve continuar passando. A física em mapas reais, sensibilidade do A/D em BHOP e micro-hop ainda exigem teste no Delta.
