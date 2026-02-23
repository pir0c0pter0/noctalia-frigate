# Baseline de Paridade - Port Plasma 6

Escopo de paridade funcional entre plugin original (Noctalia/niri) e port KDE Plasma 6.

## Funcoes obrigatorias (F01..F20)

| ID | Funcao | Status no port |
|---|---|---|
| F01 | Configurar URL do Frigate | Concluido |
| F02 | Configurar usuario/senha (Basic Auth) | Concluido |
| F03 | Persistir configuracoes | Concluido |
| F04 | Testar conexao (`/api/version`) | Concluido |
| F05 | Descobrir cameras (`/api/config`) | Concluido |
| F06 | Selecionar cameras | Concluido |
| F07 | Persistir cameras selecionadas e ordem | Concluido |
| F08 | Polling de conexao (30s) | Concluido |
| F09 | Icone de camera na barra | Concluido |
| F10 | Dot de status conectado/desconectado | Concluido |
| F11 | Tooltip de status | Concluido |
| F12 | Clique esquerdo abre/fecha painel | Concluido |
| F13 | Menu de contexto com Testar/Configuracoes | Concluido |
| F14 | Header com camera atual | Concluido |
| F15 | Navegacao anterior/proxima com wrap | Concluido |
| F16 | Stream por snapshots `latest.jpg` | Concluido |
| F17 | Retry de stream em erro | Concluido |
| F18 | Stop stream ao fechar painel | Concluido |
| F19 | i18n EN/PT | Concluido |
| F20 | Bloco About com versao | Concluido |

## Artefatos de implementacao

- `port-kde-plasma6/package/contents/ui/main.qml`
- `port-kde-plasma6/package/contents/ui/CompactRepresentation.qml`
- `port-kde-plasma6/package/contents/ui/FullRepresentation.qml`
- `port-kde-plasma6/package/contents/ui/components/StreamView.qml`
- `port-kde-plasma6/package/contents/ui/config/ConfigGeneral.qml`
- `port-kde-plasma6/package/contents/config/main.xml`
- `port-kde-plasma6/package/contents/config/config.qml`

