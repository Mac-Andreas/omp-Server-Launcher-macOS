// Server Launcher — GitHub release update check. GNU GPL v3 or later.

#ifndef UPDATER_H
#define UPDATER_H

#include <QObject>
#include <QString>

class QNetworkAccessManager;

// Queries the GitHub releases API for the latest release of the configured
// repo and reports whether it's newer than the running version. Emits
// finished() once; never blocks the UI.
class Updater : public QObject {
  Q_OBJECT

 public:
  explicit Updater(QObject* parent = nullptr);

  // Start an async check. Safe to call again after finished().
  void check();

 signals:
  // updateAvailable: a newer release exists. latestVersion: its tag (e.g.
  // "1.2.0"). htmlUrl: the release page to open. On error, updateAvailable is
  // false and the other fields are empty.
  void finished(bool updateAvailable, const QString& latestVersion,
                const QString& htmlUrl);

 private:
  QNetworkAccessManager* net_;
};

#endif // UPDATER_H
