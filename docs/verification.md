# Verificação da versão 0.1.0

Data: 2026-10-13. Código do app: `a6c0c7e5368ac8fa966d9c98d1406cedff58c5e9`. Mudanças posteriores de documentação e CI não alteram esse código.

## Testes locais

Comando executado por verificador separado da implementação:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
FELLOW_KEYCHAIN_TESTS=1 \
swift test --scratch-path /tmp/fellow-final-review-build
```

Resultado: 48 testes aprovados, zero falhas e zero ignorados. São 30 testes de núcleo, 16 de estado da interface e 2 do Keychain. Entradas do Keychain usaram identificadores exclusivos e tokens fictícios, removidos ao terminar.

O comando `./scripts/build-app.sh` compilou o executável release, montou o bundle, validou o plist e verificou a assinatura ad-hoc. Host: Apple Silicon, macOS 27.0.1, Xcode 27.0, Swift 6.4.

## CI

A [execução do código do app](https://github.com/hdoria/fellow-mac/actions/runs/38399207787) passou com Swift 6.1.2 em arm64/macOS 15. Foram 46 testes aprovados e dois testes opcionais de Keychain ignorados, seguidos pelo build release do bundle.

## Interface nativa

Outro verificador abriu o bundle local e usou somente demonstração:

- Login e páginas Estado, Perfis, Agendamentos e Ajustes legíveis.
- Expansão de detalhes de perfil.
- Criação, pausa e remoção de agendamento, com atualização da lista.
- Dados antigos e falha da nuvem preservam o último estado, mostram aviso e impedem início.
- Início simulado pede confirmação e muda o estado para preparo.
- Ao terminar, demonstração pronta e recurso experimental desabilitado.

A [captura do app](screenshots/demo.png) é real, sem edição, com dados simulados. A automação não expôs o item de status da menubar. Ao fechar a janela, a próxima leitura a reabriu; isso não comprova interação manual com o popover ou o ciclo completo de fechar/reabrir.

## Pendências

- Login, renovação e cada operação na nuvem com uma conta real.
- Observação física do efeito de perfis, agendamentos e Instant Brew.
- Agendamento durante transições de horário de verão no firmware.
- Acesso manual ao popover pela menubar e ciclo de janelas.
- Execução no macOS 14, Intel, assinatura Developer ID e notarização.

O cliente mantém Instant Brew desabilitado por padrão. Aceitação HTTP não equivale a início físico do preparo.
