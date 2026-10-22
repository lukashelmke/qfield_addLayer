# Neuer Layer – QField-Plugin

Legt direkt in QField neue, leere Vektorlayer an, ohne dass du vorher in QGIS etwas vorbereiten musst.

## Funktionen

- Toolbar-Button öffnet einen Dialog mit Name, Geometrie (Punkt/Linie/Polygon), optionaler Höhe (Z) und frei definierbaren Feldern (Text, Ganzzahl, Dezimalzahl, Ja/Nein, Datum, Datum + Zeit)
- Der Layer wird als GeoPackage im Projekt-KBS angelegt, ins offene Projekt geladen und direkt als aktiver Layer zum Digitalisieren gesetzt
- Beim erneuten Öffnen des Projekts lädt das Plugin seine Layer automatisch wieder (QField speichert die Projektdatei selbst nicht)
- Mit „Teilen“ schickst du das GeoPackage über das iOS-Teilen-Menü weiter (AirDrop, Mail, Dateien …)

## Speicherort

`QField-Dokumente/Imported Datasets/Feldlayer/<Projektname>/<Layer>.gpkg`

Der Ordner liegt bewusst außerhalb des Projektordners. So kann ein QFieldCloud-Update oder das Entfernen des Cloud-Projekts die Daten nicht löschen. Auf iOS findest du ihn in der Dateien-App unter „Auf meinem iPhone › QField“ und in QField selbst unter „Lokale Dateien öffnen“.

## Wichtig bei QFieldCloud

Die neuen Layer werden **nicht** über QFieldCloud synchronisiert, denn der Server kennt sie nicht. Das Plugin markiert sie deshalb ausdrücklich als „no_action“, damit der Push nicht fehlschlägt. Am Rechner holst du die Daten so: GeoPackage teilen (AirDrop o. Ä.), dann in QGIS laden oder in den Projektordner kopieren und regulär einbinden.

## Installation

1. Den Ordnerinhalt (`main.qml`, `metadata.txt`, `icon.svg`) als ZIP packen. Die Dateien müssen auf der obersten Ebene liegen.
2. Das ZIP über eine direkte URL bereitstellen, z. B. als GitHub-Release-Asset.
3. In QField: Einstellungen › Plugins › „Install plugin from URL“ und die URL eintragen.

Benötigt eine aktuelle QField-Version (geprüft gegen den Quellcode von QField 4.3.6).
