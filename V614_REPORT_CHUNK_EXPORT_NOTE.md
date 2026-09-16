# V614 — Chunk Export R1

Esta revisão continua da V614 `TemporalPoseTelemetryR1` publicada no commit
`876fa800dc95f00e57e22da1f38024fd462e4e50`. Ela altera somente o transporte
mobile do relatório já pronto.

## Fluxo

1. `PCV614Report(true)` constrói a mesma string completa de antes.
2. Somente depois, essa string é dividida em substrings UTF-8 de no máximo
   `29.500` caracteres de conteúdo.
3. Cada substring recebe um envelope de transporte; o texto total copiado fica
   limitado a `30.000` caracteres.
4. Antes de liberar a exportação, o runtime exige:

```text
table.concat(payloads) == fullReport
```

Logo, removendo os envelopes e concatenando os payloads em ordem, o resultado é
exatamente o relatório original, inclusive espaços, quebras de linha, casas
decimais e telemetria.

Cada envelope registra:

```text
chunk X/N
reportId
totalReportChars
chunkChars
marcador de início do conteúdo original
payload original
marcador de fim do conteúdo original
END CHUNK X/N
```

O `reportId` é um GUID novo por relatório congelado. A GUI mostra parte atual,
total de partes, caracteres do payload, caracteres transportados e tamanho
total do relatório. Uma nova coleta limpa apenas o cache de exportação.

## Interface mobile

- **GERAR PARTES DO REPORT / COPIAR PARTE X/N**;
- **PARTE ANTERIOR**;
- **PRÓXIMA PARTE**.

O primeiro toque no botão azul para a probe se necessário, constrói o relatório
completo uma vez, divide e copia a parte 1. Navegação posterior nunca regenera o
relatório daquela coleta.

## Imutabilidade

Não foram alterados aquisição, telemetria, ownership V604, standing gate,
matching, calipers, segmentos, ABBA, bootstrap, gain, sensitivity, câmera,
character, juntas, animações ou física. Não foi criada V615.

O teste `V614_REPORT_CHUNK_EXPORT_TEST.py` extrai e executa os helpers puros do
runtime com o Luau CLI. Ele cobre vazio, limite exato, múltiplas partes,
Unicode, marcadores parecidos dentro do conteúdo, limite transportado e
reconstrução byte-for-byte.

## Validação da revisão

- `PCV614Report(true)`: corpo do gerador byte-idêntico ao commit-base local;
- runtime V614: `6f0791b3bc5669807903de9c4cd5e66718bbf963ca8cf66e715c7f94348a2fd4`;
- Loader: `fc6c6a90bd128257a2573f82571976d4a4a4d81a5f8a241f0f00abe82ce9cf5a`;
- V20 preservada: `634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef`;
- V500 preservada: `5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096`;
- V604 preservada: `19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571`.
