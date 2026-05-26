// Server Launcher — SF Symbols -> QIcon bridge. GNU GPL v3 or later.

#ifndef SYMBOLICON_H
#define SYMBOLICON_H

#include <QIcon>
#include <QString>

namespace SymbolIcon {

// Render an Apple SF Symbol (by name, e.g. "person.slash") into a QIcon at the
// given point size, tinted to the given color. On non-macOS or if the symbol
// is unavailable, returns a null QIcon (caller can fall back).
QIcon load(const QString& symbolName, int pointSize = 16,
           const QColor& color = QColor(0xC8, 0xCD, 0xD6));

}  // namespace SymbolIcon

#endif // SYMBOLICON_H
