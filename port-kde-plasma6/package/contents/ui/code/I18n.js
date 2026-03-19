.pragma library

var STRINGS = {
    en: {
        general: "General",
        frigateViewerTitle: "Frigate Viewer",
        statusConnected: "Frigate is reachable",
        statusDisconnected: "Frigate is offline",
        connected: "Connected",
        disconnected: "Disconnected",
        noCamerasConfigured: "No cameras configured. Open settings and list cameras.",
        noCameraSelected: "No camera selected",
        streamError: "Stream unavailable. Check your connection.",
        frigateOffline: "Frigate is offline. Check server status and settings.",
        previewHint: "Preview mode (1 fps). Click the image for live mode.",
        liveHint: "Live mode active. Click the image to return to preview.",
        previewModeChip: "Preview 1 FPS",
        liveModeChip: "Live MJPEG",
        liveMjpegStream: "Live MJPEG Stream",
        frameSingular: "{count} frame",
        framePlural: "{count} frames",
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
        cameraSelectedSingular: "{count} camera selected",
        cameraSelectedPlural: "{count} cameras selected",
        defaultCamera: "Default Camera",
        defaultCameraHint: "This camera opens first when you click the widget icon.",
        noUrlConfigured: "No Frigate URL configured",
        testing: "Testing...",
        connectedVersion: "Connected! Frigate v{version}",
        fetchCamerasFailed: "Failed to fetch cameras: {error}",
        authFailed: "Authentication failed (401). Check credentials.",
        cannotReachServer: "Cannot reach server. Check URL and whether Frigate is running.",
        httpError: "HTTP {status}: {statusText}",
        credentialsWarning: "Credentials are stored locally. Prefer a dedicated Frigate user with limited permissions.",
        homeAssistant: "Home Assistant",
        enableHaDetection: "Enable Home Assistant Detection",
        enable: "Enable",
        haWsUrl: "HA WebSocket URL",
        haToken: "HA Access Token",
        haTokenPlaceholder: "Paste your Long-Lived Access Token",
        haEventType: "HA Event Type",
        about: "About",
        developedBy: "Developed by pir0c0pter0",
        version: "Version {version}",
        applyCloseHint: "Tip: use Apply/OK to persist configuration in Plasma dialogs."
    },
    pt: {
        general: "Geral",
        frigateViewerTitle: "Visualizador Frigate",
        statusConnected: "Frigate acessivel",
        statusDisconnected: "Frigate offline",
        connected: "Conectado",
        disconnected: "Desconectado",
        noCamerasConfigured: "Nenhuma camera configurada. Abra as configuracoes e liste as cameras.",
        noCameraSelected: "Nenhuma camera selecionada",
        streamError: "Stream indisponivel. Verifique sua conexao.",
        frigateOffline: "Frigate esta offline. Verifique servidor e configuracoes.",
        previewHint: "Modo preview (1 fps). Clique na imagem para modo ao vivo.",
        liveHint: "Modo ao vivo ativo. Clique na imagem para voltar ao preview.",
        previewModeChip: "Preview 1 FPS",
        liveModeChip: "Ao vivo MJPEG",
        liveMjpegStream: "Stream MJPEG ao vivo",
        frameSingular: "{count} frame",
        framePlural: "{count} frames",
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
        cameraSelectedSingular: "{count} camera selecionada",
        cameraSelectedPlural: "{count} cameras selecionadas",
        defaultCamera: "Camera padrao",
        defaultCameraHint: "Esta camera abre primeiro quando voce clica no icone do widget.",
        noUrlConfigured: "URL do Frigate nao configurada",
        testing: "Testando...",
        connectedVersion: "Conectado! Frigate v{version}",
        fetchCamerasFailed: "Falha ao buscar cameras: {error}",
        authFailed: "Autenticacao falhou (401). Verifique credenciais.",
        cannotReachServer: "Nao foi possivel conectar ao servidor. Verifique a URL e se o Frigate esta rodando.",
        httpError: "HTTP {status}: {statusText}",
        credentialsWarning: "Credenciais sao armazenadas localmente. Prefira um usuario dedicado do Frigate com permissoes limitadas.",
        homeAssistant: "Home Assistant",
        enableHaDetection: "Ativar Deteccao do Home Assistant",
        enable: "Ativar",
        haWsUrl: "URL WebSocket do HA",
        haToken: "Token de Acesso do HA",
        haTokenPlaceholder: "Cole seu Token de Acesso de Longa Duracao",
        haEventType: "Tipo de Evento do HA",
        about: "Sobre",
        developedBy: "Desenvolvido por pir0c0pter0",
        version: "Versao {version}",
        applyCloseHint: "Dica: use Aplicar/OK para persistir configuracoes no dialogo do Plasma."
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

function trCount(localeName, singularKey, pluralKey, count, params) {
    var data = params ? Object.assign({}, params) : {}
    if (!Object.prototype.hasOwnProperty.call(data, "count")) {
        data.count = count
    }
    var key = Number(count) === 1 ? singularKey : pluralKey
    return tr(localeName, key, data)
}
