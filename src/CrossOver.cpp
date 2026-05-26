// Server Launcher — CrossOver helper. GNU GPL v3 or later.

#include "CrossOver.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>

const QString CrossOver::kBottle = QStringLiteral("OpenMPServer");
const QString CrossOver::kBottleTemplate = QStringLiteral("win10");

QString CrossOver::appPath() {
  static const QString fixed = QStringLiteral("/Applications/CrossOver.app");
  return QFileInfo::exists(fixed) ? fixed : QString();
}

QString CrossOver::cxRoot() {
  const QString app = appPath();
  return app.isEmpty()
             ? QString()
             : app + QStringLiteral("/Contents/SharedSupport/CrossOver");
}

QString CrossOver::winePath() {
  const QString root = cxRoot();
  if (root.isEmpty()) {
    return QString();
  }
  const QString wine = root + QStringLiteral("/bin/wine");
  return QFileInfo(wine).isExecutable() ? wine : QString();
}

QString CrossOver::cxBottlePath() {
  const QString root = cxRoot();
  if (root.isEmpty()) {
    return QString();
  }
  const QString cxbottle = root + QStringLiteral("/bin/cxbottle");
  return QFileInfo(cxbottle).isExecutable() ? cxbottle : QString();
}

bool CrossOver::isInstalled() {
  return !appPath().isEmpty();
}

QString CrossOver::version() {
  const QString app = appPath();
  if (app.isEmpty()) {
    return QString();
  }
  QSettings plist(app + QStringLiteral("/Contents/Info.plist"),
                  QSettings::NativeFormat);
  return plist.value(QStringLiteral("CFBundleShortVersionString")).toString();
}

QString CrossOver::bottlesDir() {
  const QString home =
      QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
  return home + QStringLiteral("/Library/Application Support/CrossOver/Bottles");
}

QString CrossOver::bottlePath() {
  return bottlesDir() + QStringLiteral("/") + kBottle;
}

bool CrossOver::bottleExists() {
  return QFileInfo::exists(bottlePath() + QStringLiteral("/system.reg"));
}

bool CrossOver::createBottle(QString* error) {
  if (bottleExists()) {
    return true;
  }
  const QString cxbottle = cxBottlePath();
  if (cxbottle.isEmpty()) {
    if (error) {
      *error = QObject::tr("cxbottle not found; is CrossOver installed?");
    }
    return false;
  }

  QProcess proc;
  proc.setProcessChannelMode(QProcess::MergedChannels);
  QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
  env.insert(QStringLiteral("CX_ROOT"), cxRoot());
  proc.setProcessEnvironment(env);

  proc.start(cxbottle, {QStringLiteral("--create"),
                        QStringLiteral("--bottle"), kBottle,
                        QStringLiteral("--template"), kBottleTemplate});
  if (!proc.waitForStarted(10000)) {
    if (error) {
      *error = QObject::tr("Could not start cxbottle.");
    }
    return false;
  }
  proc.waitForFinished(300000);

  if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0 ||
      !bottleExists()) {
    if (error) {
      *error = QString::fromLocal8Bit(proc.readAll());
      if (error->isEmpty()) {
        *error =
            QObject::tr("cxbottle exited with code %1.").arg(proc.exitCode());
      }
    }
    return false;
  }
  return true;
}

bool CrossOver::deleteBottle(QString* error) {
  if (!bottleExists()) {
    return true;
  }
  const QString cxbottle = cxBottlePath();
  if (!cxbottle.isEmpty()) {
    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("CX_ROOT"), cxRoot());
    proc.setProcessEnvironment(env);
    proc.start(cxbottle,
               {QStringLiteral("--delete"), QStringLiteral("--bottle"), kBottle});
    if (proc.waitForStarted(10000)) {
      proc.waitForFinished(120000);
    }
  }
  if (bottleExists()) {
    QDir(bottlePath()).removeRecursively();
  }
  if (bottleExists()) {
    if (error) {
      *error = QObject::tr("Could not remove the bottle directory.");
    }
    return false;
  }
  return true;
}

QString CrossOver::serverDir() {
  // The .app is dropped into the server folder, so the server files are the
  // .app's siblings. applicationDirPath() is .app/Contents/MacOS — go up three.
  QDir dir(QCoreApplication::applicationDirPath());
  if (dir.dirName() == QLatin1String("MacOS")) {
    dir.cdUp();  // Contents
    dir.cdUp();  // .app
    dir.cdUp();  // folder containing the .app == server folder
  }
  return dir.absolutePath();
}

QStringList CrossOver::requiredFiles() {
  // The Windows open.mp server binary the launcher runs under Wine.
  return {QStringLiteral("omp-server.exe")};
}

QStringList CrossOver::missingFiles() {
  const QString dir = serverDir();
  QStringList missing;
  for (const QString& f : requiredFiles()) {
    if (!QFileInfo::exists(dir + QStringLiteral("/") + f)) {
      missing << f;
    }
  }
  return missing;
}

bool CrossOver::filesPresent() {
  return missingFiles().isEmpty();
}

bool CrossOver::serverRunning() {
  // pgrep matches the omp-server.exe image Wine launches.
  QProcess p;
  p.start(QStringLiteral("pgrep"), {QStringLiteral("-i"),
                                    QStringLiteral("-f"),
                                    QStringLiteral("omp-server.exe")});
  p.waitForFinished(5000);
  return !p.readAllStandardOutput().trimmed().isEmpty();
}

void CrossOver::killRunningServers() {
  // Kill the Windows server image, then the wineserver backing our bottle.
  for (const QString& pat :
       {QStringLiteral("omp-server.exe"), QStringLiteral("wineserver")}) {
    QProcess p;
    p.start(QStringLiteral("pkill"),
            {QStringLiteral("-i"), QStringLiteral("-f"), pat});
    p.waitForFinished(5000);
  }
}
