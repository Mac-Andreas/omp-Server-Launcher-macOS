// Server Launcher — app metadata. GNU GPL v3 or later.

#ifndef APPINFO_H
#define APPINFO_H

#include <QString>

namespace AppInfo {

// Bump this on each release; the update check compares it to the latest
// GitHub release tag.
inline const QString kVersion = QStringLiteral("1.0.0");

// GitHub repo to check for releases + fetch the live LICENSE.
// (update check: https://api.github.com/repos/<owner>/<repo>/releases/latest)
inline const QString kUpdateOwner = QStringLiteral("isiddharthasharma");
inline const QString kUpdateRepo  = QStringLiteral("open.mp-Server-Launcher");

}  // namespace AppInfo

#endif // APPINFO_H
