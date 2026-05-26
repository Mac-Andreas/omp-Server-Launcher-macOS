// Server Launcher — anonymous telemetry helper. GNU GPL v3 or later.

#include "TelemetryManager.h"

#include "AppInfo.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QJsonDocument>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QSysInfo>
#include <QUuid>
#include <QVariant>

TelemetryManager::TelemetryManager(QObject* parent)
    : QObject(parent), network_(new QNetworkAccessManager(this)) {
  loadSettings();
}

bool TelemetryManager::enabled() const {
  return enabled_;
}

bool TelemetryManager::extended() const {
  return extended_;
}

bool TelemetryManager::hasConsent() const {
  return asked_;
}

bool TelemetryManager::canSend() const {
  return enabled_ && asked_ && hasValidConfiguration();
}

QString TelemetryManager::endpoint() const {
  return endpoint_;
}

QString TelemetryManager::apiKey() const {
  return apiKey_;
}

void TelemetryManager::setEnabled(bool enabled) {
  enabled_ = enabled;
  saveSetting(QStringLiteral("TelemetryEnabled"), enabled_);
  if (enabled_) {
    ensureAnonymousId();
  }
}

void TelemetryManager::setExtended(bool extended) {
  extended_ = extended;
  saveSetting(QStringLiteral("TelemetryExtended"), extended_);
}

void TelemetryManager::setEndpoint(const QString& endpoint) {
  endpoint_ = endpoint.trimmed();
}

void TelemetryManager::setApiKey(const QString& apiKey) {
  apiKey_ = apiKey.trimmed();
}

void TelemetryManager::setConsentAsked(bool asked) {
  asked_ = asked;
  saveSetting(QStringLiteral("TelemetryConsentAsked"), asked_);
}

void TelemetryManager::sendEvent(const QString& eventName,
                                 const QJsonObject& properties) {
  if (!canSend()) {
    return;
  }

  ensureAnonymousId();
  QJsonObject payload = baselineProperties(eventName);
  payload[QStringLiteral("event_properties")] = properties;

  const QJsonDocument doc(payload);
  const QUrl url(endpoint_);
  QNetworkRequest request(url);
  request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
  request.setRawHeader("apikey", apiKey_.toUtf8());
  request.setRawHeader("Authorization",
                       QStringLiteral("Bearer %1").arg(apiKey_).toUtf8());
  request.setRawHeader("Prefer", "return=minimal");

  QNetworkReply* reply = network_->post(request, doc.toJson(QJsonDocument::Compact));
  connect(reply, &QNetworkReply::finished, reply, [reply] {
    if (reply->error() != QNetworkReply::NoError) {
      qWarning() << "Telemetry send failed:" << reply->errorString();
    }
    reply->deleteLater();
  });
}

void TelemetryManager::loadSettings() {
  QSettings s;
  endpoint_ = s.value(QStringLiteral("TelemetrySupabaseEndpoint"), "").toString();
  apiKey_ = s.value(QStringLiteral("TelemetrySupabaseApiKey"), "").toString();
  enabled_ = s.value(QStringLiteral("TelemetryEnabled"), false).toBool();
  extended_ = s.value(QStringLiteral("TelemetryExtended"), false).toBool();
  asked_ = s.value(QStringLiteral("TelemetryConsentAsked"), false).toBool();
  anonymousId_ = s.value(QStringLiteral("TelemetryAnonymousId"), "").toString();

  const QString envUrl = QString::fromUtf8(qgetenv("SUPABASE_URL"));
  const QString envKey = QString::fromUtf8(qgetenv("SUPABASE_API_KEY"));
  if (!envUrl.isEmpty()) {
    endpoint_ = envUrl;
  }
  if (!envKey.isEmpty()) {
    apiKey_ = envKey;
  }
  if (enabled_) {
    ensureAnonymousId();
  }
}

void TelemetryManager::saveSetting(const QString& key, const QVariant& value) {
  QSettings().setValue(key, value);
}

void TelemetryManager::ensureAnonymousId() {
  if (!anonymousId_.isEmpty()) {
    return;
  }
  anonymousId_ = QUuid::createUuid().toString(QUuid::WithoutBraces);
  saveSetting(QStringLiteral("TelemetryAnonymousId"), anonymousId_);
}

QJsonObject TelemetryManager::baselineProperties(
    const QString& eventName) const {
  QJsonObject payload;
  payload[QStringLiteral("anonymous_id")] = anonymousId_;
  payload[QStringLiteral("event_name")] = eventName;
  payload[QStringLiteral("app_version")] = AppInfo::kVersion;
  payload[QStringLiteral("os_name")] = QSysInfo::productType();
  payload[QStringLiteral("os_version")] = QSysInfo::productVersion();
  payload[QStringLiteral("architecture")] = QSysInfo::currentCpuArchitecture();
  payload[QStringLiteral("locale")] = QLocale::system().name();
  payload[QStringLiteral("platform")] = QStringLiteral("macos");
  payload[QStringLiteral("extended")]= extended_;
  payload[QStringLiteral("timestamp_utc")] =
      QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
  payload[QStringLiteral("source")] = QStringLiteral("openmp_server_launcher");
  return payload;
}

bool TelemetryManager::hasValidConfiguration() const {
  return !endpoint_.trimmed().isEmpty() && !apiKey_.trimmed().isEmpty();
}
