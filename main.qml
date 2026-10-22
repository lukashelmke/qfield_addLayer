import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.qfield
import org.qgis
import Theme

/**
 * Neuer Layer – QField-Plugin
 *
 * Legt direkt in QField einen neuen, leeren Vektorlayer an (GeoPackage),
 * fügt ihn dem offenen Projekt hinzu und lädt ihn bei jedem erneuten Öffnen
 * des Projekts automatisch wieder.
 *
 * Speicherort: <QField-Dokumente>/Imported Datasets/Feldlayer/<Projektname>/<Layer>.gpkg
 * Bewusst außerhalb des Projektordners, damit QFieldCloud-Updates oder das
 * Entfernen eines Cloud-Projekts die Daten nicht löschen.
 */
Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var dashBoard: iface.findItemByObjectName('dashBoard')

  readonly property string settingsPrefix: "neuerLayerPlugin/"

  // QMetaType-IDs, wie von FeatureUtils.createField erwartet
  readonly property var fieldTypes: [
    { label: qsTr("Text"),         type: 10 },  // QString
    { label: qsTr("Ganzzahl"),     type: 2 },   // Int
    { label: qsTr("Dezimalzahl"),  type: 6 },   // Double
    { label: qsTr("Ja/Nein"),      type: 1 },   // Bool
    { label: qsTr("Datum"),        type: 14 },  // QDate
    { label: qsTr("Datum + Zeit"), type: 16 }   // QDateTime
  ]

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(newLayerButton)
    restoreLayers()
  }

  Connections {
    target: iface
    function onLoadProjectEnded(path, name) {
      plugin.restoreLayers()
    }
  }

  // ---------------------------------------------------------------------------
  // Hilfsfunktionen
  // ---------------------------------------------------------------------------

  function toast(message, type) {
    mainWindow.displayToast(message, type === undefined ? 'info' : type)
  }

  function projectKey() {
    const fileName = qgisProject.fileName
    return fileName ? settingsPrefix + fileName : ""
  }

  function projectBaseName() {
    const name = FileUtils.fileName(qgisProject.fileName, false)
    return FileUtils.sanitizeFilePathPart(name !== "" ? name : "projekt")
  }

  function storageDirectory() {
    return platformUtilities.applicationDirectory() + "/Imported Datasets/Feldlayer/" + projectBaseName()
  }

  function loadRegistry() {
    const key = projectKey()
    if (key === "")
      return []
    try {
      const raw = settings.value(key, "[]")
      const list = JSON.parse(raw)
      return Array.isArray(list) ? list : []
    } catch (e) {
      return []
    }
  }

  function saveRegistry(list) {
    const key = projectKey()
    if (key === "")
      return
    settings.setValue(key, JSON.stringify(list))
    settings.sync()
  }

  function isLayerLoaded(path) {
    const layers = ProjectUtils.mapLayers(qgisProject)
    for (const id in layers) {
      const layer = layers[id]
      if (layer && layer.customProperty("neuerLayer/path", "") === path)
        return true
    }
    return false
  }

  function addLayerToProject(entry) {
    const uri = entry.path + "|layername=" + entry.layerName
    const layer = LayerUtils.loadVectorLayer(uri, entry.name, "ogr")
    if (!layer || !layer.isValid) {
      return null
    }
    // Markierung für die Wiedererkennung
    layer.setCustomProperty("neuerLayer/path", entry.path)
    // Nicht von QFieldCloud als Cloud-Layer behandeln (der Server kennt ihn nicht)
    layer.setCustomProperty("QFieldSync/cloud_action", "no_action")
    if (!ProjectUtils.addMapLayer(qgisProject, layer)) {
      return null
    }
    return layer
  }

  function restoreLayers() {
    if (!qgisProject.fileName)
      return
    const entries = loadRegistry()
    let restored = 0
    let missing = 0
    for (const entry of entries) {
      if (!FileUtils.fileExists(entry.path)) {
        missing++
        continue
      }
      if (isLayerLoaded(entry.path))
        continue
      if (addLayerToProject(entry))
        restored++
    }
    if (missing > 0) {
      toast(qsTr("%1 Feldlayer nicht mehr gefunden").arg(missing), 'warning')
    }
    layerListModel.refresh()
  }

  function createLayer() {
    if (!qgisProject.fileName) {
      toast(qsTr("Bitte zuerst ein Projekt öffnen"), 'warning')
      return false
    }

    const displayName = layerNameField.text.trim()
    if (displayName === "") {
      toast(qsTr("Bitte einen Layernamen eingeben"), 'warning')
      return false
    }
    const fileBase = FileUtils.sanitizeFilePathPart(displayName.replace(/\s+/g, "_"))
    const path = storageDirectory() + "/" + fileBase + ".gpkg"
    if (FileUtils.fileExists(path)) {
      toast(qsTr("Ein Feldlayer mit diesem Namen existiert bereits"), 'warning')
      return false
    }

    // Felder einsammeln
    const fieldList = []
    const usedNames = {}
    for (let i = 0; i < fieldsModel.count; i++) {
      const row = fieldsModel.get(i)
      const name = row.name.trim().toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_äöüß]/g, "")
      if (name === "")
        continue
      if (name === "fid") {
        toast(qsTr("Der Feldname „fid“ ist reserviert"), 'warning')
        return false
      }
      if (usedNames[name]) {
        toast(qsTr("Feldname „%1“ ist doppelt").arg(name), 'warning')
        return false
      }
      usedNames[name] = true
      fieldList.push(FeatureUtils.createField(name, fieldTypes[row.typeIndex].type))
    }
    const fields = FeatureUtils.createFields(fieldList)

    // Geometrietyp
    const withZ = zSwitch.checked
    let wkbType
    switch (geometryGroup.checkedIndex) {
    case 1:
      wkbType = withZ ? Qgis.WkbType.LineStringZ : Qgis.WkbType.LineString
      break
    case 2:
      wkbType = withZ ? Qgis.WkbType.PolygonZ : Qgis.WkbType.Polygon
      break
    default:
      wkbType = withZ ? Qgis.WkbType.PointZ : Qgis.WkbType.Point
    }

    let crs = qgisProject.crs
    if (!crs || crs.authid === "")
      crs = CoordinateReferenceSystemUtils.wgs84Crs()

    // Leeren Speicherlayer erzeugen und als GeoPackage schreiben
    const memoryLayer = LayerUtils.createMemoryLayer(displayName, fields, wkbType, crs)
    if (!memoryLayer) {
      toast(qsTr("Layer konnte nicht erzeugt werden"), 'error')
      return false
    }
    const writtenPath = LayerUtils.saveVectorLayerAs(memoryLayer, path, "GPKG", "")
    if (writtenPath === "") {
      toast(qsTr("GeoPackage konnte nicht geschrieben werden"), 'error')
      return false
    }

    const entry = {
      name: displayName,
      path: writtenPath,
      layerName: fileBase,
      created: new Date().toISOString()
    }
    const layer = addLayerToProject(entry)
    if (!layer) {
      toast(qsTr("GeoPackage erstellt, aber Laden fehlgeschlagen"), 'error')
      return false
    }

    const list = loadRegistry()
    list.push(entry)
    saveRegistry(list)
    layerListModel.refresh()

    if (dashBoard)
      dashBoard.activeLayer = layer

    toast(qsTr("Layer „%1“ angelegt").arg(displayName), 'info')
    return true
  }

  function forgetLayer(index) {
    const list = loadRegistry()
    if (index < 0 || index >= list.length)
      return
    const entry = list[index]
    const layers = ProjectUtils.mapLayers(qgisProject)
    for (const id in layers) {
      const layer = layers[id]
      if (layer && layer.customProperty("neuerLayer/path", "") === entry.path)
        ProjectUtils.removeMapLayer(qgisProject, id)
    }
    list.splice(index, 1)
    saveRegistry(list)
    layerListModel.refresh()
    toast(qsTr("„%1“ aus dem Projekt entfernt – die Datei bleibt erhalten").arg(entry.name))
  }

  function resetForm() {
    layerNameField.text = ""
    geometryGroup.checkedIndex = 0
    zSwitch.checked = true
    fieldsModel.clear()
    fieldsModel.append({ name: "bemerkung", typeIndex: 0 })
  }

  // ---------------------------------------------------------------------------
  // Toolbar-Button
  // ---------------------------------------------------------------------------

  QfToolButton {
    id: newLayerButton
    bgcolor: Theme.darkGray
    iconSource: Qt.resolvedUrl('icon.svg')
    iconColor: Theme.mainColor
    round: true

    onClicked: {
      if (!qgisProject.fileName) {
        plugin.toast(qsTr("Bitte zuerst ein Projekt öffnen"), 'warning')
        return
      }
      plugin.resetForm()
      layerListModel.refresh()
      dialog.open()
    }
  }

  // ---------------------------------------------------------------------------
  // Modelle
  // ---------------------------------------------------------------------------

  ListModel {
    id: fieldsModel
  }

  ListModel {
    id: layerListModel
    function refresh() {
      clear()
      const list = plugin.loadRegistry()
      for (const entry of list) {
        append({ name: entry.name, path: entry.path, exists: FileUtils.fileExists(entry.path) })
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dialog
  // ---------------------------------------------------------------------------

  QfPopup {
    id: dialog
    parent: plugin.mainWindow.contentItem
    width: Math.min(440, plugin.mainWindow.width - 24)
    height: Math.min(contentColumn.implicitHeight + 32, plugin.mainWindow.height - 48)
    x: (plugin.mainWindow.width - width) / 2
    y: Math.max(24, (plugin.mainWindow.height - height) / 2)
    padding: 16
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Flickable {
      anchors.fill: parent
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: contentColumn
        width: parent.width
        spacing: 10

        Label {
          text: qsTr("Neuer Layer")
          font: Theme.strongFont
          color: Theme.mainTextColor
          Layout.fillWidth: true
        }

        // Name
        Label {
          text: qsTr("Name")
          font: Theme.tipFont
          color: Theme.secondaryTextColor
        }
        TextField {
          id: layerNameField
          Layout.fillWidth: true
          placeholderText: qsTr("z. B. Grenzsteine")
          font: Theme.defaultFont
          inputMethodHints: Qt.ImhNoPredictiveText
        }

        // Geometrie
        Label {
          text: qsTr("Geometrie")
          font: Theme.tipFont
          color: Theme.secondaryTextColor
        }
        RowLayout {
          id: geometryGroup
          property int checkedIndex: 0
          Layout.fillWidth: true
          spacing: 6

          Repeater {
            model: [qsTr("Punkt"), qsTr("Linie"), qsTr("Polygon")]
            delegate: QfButton {
              required property int index
              required property string modelData
              Layout.fillWidth: true
              text: modelData
              bgcolor: geometryGroup.checkedIndex === index ? Theme.mainColor : "transparent"
              color: geometryGroup.checkedIndex === index ? "white" : Theme.mainTextColor
              borderColor: Theme.mainColor
              onClicked: geometryGroup.checkedIndex = index
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Label {
            Layout.fillWidth: true
            text: qsTr("Höhe (Z) speichern")
            font: Theme.defaultFont
            color: Theme.mainTextColor
            wrapMode: Text.WordWrap
          }
          QfSwitch {
            id: zSwitch
            checked: true
          }
        }

        Label {
          Layout.fillWidth: true
          text: qsTr("Koordinatensystem: %1 (wie Projekt)").arg(qgisProject.crs && qgisProject.crs.authid !== "" ? qgisProject.crs.authid : "EPSG:4326")
          font: Theme.tipFont
          color: Theme.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        // Felder
        Label {
          text: qsTr("Felder")
          font: Theme.tipFont
          color: Theme.secondaryTextColor
          Layout.topMargin: 4
        }

        Repeater {
          model: fieldsModel
          delegate: RowLayout {
            required property int index
            required property string name
            required property int typeIndex
            Layout.fillWidth: true
            spacing: 6

            TextField {
              Layout.fillWidth: true
              text: name
              placeholderText: qsTr("Feldname")
              font: Theme.defaultFont
              inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
              onTextEdited: fieldsModel.setProperty(index, "name", text)
            }
            ComboBox {
              Layout.preferredWidth: 130
              model: plugin.fieldTypes.map(t => t.label)
              currentIndex: typeIndex
              font: Theme.defaultFont
              onActivated: idx => fieldsModel.setProperty(index, "typeIndex", idx)
            }
            QfToolButton {
              Layout.preferredWidth: 36
              Layout.preferredHeight: 36
              iconSource: Theme.getThemeVectorIcon('ic_close_white_24dp')
              iconColor: Theme.mainTextColor
              bgcolor: "transparent"
              onClicked: fieldsModel.remove(index)
            }
          }
        }

        QfButton {
          Layout.fillWidth: true
          text: qsTr("+ Feld hinzufügen")
          bgcolor: "transparent"
          color: Theme.mainColor
          onClicked: fieldsModel.append({ name: "", typeIndex: 0 })
        }

        QfButton {
          Layout.fillWidth: true
          Layout.topMargin: 4
          text: qsTr("Layer anlegen")
          onClicked: {
            if (plugin.createLayer())
              dialog.close()
          }
        }

        // Bestehende Feldlayer dieses Projekts
        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: 8
          height: 1
          color: Theme.controlBorderColor
          visible: layerListModel.count > 0
        }

        Label {
          text: qsTr("Feldlayer in diesem Projekt")
          font: Theme.tipFont
          color: Theme.secondaryTextColor
          visible: layerListModel.count > 0
        }

        Repeater {
          model: layerListModel
          delegate: RowLayout {
            required property int index
            required property string name
            required property string path
            required property bool exists
            Layout.fillWidth: true
            spacing: 6

            Label {
              Layout.fillWidth: true
              text: exists ? name : name + " " + qsTr("(Datei fehlt)")
              font: Theme.defaultFont
              color: exists ? Theme.mainTextColor : Theme.errorColor
              elide: Text.ElideRight
            }
            QfButton {
              text: qsTr("Teilen")
              enabled: exists
              bgcolor: "transparent"
              color: Theme.mainColor
              onClicked: platformUtilities.sendDatasetTo(path)
            }
            QfButton {
              text: qsTr("Entfernen")
              bgcolor: "transparent"
              color: Theme.errorColor
              onClicked: plugin.forgetLayer(index)
            }
          }
        }
      }
    }
  }
}
