# Port KDE Plasma 6 - Frigate Viewer

Port completo do plugin Frigate Viewer (Noctalia/niri) para um plasmoid nativo do KDE Plasma 6.

## Estrutura

- `port-kde-plasma6/PLANO_PORT_KDE_PLASMA6.md`: plano macro de port.
- `port-kde-plasma6/PORT_BASELINE.md`: baseline de paridade funcional (F01..F20).
- `port-kde-plasma6/TEST_MATRIX.md`: matriz de testes T01..T10.
- `port-kde-plasma6/EXECUTION_STATUS.md`: status final das fases do plano.
- `port-kde-plasma6/package/`: pacote do plasmoid.
- `port-kde-plasma6/scripts/install-local.sh`: instala/atualiza no usuario local.
- `port-kde-plasma6/scripts/uninstall-local.sh`: remove do usuario local.

## Instalacao local

```bash
./port-kde-plasma6/scripts/install-local.sh
```

Depois, no Plasma: `Adicionar Widgets` -> `Frigate Viewer`.

## Remocao

```bash
./port-kde-plasma6/scripts/uninstall-local.sh
```

## ID do widget

- `com.noctalia.frigateviewer`

