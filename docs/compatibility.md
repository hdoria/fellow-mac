# Compatibilidade

Estado em 2026-10-13. Este arquivo separa o comportamento implementado daquilo que depende de conta, serviço e aparelho reais.

| Recurso | Condição e limite |
| --- | --- |
| macOS | 14 ou superior, Swift 6. Build local pra arquitetura do host. |
| Menubar e demonstração | Dados sintéticos, sem chamadas à Fellow. Build release e janela de demonstração verificados no host arm64/macOS 27.0.1. Interação direta com o item da menubar ainda não verificada. |
| Login e renovação | Contrato v2 observado. Sem teste autenticado com a conta do usuário. |
| Estado | Leitura da nuvem. Horário da consulta não prova que a máquina enviou telemetria recente. Campos ausentes permanecem indisponíveis. |
| Perfis, importação e compartilhamento | Rotas v2 observadas em fontes estáticas e comunitárias. Gravações reais precisam de confirmação no aparelho. |
| Agendamentos | Dias de domingo a sábado e fuso IANA da cafeteira. A [Fellow](https://fellowproducts.com/pages/app) descreve o horário como café pronto. Mapeamento e execução física ainda não testados aqui. |
| Instant Brew | Experimental, desativado por padrão. Fonte comunitária relata firmware 1.5.16 ou superior. Usa a configuração atual de Instant Brew do aparelho. |
| Parada remota | Ausente. Relato comunitário não confirmou cancelamento do preparo. |
| Pareamento, Wi-Fi, firmware | Faça no app oficial da Fellow. |

Versão de firmware suficiente não comprova suporte ao comando. Pra testar Instant Brew, primeiro confirme leituras e estados no aparelho, habilite o recurso experimental e prepare água, café e recipiente. Confirme cada envio. Um timeout pode deixar o resultado incerto: confira a cafeteira antes de tentar de novo.

Verificação independente local: 48 testes aprovados, incluindo dois testes com entradas isoladas no Keychain. Os testes usam dados sintéticos e não comprovam integração com a nuvem real.

A versão local usa assinatura ad-hoc. Developer ID, notarização, distribuição universal e validação em Intel ficam fora da prova desta versão. A [primeira execução da CI](https://github.com/hdoria/fellow-mac/actions/runs/38399207787) passou em arm64/macOS 15 com Swift 6.1.2: testes e bundle release. Consulte o [registro de verificação](verification.md) para os fluxos observados e as pendências.

Fontes de comportamento: [nota v2 do Home Assistant](https://github.com/kristofferR/FellowAiden-HomeAssistant/blob/de409f8df513a4ef72389e43f6bc5ffd1883bb75/docs/fellow-api-v2.md) e [README fixado](https://github.com/kristofferR/FellowAiden-HomeAssistant/blob/de409f8df513a4ef72389e43f6bc5ffd1883bb75/README.md). Essas observações não substituem teste no seu aparelho.
