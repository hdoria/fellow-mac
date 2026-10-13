# Contrato de interoperabilidade observado

Observações em 2026-10-13. API móvel sem contrato público de estabilidade. Nenhuma chamada autenticada, conta real ou comando físico foi usado na pesquisa. Rotas encontradas em código estático mostram a construção da requisição, sem comprovar que o servidor a aceita hoje.

Base observada: `https://l8qtmnc692.execute-api.us-west-2.amazonaws.com/v2`. O endereço consta na configuração nativa do pacote Android pesquisado. A seleção de ambiente em execução não foi observada.

## HTTP e sessão

| Operação | Método e caminho | Corpo |
| --- | --- | --- |
| Login | `POST /auth/login` | `email` em minúsculas, `password`, `timezone` IANA |
| Renovação | `POST /auth/refresh-token` | `refreshToken` |
| Aparelhos | `GET /devices?dataType=real` | Ausente |
| Aparelho | `GET /devices/{deviceId}?dataType=real` | Ausente |
| Perfis | `GET /devices/{deviceId}/profiles` | Ausente |
| Perfil | `GET /devices/{deviceId}/profiles/{profileId}` | Ausente |
| Importação: consulta | `GET /shared/{dropType}/{sharedId}` | Ausente |
| Importação: gravação | `POST /devices/{deviceId}/profiles` | Parâmetros validados do perfil, sem campos do servidor |
| Compartilhamento | `POST /devices/{deviceId}/profiles/{profileId}/share` | Ausente |
| Agendamentos | `GET /devices/{deviceId}/schedules` | Ausente |
| Criar agendamento | `POST /devices/{deviceId}/schedules` | Objeto abaixo |
| Ativar/desativar | `PATCH /devices/{deviceId}/schedules/{scheduleId}` | `enabled` booleano |
| Remover agendamento | `DELETE /devices/{deviceId}/schedules/{scheduleId}` | Ausente |
| Instant Brew | `PATCH /devices/{deviceId}/start?confirm=true` | Ausente |

Chamadas autenticadas usam `Authorization: Bearer <accessToken>`. O modelo local de sessão contém `accessToken` e `refreshToken`. TTL, rotação, envelopes de resposta e limites de requisição ainda precisam de teste com a conta. Tokens persistidos vão pro Keychain.

A sessão serializa renovação e invalida resultados anteriores após logout ou troca de conta. Uma leitura pode renovar uma vez. Gravações não são repetidas automaticamente depois de uma resposta incerta. A interface deve reler o estado antes de um novo envio. `Retry-After` interrompe consultas durante o prazo indicado.

## Dados do aparelho e perfis

O estado local distingue conexão, fase de preparo, firmware, fuso, água, tampa, jarra, cesto, limpeza, enxágue e erro. Ausência de campo mantém valor desconhecido. Horário de consulta HTTP e horário de telemetria da máquina são dados diferentes. O estado v2 aninhado tem precedência sobre indicadores antigos quando ambos existem.

`brewStartTime` e `brewEndTime` podem mudar fora de um ciclo. A subtração isolada não comprova duração. Estados reconhecidos são apresentados na interface; valores novos precisam de tratamento como estado desconhecido.

Um perfil tem identificador, título e parâmetros de receita. Os dados devolvidos pela API podem conter mais campos que o resumo exibido. Importação deve preservar apenas parâmetros de receita validados e retirar IDs, vínculos, timestamps e metadados do servidor antes de criar um perfil. Os ramos de outros produtos podem exigir prefixos e `settingsVersion`; esse comportamento não foi confirmado pra Aiden.

Links comunitários seguem `/p/{sharedId}` ou `/p/{sharedId}/aiden`. A consulta v2 é `/shared/aiden/{sharedId}`. O Mac deve aceitar somente hosts conhecidos da Fellow, HTTPS e o tipo Aiden, extrair o identificador e consultar a base fixa. O link informado nunca deve decidir o servidor HTTP. Outros produtos e formatos de compartilhamento ficam fora deste contrato até validação.

## Agendamentos

Objeto de criação, com valores sintéticos:

```json
{
  "days": [false, true, true, true, true, true, false],
  "secondFromStartOfTheDay": 25200,
  "enabled": true,
  "amountOfWater": 500,
  "profileId": "p123"
}
```

`days` contém 7 booleanos, domingo primeiro e sábado último, com pelo menos um dia escolhido. `secondFromStartOfTheDay` é um inteiro entre 0 e 86399, calculado no fuso IANA confirmado da cafeteira. `amountOfWater` é inteiro em ml, entre 150 e 1500. A restrição comunitária de perfil é `p` ou `plocal` seguido de dígitos. O perfil precisa pertencer à cafeteira selecionada.

A [página oficial da Fellow](https://fellowproducts.com/pages/app), seção “Schedule in advance”, descreve o horário escolhido como café pronto. Essa fonte prevalece sobre o comentário antigo do cliente TypeScript que chama o campo de início do preparo. O Mac envia o horário local escolhido sem calcular ou subtrair duração. A execução física desse mapeamento ainda precisa de teste. Fuso ausente ou inválido impede criação, evitando assumir o fuso do Mac. Repetições em transições de horário de verão dependem do comportamento do firmware.

## Início remoto e funções excluídas

O pacote Android contém duas chamadas pra `/start`: Instant Brew sem corpo e preparo com `profileId` e `amountOfWater` inteiro. A versão inicial usa somente Instant Brew. Ele usa a receita e a quantidade já configuradas na cafeteira.

A fonte comunitária v2 relata suporte a partir de firmware 1.5.16. O Mac exige habilitação experimental, estado recente, sensores conhecidos e confirmação de preparo. A versão do firmware é uma condição prévia, sem comprovar efeito físico. Falhas e timeouts não disparam outra tentativa.

A rota `PATCH /devices/{deviceId}/stop` existe no pacote. O relato comunitário não confirmou cancelamento e o Mac não a oferece. A rota `selectedProfile` também foi encontrada, mas a fonte v2 relata rejeição pelo gateway. FCM, pareamento, Wi-Fi, reset e atualização de firmware ficam fora desta implementação.

## Evidência e precedência

A [pesquisa completa](research/2026-10-13-aiden.md) registra hashes, método e referências fixadas. A análise estática examinou pacote Android identificado como 1.4.6, código 54, obtido no [APKPure](https://apkpure.net/fellow/com.fellowproducts.Fellow/download). A assinatura não foi verificada contra uma cópia da Google Play. Nenhum pacote ou disassembly é distribuído aqui.

Pra semântica de produto, prevalece a documentação oficial. Pra chamadas HTTP v2, prevalecem os pontos de chamada do pacote e a [nota v2](https://github.com/kristofferR/FellowAiden-HomeAssistant/blob/de409f8df513a4ef72389e43f6bc5ffd1883bb75/docs/fellow-api-v2.md) com relatos explícitos, acima dos clientes v1. O teste no aparelho é a prova final do efeito de uma operação. Consulte [atribuições e licenças](../THIRD_PARTY_NOTICES.md).
