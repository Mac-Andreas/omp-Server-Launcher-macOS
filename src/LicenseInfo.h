// Server Launcher — license detection + permission pills. GNU GPL v3 or later.

#ifndef LICENSEINFO_H
#define LICENSEINFO_H

#include <QObject>
#include <QString>
#include <QVector>

// Data-driven license info: given license text (bundled, or fetched live from
// GitHub), it detects the license type and exposes the permissions/conditions/
// limitations as pills. Change the LICENSE file and the pills follow — no code
// edit needed for a license swap among the known types.
class LicenseInfo : public QObject {
  Q_OBJECT

 public:
  // kind: 0 = permission (green ✓), 1 = condition (amber ⚑),
  //       2 = limitation (red ✗).
  struct Pill {
    QString text;
    int kind;
  };

  explicit LicenseInfo(QObject* parent = nullptr);

  // Short name detected from the text, e.g. "GNU GPL v3", "MIT", "MPL 2.0".
  // Empty if unknown.
  QString name() const { return name_; }
  QString summary() const { return summary_; }
  QVector<Pill> pills() const { return pills_; }
  QString fullText() const { return text_; }

  // Detect from already-loaded text (e.g. the bundled LICENSE.txt).
  void setText(const QString& licenseText);

  // Fetch LICENSE live from a GitHub repo's default branch (raw), then detect.
  // Emits changed() when done (whether it updated or kept the fallback).
  void fetchFromGitHub(const QString& owner, const QString& repo);

 signals:
  void changed();

 private:
  void detect();

  QString text_;
  QString name_;
  QString summary_;
  QVector<Pill> pills_;
};

#endif // LICENSEINFO_H
