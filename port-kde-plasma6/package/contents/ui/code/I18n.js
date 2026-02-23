.pragma library

var STRINGS = {
    en: {
        frigateViewerTitle: "Frigate Viewer",
        tooltipConnected: "Connected",
        tooltipDisconnected: "Disconnected",
        statusConnected: "Frigate is reachable",
        statusDisconnected: "Frigate is offline",
        noCamerasConfigured: "No cameras configured. Open settings and list cameras.",
        noCameraSelected: "No camera selected",
        loadingStream: "Loading stream...",
        streamError: "Stream unavailable. Check your connection.",
        frigateOffline: "Frigate is offline. Check server status and settings.",
        previewHint: "Preview mode (1 fps). Click the image for live mode.",
        liveHint: "Live mode active. Click the image to return to preview.",
        previewModeChip: "Preview 1 FPS",
        liveModeChip: "Live MJPEG",
        testConnection: "Test Connection",
        settings: "Settings",
        save: "Save",
        saved: "Saved!",
        listCameras: "List Cameras",
        frigateConnection: "Frigate Connection",
        frigateServerUrl: "Frigate Server URL",
        usernameOptional: "Username (optional)",
        passwordOptional: "Password (optional)",
        leaveBlankIfNoAuth: "Leave blank if no auth",
        cameraSelection: "Camera Selection",
        selectCamerasHint: "Select which cameras appear in the viewer panel:",
        camerasSelected: "{count} camera(s) selected",
        noUrlConfigured: "No Frigate URL configured",
        testing: "Testing...",
        connectedVersion: "Connected! Frigate v{version}",
        fetchCamerasFailed: "Failed to fetch cameras: {error}",
        authFailed: "Authentication failed (401). Check credentials. Frigate native JWT auth may require reverse proxy Basic Auth.",
        cannotReachServer: "Cannot reach server. Check URL and whether Frigate is running.",
        httpError: "HTTP {status}: {statusText}",
        credentialsWarning: "Credentials are stored locally. Prefer a dedicated Frigate user with limited permissions.",
        about: "About",
        developedBy: "Developed by pir0c0pter0",
        version: "Version {version}",
        applyCloseHint: "Tip: use Apply/OK to persist configuration in Plasma dialogs.",
        enableHaDetection: "Enable Home Assistant Detection",
        haEnable: "Enable",
        haWsUrl: "HA WebSocket URL",
        haToken: "HA Access Token",
        haTokenPlaceholder: "Paste your Long-Lived Access Token"
    },
    pt: {
        frigateViewerTitle: "Visualizador Frigate",
        tooltipConnected: "Conectado",
        tooltipDisconnected: "Desconectado",
        statusConnected: "Frigate acessivel",
        statusDisconnected: "Frigate offline",
        noCamerasConfigured: "Nenhuma camera configurada. Abra as configuracoes e liste as cameras.",
        noCameraSelected: "Nenhuma camera selecionada",
        loadingStream: "Carregando stream...",
        streamError: "Stream indisponivel. Verifique sua conexao.",
        frigateOffline: "Frigate esta offline. Verifique servidor e configuracoes.",
        previewHint: "Modo preview (1 fps). Clique na imagem para modo ao vivo.",
        liveHint: "Modo ao vivo ativo. Clique na imagem para voltar ao preview.",
        previewModeChip: "Preview 1 FPS",
        liveModeChip: "Ao vivo MJPEG",
        testConnection: "Testar Conexao",
        settings: "Configuracoes",
        save: "Salvar",
        saved: "Salvo!",
        listCameras: "Listar Cameras",
        frigateConnection: "Conexao Frigate",
        frigateServerUrl: "URL do Servidor Frigate",
        usernameOptional: "Usuario (opcional)",
        passwordOptional: "Senha (opcional)",
        leaveBlankIfNoAuth: "Deixe em branco se nao usar autenticacao",
        cameraSelection: "Selecao de Cameras",
        selectCamerasHint: "Selecione quais cameras aparecem no painel:",
        camerasSelected: "{count} camera(s) selecionada(s)",
        noUrlConfigured: "URL do Frigate nao configurada",
        testing: "Testando...",
        connectedVersion: "Conectado! Frigate v{version}",
        fetchCamerasFailed: "Falha ao buscar cameras: {error}",
        authFailed: "Autenticacao falhou (401). Verifique credenciais. Auth JWT nativo do Frigate pode exigir proxy com Basic Auth.",
        cannotReachServer: "Nao foi possivel conectar ao servidor. Verifique a URL e se o Frigate esta rodando.",
        httpError: "HTTP {status}: {statusText}",
        credentialsWarning: "Credenciais sao armazenadas localmente. Prefira um usuario dedicado do Frigate com permissoes limitadas.",
        about: "Sobre",
        developedBy: "Desenvolvido por pir0c0pter0",
        version: "Versao {version}",
        applyCloseHint: "Dica: use Aplicar/OK para persistir configuracoes no Plasma.",
        enableHaDetection: "Ativar Deteccao do Home Assistant",
        haEnable: "Ativar",
        haWsUrl: "URL WebSocket do HA",
        haToken: "Token de Acesso do HA",
        haTokenPlaceholder: "Cole seu Token de Acesso de Longa Duracao"
    }
}

function languageFromLocale(localeName) {
    var value = String(localeName || "en_US").toLowerCase()
    if (value.indexOf("pt") === 0) {
        return "pt"
    }
    return "en"
}

function interpolate(template, params) {
    var text = String(template || "")
    if (!params) {
        return text
    }

    return text.replace(/\{([a-zA-Z0-9_]+)\}/g, function(match, key) {
        if (Object.prototype.hasOwnProperty.call(params, key)) {
            return String(params[key])
        }
        return match
    })
}

function tr(localeName, key, params) {
    var lang = languageFromLocale(localeName)
    var byLang = STRINGS[lang] || STRINGS.en
    var raw = byLang[key]
    if (raw === undefined) {
        raw = STRINGS.en[key]
    }
    if (raw === undefined) {
        raw = key
    }
    return interpolate(raw, params)
}
