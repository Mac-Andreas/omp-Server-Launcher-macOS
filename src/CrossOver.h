// Server Launcher — a small macOS app that runs the Windows open.mp server
// under CrossOver's Wine, in its own 32-bit bottle.
//
// This file is free software under the GNU GPL v3 or later (same as qawno).

#ifndef CROSSOVER_H
#define CROSSOVER_H

#include <QObject>
#include <QString>
#include <QStringList>

// macOS-only helper around CrossOver's bundled Wine. open.mp ships only a
// 32-bit Windows server, so the launcher runs omp-server.exe in a dedicated
// 32-bit bottle (separate from qawno's compiler bottle). Everything is static;
// CrossOver state lives on disk and is re-read on each call.
class CrossOver {
 public:
  // The 32-bit bottle the server runs in. Distinct from qawno's "Qawno" bottle.
  static const QString kBottle;          // "OpenMPServer"
  static const QString kBottleTemplate;  // "win10"

  static QString appPath();          // "" if not installed
  static QString cxRoot();           // .../SharedSupport/CrossOver
  static QString winePath();         // cxRoot/bin/wine ("" if missing)
  static QString cxBottlePath();     // cxRoot/bin/cxbottle ("" if missing)

  static bool isInstalled();
  static QString version();          // CFBundleShortVersionString, e.g. "26.1"

  static QString bottlesDir();
  static QString bottlePath();       // bottlesDir/kBottle
  static bool bottleExists();

  // Create the 32-bit OpenMPServer bottle (blocking; seconds). True on success;
  // on failure fills *error. No-op (true) if the bottle already exists.
  static bool createBottle(QString* error = nullptr);

  // Delete the bottle (for a clean reinstall). True on success or if already
  // gone; on failure fills *error.
  static bool deleteBottle(QString* error = nullptr);

  // The open.mp server folder: where the .app is dropped (its parent dir), so
  // omp-server.exe / config / components sit beside the .app, not inside it.
  static QString serverDir();

  // Server files the launcher needs in serverDir(): the Windows server binary.
  // (run-omp-server-wine.sh ships inside the app, so it isn't listed.)
  static QStringList requiredFiles();   // file names, display order
  static QStringList missingFiles();    // absent subset of requiredFiles
  static bool filesPresent();

  // True if an omp-server.exe is already running on this machine (e.g. started
  // outside this launcher). Used to kill a stray server before starting ours.
  static bool serverRunning();
  // Kill any running omp-server.exe (and wineserver in our bottle). Blocking.
  static void killRunningServers();
};

#endif // CROSSOVER_H
