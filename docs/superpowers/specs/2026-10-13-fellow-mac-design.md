# Fellow Mac: proposta de primeira versão

Status: aprovado pelo usuário em 2026-10-13, incluindo autenticação e MVP completo.

## Intenção e critério de aceite

Criar um cliente open source para a cafeteira Fellow Aiden que rode nativamente no Mac e permaneça acessível pela menubar. Pedido explícito: investigar o app móvel e sua comunicação antes de implementar. Nome provisório: Fellow Mac; projeto independente, sem afiliação com a Fellow.

Prioridades confirmadas: status na menubar e iniciar café pelo Mac, com perfis e agendamentos no MVP completo. Início remoto será uma função experimental separada, condicionada à validação do aparelho. A [pesquisa](../../research/2026-10-13-aiden.md) distingue achados estáticos de funções comprovadas em hardware.

Referências de interface fornecidas pelo usuário: [Ilter Canberk](https://x.com/icanberk/status/2109031477484937571) e [YuriRDev](https://x.com/YuriRDev/status/2109343577583034661), abertas e inspecionadas no navegador. Direção: popover compacto escuro, representação central do aparelho, estado imediato, comando principal destacado e controles secundários discretos. Usar arte própria e componentes nativos, sem copiar assets.

## Abordagens consideradas

| Abordagem | Benefício | Custo |
| --- | --- | --- |
| SwiftUI + URLSession, recomendada | Menubar, janelas e Keychain nativos; sem serviço intermediário | Implementar e manter o contrato HTTP em Swift |
| Tauri + cliente TypeScript | Reaproveitamento de ecossistema web | Integração adicional com macOS; cliente pesquisado ainda usa API anterior |
| SwiftUI + processo Python | Reaproveitar biblioteca existente | Empacotar runtime, gerir processo e revisar licenças/dependências |

Stack aprovada: macOS 14 ou superior, Swift 6, SwiftUI, URLSession e Security.framework; zero dependências de produto. Código próprio sob MIT, com atribuição de pesquisa e sem copiar implementações incompatíveis com a licença escolhida.

## Experiência

1. Ao abrir, ícone na menubar e opção de conectar conta ou entrar em modo demonstração.
2. Login na janela local; senha usada apenas na requisição e descartada. Persistir somente os tokens necessários no Keychain. Logout limpa sessão, tarefas pendentes e dados visíveis.
3. Selecionar explicitamente a Aiden quando houver vários aparelhos. Produtos não suportados são filtrados sem escolher silenciosamente o primeiro dispositivo.
4. Popover mostra nome, estado disponível, horário da última consulta e atualização manual. Ausência de campo vira “indisponível”, nunca valor inventado. Distinguir consulta recente da nuvem de telemetria recente da máquina.
5. Janela principal com Estado, Perfis, Agendamentos e Ajustes. Oferecer leitura/detalhe de perfis, importação por link compatível e compartilhamento; agendamentos podem ser consultados, criados, ativados/desativados e removidos com confirmação.
6. Botão experimental de Instant Brew usa a configuração atual do aparelho, exibe esse contexto e exige confirmação a cada envio. Não prometer seleção arbitrária de receita, controle de volume ou parada remota na primeira versão.

O pareamento inicial, configuração de Wi-Fi e atualização de firmware continuam dependendo do fluxo oficial. Editor completo de receitas, IA, sincronização própria e notificações ficam fora desta versão.

## Fronteiras técnicas

- `AidenCore`: modelos de dispositivo/perfil/agendamento, transporte HTTP, sessão, serviço e regras de apresentação de status. Não depende de SwiftUI.
- `FellowMac`: cenas SwiftUI, estado de interface, Keychain, modo demonstração e ciclo de atualização. Nenhum segredo em UserDefaults, arquivos ou logs.
- Testes com transporte e relógio injetáveis, fixtures sintéticas e verificador independente. O modo demonstração não realiza chamadas de rede.
- App faz chamadas diretas à Fellow por HTTPS. Não há backend nosso, cadastro adicional ou analytics.

Login e renovação são serializados para evitar disputas de refresh token. Uma resposta tardia após logout/troca de conta não pode reconstituir a sessão. Leituras podem tentar renovar uma vez; gravações nunca são repetidas automaticamente depois de resultado incerto.

Atualizar ao abrir o popover e em intervalo conservador de 60 segundos enquanto conectado, com uma consulta por vez e pausa durante suspensão do Mac. Falhas preservam o último snapshot explicitamente marcado como desatualizado. Respeitar `Retry-After`; não gerar loop de login ou polling agressivo.

Antes de habilitar gravações, fixar schemas v2 e testar validação de perfil, volume, dias, fuso e vínculo do dispositivo. Agendamentos usam o fuso da cafeteira confirmado pela API, com apresentação explícita para evitar confusão com o fuso do Mac. Confirmar se o horário significa início ou café pronto antes de rotular ou liberar a criação.

## Início remoto

A rota existe no pacote Android, mas efeito físico não foi validado nesta sessão. Para disponibilizar o recurso, confirmar firmware e suporte, consultar estado recente e pedir ao usuário confirmação de que preparou água, café e recipiente. Não inferir preparo físico apenas pelos sensores. Falha ou timeout exige releitura e decisão explícita, sem segundo disparo automático. Não usar agendamento próximo como substituto oculto de “iniciar agora”.

## Verificação e definição de pronto

- Compilação e testes de lógica, sessão e transporte aprovados com evidência de execução.
- `.app` local abre, apresenta menubar/janela e permite percorrer estados de demonstração, confirmado visualmente por verificador independente.
- Login, seleção e leitura reais ficam marcados como não verificados até teste com a conta local do usuário. O mesmo vale individualmente para cada gravação.
- Distribuição pública exige README, licença, atribuições, instruções de build, CI macOS e documentação do estado de compatibilidade. Assinatura/notarização exigem configuração própria e não fazem parte da prova local.

Pesquisa e plano aprovados em 2026-10-13, incluindo autenticação e escopo superior a cinco arquivos/100 linhas. Condição de parada da implementação: build, testes e demonstração visual aprovados, fonte publicada; integração física, se indisponível, é declarada como pendência e nunca como concluída.
