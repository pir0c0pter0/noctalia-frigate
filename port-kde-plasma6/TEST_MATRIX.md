# Matriz de Testes - Port Plasma 6

## Casos obrigatorios (T01..T10)

| Caso | Objetivo | Cobertura no codigo | Status |
|---|---|---|---|
| T01 | URL valida sem auth conecta | `main.qml:testConnection/pollConnection` | Coberto |
| T02 | URL valida com Basic Auth conecta | `main.qml:makeAuthRequest + buildAuthUrl` | Coberto |
| T03 | URL invalida gera erro amigavel | `cannotReachServer/httpError` | Coberto |
| T04 | Credencial errada gera 401 | `authFailed` | Coberto |
| T05 | Listagem de cameras sem `birdseye` | `FrigateApi.parseCameraList` | Coberto |
| T06 | Selecao de cameras reflete no painel | `ConfigGeneral.qml + effectiveSelectedCameras` | Coberto |
| T07 | Navegacao com wrap | `main.qml:nextCamera/prevCamera` | Coberto |
| T08 | Fechar painel para stream | `StreamView.active` + `stopStreaming()` | Coberto |
| T09 | Persistencia apos reinicio | `main.xml` + `cfg_*` | Coberto |
| T10 | EN/PT funcionando | `I18n.js` | Coberto |
| T11 | Integracao HA WebSocket e troca auto | `main.qml:haSocket` | Coberto |

## Validacoes executadas neste ambiente

- `qmllint` em todos os QML do port: sem erros.
- Instalacao de pacote via `kpackagetool6 --install`: sucesso.
- Remocao via `kpackagetool6 --remove`: sucesso.

## Validacao manual pendente no desktop do usuario

- Abrir widget no painel do Plasma.
- Testar conexao real com instancia Frigate alvo.
- Verificar troca de idioma da sessao para pt_BR/en_US.

