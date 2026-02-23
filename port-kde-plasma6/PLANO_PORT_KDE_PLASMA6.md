# Plano Completo de Port: Frigate Viewer -> KDE Plasma 6

## 1. Objetivo

Portar o plugin atual (Noctalia Shell sobre niri) para **KDE Plasma 6** mantendo paridade funcional total, com UX equivalente:

- ícone na barra;
- status de conexão;
- painel flutuante com stream e navegação de câmeras;
- configurações (URL, auth, teste, descoberta, seleção);
- persistência;
- i18n EN/PT.

## 2. Evidências e Escopo Atual (base no código)

Arquivos analisados:

- `Main.qml`
- `BarWidget.qml`
- `Panel.qml`
- `Settings.qml`
- `manifest.json`
- `i18n/en.json`
- `i18n/pt.json`

Funcionalidades observadas no plugin atual:

| ID | Função atual | Origem atual | Observação de port |
|---|---|---|---|
| F01 | Configurar URL do Frigate | `Settings.qml` | Migrar para `plasmoid.configuration.frigateUrl` |
| F02 | Configurar usuário/senha (Basic Auth) | `Settings.qml` | Migrar para configuração do widget |
| F03 | Salvar e persistir settings | `pluginApi.saveSettings()` | Migrar para KConfig do Plasma (`main.xml`) |
| F04 | Testar conexão (`/api/version`) | `Main.qml::testConnection()` | Manter com `XMLHttpRequest` |
| F05 | Descobrir câmeras (`/api/config`) | `Main.qml::fetchCameras()` | Manter parser + filtro `birdseye` |
| F06 | Selecionar câmeras por checkbox | `Settings.qml` | Migrar para página de configuração |
| F07 | Persistir câmeras selecionadas e ordem | `Settings.qml` | Manter em `StringList` de configuração |
| F08 | Polling de conexão (30s) | `Main.qml::Timer` | Manter timer no applet root |
| F09 | Ícone de câmera na barra | `BarWidget.qml` | Migrar para `compactRepresentation` |
| F10 | Dot verde/vermelho conectado/desconectado | `BarWidget.qml` | Manter na compact view |
| F11 | Tooltip conectado/desconectado | `BarWidget.qml` | Migrar para tooltip do Plasmoid |
| F12 | Clique esquerdo abre/fecha painel | `BarWidget.qml` | Mapear para `plasmoid.expanded` |
| F13 | Clique direito com menu (Testar/Config) | `BarWidget.qml` | Mapear para `contextualActions` |
| F14 | Header com nome da câmera atual | `Panel.qml` | Manter em `fullRepresentation` |
| F15 | Navegação anterior/próxima com wrap-around | `Main.qml` + `Panel.qml` | Manter funções de índice |
| F16 | Stream por snapshot contínuo (`latest.jpg`) | `Panel.qml` | Manter estratégia inicial para paridade |
| F17 | Retry em erro de stream | `Panel.qml::retryTimer` | Manter backoff simples |
| F18 | Parar stream ao fechar painel | `Panel.qml::onVisibleChanged` | Manter para CPU/rede |
| F19 | i18n inglês/português | `i18n/*.json` | Migrar para i18n do KDE (gettext) |
| F20 | Exibir versão no About | `Settings.qml` | Manter na página de config |

## 3. Análise Multi-Perspectiva

**Modo:** balanced (5 perspectivas)  
**Confiança geral:** MEDIUM-HIGH

### Arquiteto

- Melhor estrutura: um único applet Plasma com estado central + componentes UI separados.
- Reduz risco de regressão se `Main.qml` virar camada de domínio (API, estado, timers) e as views só consumirem estado.
- Recomenda separar lógica em módulos JS/QML (`core/FrigateApi.js`, `core/StateController.qml`).

### Planner

- Estratégia ideal: **paridade primeiro**, otimizações depois.
- Fases curtas com critérios de aceite por função (F01..F20).
- Entrega incremental: esqueleto -> config -> conexão -> compact view -> full view -> i18n -> hardening.

### Segurança

- Risco principal: senha em texto claro em configuração local (equivalente ao plugin atual).
- Mitigação de curto prazo: aviso explícito no UI e recomendação de usuário Frigate dedicado.
- Mitigação opcional pós-paridade: integração com KWallet/Secret Service.
- Manter `encodeURIComponent` para credenciais em URL de stream.

### Qualidade de Código

- Evitar lógica duplicada entre compact/full/config.
- Centralizar mensagens de erro e mapeamento HTTP.
- Cobrir parser de câmeras, builder de URL e navegação circular com testes de unidade (Qt Quick Test).

### Criativo

- Para preservar estabilidade, manter snapshot streaming inicial (com double-buffer), e deixar MJPEG puro como melhoria opcional.
- Adicionar modo diagnóstico simples (frame counter opcional) via flag de debug para facilitar suporte.

### Síntese (recomendação única)

Executar o port em duas trilhas:

1. **Trilha de paridade obrigatória (F01..F20)** sem mudanças de comportamento.
2. **Trilha opcional pós-paridade** (KWallet, fallback MJPEG/snapshot configurável, melhorias visuais).

Isso minimiza risco, mantém prazo controlado e garante entrega funcional no Plasma 6.

## 4. Arquitetura Alvo no Plasma 6

Estrutura de pacote proposta:

```text
port-kde-plasma6/
  package/
    metadata.json
    contents/
      ui/
        main.qml
        CompactRepresentation.qml
        FullRepresentation.qml
        components/
          StatusDot.qml
          CameraHeader.qml
          StreamView.qml
      config/
        config.qml
        main.xml
        ConfigGeneral.qml
      code/
        FrigateApi.js
        StreamController.js
      locale/
        pt_BR/LC_MESSAGES/frigateviewer.po
        en/LC_MESSAGES/frigateviewer.po
```

Mapeamento de APIs Noctalia -> Plasma 6:

| Noctalia atual | Plasma 6 equivalente |
|---|---|
| `pluginApi.pluginSettings` | `plasmoid.configuration.*` |
| `pluginApi.saveSettings()` | Persistência automática KConfig |
| `pluginApi.mainInstance` | Estado no `main.qml` (id root) + bindings |
| `pluginApi.togglePanel(...)` | `plasmoid.expanded = !plasmoid.expanded` |
| `BarWidget.qml` | `compactRepresentation` |
| `Panel.qml` | `fullRepresentation` |
| `TooltipService.show(...)` | propriedades de tooltip do Plasmoid |
| Menu de contexto custom | `Plasmoid.contextualActions` |
| `pluginApi.tr(...)` + JSON i18n | `i18n(...)` com catálogo gettext |

## 5. Plano de Execução por Fases

## Fase 0: Preparação e Baseline

Objetivo:

- travar baseline funcional atual;
- preparar pasta do port e checklist de paridade.

Tarefas:

- congelar matriz F01..F20;
- registrar cenários de teste reais (sem auth, auth, offline, 401, HTTPS);
- remover credenciais reais de artefatos de desenvolvimento e criar arquivo de exemplo.

Saídas:

- `PORT_BASELINE.md` com critérios de aceite por função.

DoD:

- matriz aprovada e sem ambiguidades funcionais.

## Fase 1: Esqueleto do Plasmoid Plasma 6

Objetivo:

- criar pacote instalável mínimo.

Tarefas:

- `metadata.json` com plugin id e metadados;
- `contents/ui/main.qml` com estado raiz;
- compact/full placeholders;
- configuração inicial (`contents/config/config.qml`, `main.xml`, `ConfigGeneral.qml`).

Saídas:

- pacote instalável via `kpackagetool6`.

DoD:

- widget carrega no Plasma sem erros de import.

## Fase 2: Camada de Configuração (F01, F02, F03, F20)

Objetivo:

- migrar settings completos para a UI de configuração do Plasma.

Tarefas:

- campos URL/usuário/senha;
- persistência via `cfg_*` + `main.xml`;
- seção About com versão;
- normalização de URL (`remove trailing slash`).

Saídas:

- Configuração funcional e persistente.

DoD:

- reiniciar sessão Plasma mantém todos os valores.

## Fase 3: Camada Frigate API e Estado (F04, F05, F07, F08)

Objetivo:

- portar lógica de API e estado central.

Tarefas:

- implementar `makeAuthRequest`, `testConnection`, `fetchCameras`, `pollConnection`;
- timer de 30s;
- filtro `birdseye`;
- mensagens de erro equivalentes.

Saídas:

- estado de conexão e lista de câmeras atualizados.

DoD:

- teste manual: conectar, listar câmeras, simular offline.

## Fase 4: Compact Representation (barra) (F09, F10, F11, F12, F13)

Objetivo:

- reproduzir experiência da barra.

Tarefas:

- ícone de câmera e status dot;
- tooltip dinâmico;
- clique esquerdo abre/fecha popup;
- ações de contexto: "Testar Conexão" e "Configurações".

Saídas:

- interação completa na barra equivalente ao plugin atual.

DoD:

- parity UX confirmada para connected/disconnected.

## Fase 5: Full Representation (painel) (F14, F15, F16, F17, F18)

Objetivo:

- migrar visualizador de câmeras com navegação.

Tarefas:

- header com nome atual;
- botões anterior/próximo;
- stream por snapshot contínuo com double-buffer;
- retry timer em erro;
- start/stop stream conforme `plasmoid.expanded`.

Saídas:

- painel funcional com alternância de câmeras.

DoD:

- abrir/fechar repetidamente sem vazamento perceptível e sem stream em segundo plano.

## Fase 6: i18n KDE (F19)

Objetivo:

- garantir EN/PT com sistema de tradução do KDE.

Tarefas:

- migrar strings para `i18n(...)`;
- criar catálogo EN/PT;
- validar troca de idioma da sessão.

Saídas:

- traduções completas sem regressão.

DoD:

- todas as strings de UI passam por i18n.

## Fase 7: Qualidade, Segurança e Performance

Objetivo:

- endurecer comportamento antes de release.

Tarefas:

- testes de regressão F01..F20;
- tratamento de casos: 401, 404, URL inválida, sem câmeras;
- validação com senha contendo caracteres especiais;
- avaliação de CPU/rede com painel aberto/fechado.

Saídas:

- relatório de validação e issues remanescentes.

DoD:

- zero regressão crítica de função.

## Fase 8: Empacotamento e Entrega

Objetivo:

- finalizar pacote pronto para instalação.

Tarefas:

- documentação de instalação;
- pacote com versão semântica inicial (`0.1.0-port` ou `1.0.0-plasma6`);
- notas de compatibilidade (limitação de auth nativa JWT do Frigate quando aplicável).

Saídas:

- release candidate do plasmoid.

DoD:

- instalação limpa em ambiente Plasma 6.

## 6. Matriz de Testes de Paridade (mínima obrigatória)

| Caso | Entrada | Resultado esperado |
|---|---|---|
| T01 | URL válida sem auth | Conecta e mostra status verde |
| T02 | URL válida com Basic Auth em proxy | Conecta e stream funciona |
| T03 | URL inválida | Erro amigável + status vermelho |
| T04 | Credencial errada | Mensagem 401 |
| T05 | Listar câmeras | Lista populada sem `birdseye` |
| T06 | Selecionar/desselecionar câmeras | Painel reflete seleção imediatamente |
| T07 | Navegar com 2+ câmeras | Wrap-around correto |
| T08 | Fechar painel | Stream para e tráfego reduz |
| T09 | Reiniciar Plasma | Settings e seleção persistem |
| T10 | Idioma pt_BR/en_US | Textos corretos em ambos |

## 7. Riscos e Mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Mudanças de API entre Noctalia e Plasma | Alto | Isolar domínio Frigate da UI desde o início |
| Auth do Frigate nativo (JWT) não compatível com fluxo Basic | Alto | Documentar limitação e recomendar proxy Basic Auth |
| Credenciais em texto claro | Médio | Aviso no UI + opção futura KWallet |
| Congelamento/erro de stream | Médio | Retry timer + restart controlado + fallback |
| Regressão de i18n | Médio | checklist de strings obrigatória antes da release |

## 8. Estimativa de Execução

- Fase 0: 0.5 dia
- Fase 1: 0.5 dia
- Fase 2: 1.0 dia
- Fase 3: 1.0 dia
- Fase 4: 1.0 dia
- Fase 5: 1.5 dia
- Fase 6: 0.5 dia
- Fase 7: 1.0 dia
- Fase 8: 0.5 dia

**Total estimado:** 7.5 dias úteis (incluindo validação manual).

## 9. Critérios de Conclusão do Port

O port para Plasma 6 será considerado concluído somente quando:

- todas as funções F01..F20 estiverem entregues;
- matriz T01..T10 estiver aprovada;
- instalação limpa do pacote funcionar;
- documentação de uso/configuração estiver pronta.

## 10. Referências Técnicas (KDE/Qt)

- Plasma 6 Plasmoids Getting Started: <https://develop.kde.org/docs/plasma/widget/>
- Estrutura de pacote e UI files: <https://develop.kde.org/docs/plasma/widget/setup/>
- Configuração/KCM para widget: <https://develop.kde.org/docs/plasma/widget/configuration/>
- Tutorial de Hello World plasmoid: <https://develop.kde.org/docs/plasma/widget/plasma6/>
- Referência de API Applet/Plasmoid (Plasma QML): <https://api.kde.org/legacy/plasma/plasma-framework/html/classPlasma_1_1Applet.html>
- Qt Quick `Image` (stream/snapshot rendering constraints): <https://doc.qt.io/qt-6/qml-qtquick-image.html>

