.pragma library

// Shared i18n helper for the Frigate Viewer plugin.
// Single source of truth for translation lookup, missing-key fallback,
// and {placeholder} interpolation. Imported by every QML entry point as:
//
//   import "Translation.js" as Translation
//   function tr(key, params) { return Translation.tr(pluginApi, key, params) }
//
// tr(pluginApi, key)         -> looked-up string, or `key` if missing
// tr(pluginApi, key, params) -> same, with {name} tokens replaced from params

function tr(pluginApi, key, params) {
    var value = (pluginApi && typeof pluginApi.tr === "function")
        ? pluginApi.tr(key)
        : undefined

    if (value === undefined || value === null) {
        value = key
    }
    value = String(value)

    // Noctalia marks an untranslated key as !!key!! -- fall back to the key.
    if (/^!!.*!!$/.test(value)) {
        value = key
    }

    if (!params) {
        return value
    }

    return value.replace(/\{([a-zA-Z0-9_]+)\}/g, function (match, name) {
        if (Object.prototype.hasOwnProperty.call(params, name)) {
            return String(params[name])
        }
        return match
    })
}
