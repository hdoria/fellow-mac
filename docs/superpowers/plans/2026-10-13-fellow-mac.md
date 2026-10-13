# Fellow Mac: plano de implementação para revisão

Status: aprovado em 2026-10-13; implementação em andamento com API, UI e empacotamento em responsabilidades separadas.

**Objetivo:** entregar um app nativo de menubar para consultar e gerenciar uma Fellow Aiden.
**Arquitetura:** SwiftUI na interface, núcleo Swift testável e HTTPS direto para a nuvem Fellow. Modo demonstração sem rede permite validar interface antes de conectar uma conta.
**Stack:** macOS 14+, Swift 6, SwiftUI, Foundation/URLSession, Security.framework, Swift Package Manager e Xcode.
**Spec:** [desenho](../specs/2026-10-13-fellow-mac-design.md).
**Pesquisa:** [evidências e fontes](../../research/2026-10-13-aiden.md).

## Restrições globais

- Zero dependências de produto inicialmente; não incorporar binários/assets do app oficial.
- Projeto independente; MIT proposta para código próprio, com atribuição e revisão de qualquer código incorporado.
- Tokens apenas no Keychain; senha apenas em memória durante login; logs sem payloads, identificadores ou credenciais.
- Mutações só por ação explícita; sem repetição automática em resposta incerta.
- Demonstração e integração real sempre distinguíveis. Sem simular sucesso de API.
- Estimativa de escopo: 20 a 30 arquivos, acima de 100 linhas; confirmar antes de escrever código de produto.

## Arquivos e responsabilidades previstos

| Caminho relativo ao projeto | Responsabilidade |
| --- | --- |
| `Package.swift` | Executável `FellowMac`, biblioteca `AidenCore` e targets de teste |
| `Sources/AidenCore/Models.swift` | DTOs e tipos de domínio, opcionais onde o contrato permitir |
| `Sources/AidenCore/HTTPTransport.swift` | Requests/responses, timeout, erros sanitizados e transporte substituível |
| `Sources/AidenCore/AidenSession.swift` | Login, refresh serializado, invalidação da sessão |
| `Sources/AidenCore/AidenService.swift` | Dispositivos, perfis, agendamentos e capacidade de início experimental |
| `Sources/AidenCore/BrewerStatus.swift` | Estado derivado e distinção entre telemetria e consulta à nuvem |
| `Sources/FellowMac/FellowMacApp.swift` | Menubar e cenas de janela |
| `Sources/FellowMac/AppModel.swift` | Seleção, carregamento, polling e descarte de tarefas antigas |
| `Sources/FellowMac/KeychainStore.swift` | Armazenamento e remoção de tokens por serviço/conta |
| `Sources/FellowMac/DemoService.swift` | Fixtures sintéticas e demonstração sem rede |
| `Sources/FellowMac/Views/` | Login, popover, janela, perfis, agendamentos e ajustes |
| `Tests/AidenCoreTests/` | Contratos, sessão, transporte, validação e estado |
| `Tests/FellowMacTests/` | Modelo da interface, logout e isolamento do modo demonstração |
| `Resources/Info.plist`, `scripts/build-app.sh` | Bundle `.app`, identificador estável e `LSUIElement` |
| `README.md`, `LICENSE`, `.gitignore`, `.github/workflows/ci.yml` | Uso, licença, exclusões e verificação pública |

## Ordem de execução

### 1. Fixar contratos e casos de erro

- [ ] Criar `Package.swift` com biblioteca `AidenCore`, executável `FellowMac` com entry point mínimo compilável e respectivos targets de teste, usando um teste inicial para verificar descoberta e execução pelo Swift Package Manager.
- [ ] Registrar métodos, caminhos e envelopes v2 observados, com exemplos sintéticos de login, refresh, dispositivos, perfis e agendamentos. Conferir o corpo necessário para cada escrita antes de habilitá-la.
- [ ] Definir `AidenService` como interface assíncrona injetável e `HTTPTransport` sem dependência da UI. Instanciar demo e produção por composição, sem sinalizador que apenas finja sucesso.
- [ ] Escrever testes de decodificação para conta vazia, produtos mistos, duas Aidens, campos ausentes, estado desconhecido e resposta inválida. Rodar os testes falhando antes da implementação.
- [ ] Implementar apenas modelos/transporte necessários e confirmar testes. Fixar limites de payload e duração das requisições.

### 2. Sessão e armazenamento local

- [ ] Testar login rejeitado, 401, refresh concorrente, rotação de refresh token, refresh expirado, 429 com `Retry-After`, timeout e logout durante requisição.
- [ ] Implementar sessão serializada, erros apresentados sem corpo bruto e Keychain com serviço próprio. Não persistir senha nem usar credenciais em arquivos de configuração.
- [ ] Testar remoção de tokens e snapshot no logout, mudança de conta e falha do Keychain. O primeiro login real será feito pelo usuário na interface local.

### 3. Aplicativo e menubar

- [ ] Implementar no executável `FellowMac` o entry point SwiftUI, popover e janela com navegação. Empacotar como `.app` local com `LSUIElement`.
- [ ] Implementar demonstração com estados conectando, sem aparelho, em preparo, erro e dados desatualizados.
- [ ] Implementar polling único de 60 segundos, atualização manual, suspensão/retomada e proteção contra respostas tardias após troca de dispositivo.
- [ ] Testar relógio controlado, cancelamento e isolamento demo/produção. Verificar visualmente menubar, abertura/reabertura da janela, foco de login, seleção entre Aidens e legibilidade em claro/escuro.

### 4. Perfis e agendamentos

- [ ] Adicionar leitura/detalhe, importação por link de host Fellow conhecido e compartilhamento. Não seguir URLs arbitrárias com Authorization.
- [ ] Adicionar consulta, criação, ativação/desativação e exclusão de agendamentos, depois de confirmar esquema e semântica do horário.
- [ ] Testar links inválidos, campos faltantes, resposta vazia, IDs de outro aparelho, volume/dias inválidos, fuso diferente do Mac e transições de horário de verão.
- [ ] Confirmar cada alteração na interface; após escrita, reler do servidor. Timeout apresenta resultado incerto e oferece atualização, sem repetir a gravação.

### 5. Instant Brew experimental

- [ ] Disponibilizar apenas após confirmar contrato e suporte do firmware. Usar a função sem corpo, que aciona o Instant Brew configurado, e explicar isso na confirmação.
- [ ] Testar seleção correta do aparelho, estado desatualizado, comando em andamento, clique duplo, rejeição e resposta perdida. Garantir um único envio por confirmação.
- [ ] Fazer teste físico supervisionado com conta conectada localmente e máquina preparada. Aceitação HTTP é diferente de observar início de preparo.
- [ ] Se não for possível observar o comportamento, manter o recurso indisponível por padrão e documentar pendência; não oferecer parada remota como garantia.

### 6. Revisão, entrega e publicação

- [ ] Executar `swift test`, `swift build -c release` e `scripts/build-app.sh` com evidência guardada. Usar `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` quando necessário.
- [ ] Verificador com contexto limpo testa artefato e rubrica: menubar, navegação, demonstração, exclusão de segredos, concorrência de sessão e ausência de disparos automáticos. Quem implementou não assina sozinho a verificação.
- [ ] Preparar README, licença, atribuições e CI, distinguindo compatibilidade declarada e efetivamente testada. Não anunciar macOS Intel ou macOS 14 como testados apenas por build no host arm64/macOS 27.
- [ ] Inicializar Git e realizar commits convencionais por mudança lógica. Publicar o repositório somente após definir dono/nome e conferir que contém exclusivamente material publicável; push/main conforme regra global quando a entrega estiver aprovada.

## Resultado esperado e limites

Artefato local executável e testado, fonte publicável e mapa explícito de testes reais pendentes. O app não deve ser anunciado como controlador funcional da cafeteira antes da validação de integração. Desenvolvimento pode avançar com demo sem credenciais; a validação física depende de acesso autorizado à conta e ao aparelho.
