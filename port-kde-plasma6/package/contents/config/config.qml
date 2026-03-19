import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.configuration

import "../ui/code/I18n.js" as I18n

ConfigModel {
    ConfigCategory {
        name: I18n.tr(Qt.locale().name, "general")
        icon: "settings-configure"
        source: "config/ConfigGeneral.qml"
    }
}
