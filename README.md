# Fellow Mac

Cliente nativo de menubar pra Fellow Aiden, escrito em SwiftUI. Consulte o estado da cafeteira, perfis e agendamentos pelo Mac. O modo demonstração usa dados fictícios e funciona sem conta ou rede.

Projeto independente, sem afiliação ou endosso da Fellow. A API móvel usada aqui é privada e pode mudar. A integração com uma conta e cafeteira reais ainda precisa de validação. Confira [compatibilidade](docs/compatibility.md) antes de enviar comandos.

## Build local

Você precisa de macOS 14 ou superior e Xcode com Swift 6. O projeto usa apenas frameworks da Apple, sem pacotes externos.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/build-app.sh
open "dist/Fellow Mac.app"
```

Os testes exigem o Xcode completo. O comando acima seleciona o Xcode só para esse processo; ajuste o caminho se a instalação tiver outro nome.

Dois testes de Keychain são opcionais. Para executá-los no seu Mac desbloqueado, use `FELLOW_KEYCHAIN_TESTS=1` junto ao comando de testes. Eles criam entradas isoladas com tokens fictícios e as removem ao terminar.

O script faz o build release pra arquitetura do Mac, monta `dist/Fellow Mac.app` e aplica assinatura ad-hoc. Ele não abre o app nem altera `xcode-select`. O resultado é um bundle local, sem assinatura Developer ID ou notarização. Releases públicas precisam de um processo próprio de assinatura.

## Uso

Abra o app e escolha demonstração ou conecte sua conta Fellow na janela local. O app fica na menubar, sem ícone permanente no Dock. Se houver várias cafeteiras, selecione qual você quer consultar.

Senha é usada no login e descartada. Tokens persistidos ficam no Keychain. O app chama a nuvem da Fellow por HTTPS, sem backend próprio ou analytics. Logout remove a sessão local. Pareamento inicial, Wi-Fi e atualização de firmware continuam no app oficial.

Instant Brew é experimental e vem desativado. O comando usa a receita e quantidade já configuradas na cafeteira. Exige habilitação explícita, firmware compatível, estado recente e confirmação de preparo antes de cada envio. Não há botão de parada remota porque o efeito dessa rota não foi confirmado.

Agendamentos usam o fuso da cafeteira. A Fellow descreve o horário escolhido como café pronto. Confira o resultado no aparelho antes de depender de um agendamento criado pelo Mac.

Para testar os estados sem conta, entre em demonstração e escolha um cenário em Ajustes: pronta, em preparo, sem conexão, sem aparelho, conectando, falha da nuvem ou dados antigos.

## Código e pesquisa

`AidenCore` reúne modelos, transporte HTTP e sessão. `FellowMac` contém SwiftUI, Keychain e demonstração. Testes usam transporte injetável e dados sintéticos.

Leia o [contrato observado](docs/api-contract.md), a [pesquisa](docs/research/2026-10-13-aiden.md) e as [atribuições](THIRD_PARTY_NOTICES.md). A interface tem referências de composição de [Ilter Canberk](https://x.com/icanberk/status/2109031477484937571) e [YuriRDev](https://x.com/YuriRDev/status/2109343577583034661), com desenho próprio. Nenhum asset dessas referências foi incorporado.

Código sob [MIT](LICENSE), copyright 2026 Hugo Doria.
