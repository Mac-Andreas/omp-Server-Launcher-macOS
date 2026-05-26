// Server Launcher — license detection + permission pills. GNU GPL v3 or later.

#include "LicenseInfo.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

#include <functional>
#include <memory>

namespace {
// A known-license descriptor: detection markers + the pills to show. Adding a
// license here makes the UI support it; detection picks the first whose marker
// appears in the text.
struct Known {
  const char* name;
  const char* summary;
  QStringList markers;  // case-insensitive substrings unique to this license
  QVector<LicenseInfo::Pill> pills;
};

QVector<Known> table() {
  using P = LicenseInfo::Pill;
  return {
      {"GNU GPL v3",
       "A strong copyleft license: share the source and keep it free.",
       {"GNU GENERAL PUBLIC LICENSE", "Version 3"},
       {{"Use commercially", 0}, {"Modify", 0}, {"Distribute", 0},
        {"Use privately", 0},
        {"Disclose source", 1}, {"Same license", 1}, {"State changes", 1},
        {"Hold authors liable", 2}, {"Expect warranty", 2},
        {"Sublicense as proprietary", 2}}},
      {"GNU GPL v2",
       "A strong copyleft license: share the source and keep it free.",
       {"GNU GENERAL PUBLIC LICENSE", "Version 2"},
       {{"Use commercially", 0}, {"Modify", 0}, {"Distribute", 0},
        {"Use privately", 0},
        {"Disclose source", 1}, {"Same license", 1}, {"State changes", 1},
        {"Hold authors liable", 2}, {"Expect warranty", 2}}},
      {"GNU LGPL v3",
       "Weak copyleft: link freely, but changes to the library stay open.",
       {"GNU LESSER GENERAL PUBLIC LICENSE"},
       {{"Use commercially", 0}, {"Modify", 0}, {"Distribute", 0},
        {"Use privately", 0},
        {"Disclose source (library)", 1}, {"Same license (library)", 1},
        {"State changes", 1},
        {"Hold authors liable", 2}, {"Expect warranty", 2}}},
      {"MPL 2.0",
       "File-level copyleft: modified files stay open, the rest is yours.",
       {"Mozilla Public License Version 2.0"},
       {{"Use commercially", 0}, {"Modify", 0}, {"Distribute", 0},
        {"Use privately", 0}, {"Sublicense", 0},
        {"Disclose source (changed files)", 1}, {"Same license (files)", 1},
        {"Hold authors liable", 2}, {"Use trademarks", 2},
        {"Expect warranty", 2}}},
      {"Apache 2.0",
       "Permissive with a patent grant; keep notices.",
       {"Apache License", "Version 2.0"},
       {{"Use commercially", 0}, {"Modify", 0}, {"Distribute", 0},
        {"Use privately", 0}, {"Sublicense", 0}, {"Patent use", 0},
        {"State changes", 1}, {"Keep notices", 1},
        {"Hold authors liable", 2}, {"Use trademarks", 2},
        {"Expect warranty", 2}}},
      {"MIT",
       "Very permissive: do almost anything, keep the copyright notice.",
       {"Permission is hereby granted, free of charge"},
       {{"Use commercially", 0}, {"Modify", 0}, {"Distribute", 0},
        {"Use privately", 0}, {"Sublicense", 0},
        {"Keep copyright notice", 1},
        {"Hold authors liable", 2}, {"Expect warranty", 2}}},
      {"BSD",
       "Permissive: keep the copyright and disclaimer.",
       {"Redistribution and use in source and binary forms"},
       {{"Use commercially", 0}, {"Modify", 0}, {"Distribute", 0},
        {"Use privately", 0},
        {"Keep copyright notice", 1},
        {"Hold authors liable", 2}, {"Expect warranty", 2}}},
  };
}
}  // namespace

LicenseInfo::LicenseInfo(QObject* parent) : QObject(parent) {}

void LicenseInfo::setText(const QString& licenseText) {
  text_ = licenseText;
  detect();
}

void LicenseInfo::detect() {
  name_.clear();
  summary_.clear();
  pills_.clear();
  if (text_.isEmpty()) {
    return;
  }
  for (const Known& k : table()) {
    bool all = true;
    for (const QString& m : k.markers) {
      if (!text_.contains(m, Qt::CaseInsensitive)) {
        all = false;
        break;
      }
    }
    if (all) {
      name_ = k.name;
      summary_ = k.summary;
      pills_ = k.pills;
      return;
    }
  }
  // Unknown license: still show the text, with a neutral note.
  name_ = QObject::tr("Custom license");
  summary_ = QObject::tr("See the full text below.");
}

void LicenseInfo::fetchFromGitHub(const QString& owner, const QString& repo) {
  // Try common LICENSE filenames on the default branch via raw.githubusercontent.
  auto* net = new QNetworkAccessManager(this);
  auto names = std::make_shared<QStringList>(QStringList{
      "LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING"});
  auto branch = std::make_shared<QString>("HEAD");

  std::function<void()> tryNext;
  auto tryNextPtr = std::make_shared<std::function<void()>>();
  *tryNextPtr = [this, net, owner, repo, names, branch, tryNextPtr]() {
    if (names->isEmpty()) {
      return;  // keep whatever fallback text was set
    }
    const QString file = names->takeFirst();
    const QString url =
        QStringLiteral("https://raw.githubusercontent.com/%1/%2/%3/%4")
            .arg(owner, repo, *branch, file);
    QNetworkRequest req((QUrl(url)));
    req.setRawHeader("User-Agent", "openmp-server-launcher");
    QNetworkReply* reply = net->get(req);
    QObject::connect(reply, &QNetworkReply::finished, this,
                     [this, reply, tryNextPtr]() {
                       reply->deleteLater();
                       if (reply->error() == QNetworkReply::NoError) {
                         const QString body =
                             QString::fromUtf8(reply->readAll());
                         if (!body.trimmed().isEmpty()) {
                           setText(body);
                           emit changed();
                           return;
                         }
                       }
                       (*tryNextPtr)();  // try the next filename
                     });
  };
  (*tryNextPtr)();
}
