// Server Launcher — GitHub release update check. GNU GPL v3 or later.

#include "Updater.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>

#include "AppInfo.h"

namespace {
// Compare dotted version strings (e.g. "1.10.0" > "1.9.0"). Non-numeric chars
// (a leading "v", pre-release suffixes) are stripped per segment.
int compareVersions(const QString& a, const QString& b) {
  const QStringList as = a.split('.');
  const QStringList bs = b.split('.');
  const int n = qMax(as.size(), bs.size());
  for (int i = 0; i < n; ++i) {
    auto seg = [](const QStringList& s, int i) {
      if (i >= s.size()) return 0;
      QString t = s[i];
      t.remove(QRegularExpression("[^0-9]"));
      return t.isEmpty() ? 0 : t.toInt();
    };
    const int x = seg(as, i), y = seg(bs, i);
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}
}  // namespace

Updater::Updater(QObject* parent)
    : QObject(parent), net_(new QNetworkAccessManager(this)) {}

void Updater::check() {
  const QString url =
      QStringLiteral("https://api.github.com/repos/%1/%2/releases/latest")
          .arg(AppInfo::kUpdateOwner, AppInfo::kUpdateRepo);
  QNetworkRequest req((QUrl(url)));
  req.setRawHeader("Accept", "application/vnd.github+json");
  req.setRawHeader("User-Agent", "openmp-server-launcher");

  QNetworkReply* reply = net_->get(req);
  connect(reply, &QNetworkReply::finished, this, [this, reply] {
    reply->deleteLater();
    if (reply->error() != QNetworkReply::NoError) {
      emit finished(false, QString(), QString());
      return;
    }
    const QJsonObject obj =
        QJsonDocument::fromJson(reply->readAll()).object();
    const QString tag = obj.value("tag_name").toString();
    const QString htmlUrl = obj.value("html_url").toString();
    if (tag.isEmpty()) {
      emit finished(false, QString(), QString());
      return;
    }
    const bool newer = compareVersions(AppInfo::kVersion, tag) < 0;
    emit finished(newer, tag, htmlUrl);
  });
}
