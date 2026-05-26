// Server Launcher — anonymous telemetry helper. GNU GPL v3 or later.

#ifndef TELEMETRYMANAGER_H
#define TELEMETRYMANAGER_H

#include <QJsonObject>
#include <QObject>
#include <QVariant>
#include <QString>

class QNetworkAccessManager;

class TelemetryManager : public QObject {
  Q_OBJECT
 public:
  explicit TelemetryManager(QObject* parent = nullptr);

  bool enabled() const;
  bool extended() const;
  bool hasConsent() const;
  bool canSend() const;
  QString endpoint() const;
  QString apiKey() const;

  void sendEvent(const QString& eventName,
                 const QJsonObject& properties = QJsonObject());

 public slots:
  void setEnabled(bool enabled);
  void setExtended(bool extended);
  void setEndpoint(const QString& endpoint);
  void setApiKey(const QString& apiKey);
  void setConsentAsked(bool asked);

 private:
  void loadSettings();
  void saveSetting(const QString& key, const QVariant& value);
  void ensureAnonymousId();
  QJsonObject baselineProperties(const QString& eventName) const;
  bool hasValidConfiguration() const;

  QNetworkAccessManager* network_ = nullptr;
  QString endpoint_;
  QString apiKey_;
  QString anonymousId_;
  const QString table_ = QStringLiteral("telemetry_events");
  bool enabled_ = false;
  bool extended_ = false;
  bool asked_ = false;
};

#endif // TELEMETRYMANAGER_H
