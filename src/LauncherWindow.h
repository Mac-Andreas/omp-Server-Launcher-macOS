// Server Launcher — main window. GNU GPL v3 or later.

#ifndef LAUNCHERWINDOW_H
#define LAUNCHERWINDOW_H

#include <QJsonObject>
#include <QMainWindow>
#include <QPair>
#include <QVector>

class QLabel;
class QPushButton;
class QPlainTextEdit;
class QProcess;
class QLineEdit;
class QSpinBox;
class QComboBox;
class QListWidget;
class QTabWidget;
class QSystemTrayIcon;
class QCloseEvent;
class QShowEvent;
class TelemetryManager;

// Tabbed launcher: Server (cards + start/stop/restart + live log), Config
// (key fields with folder-populated dropdowns), Bans (add/remove), License.
// Top-right: Settings (run-at-login, menu-bar) + version/update pills.
class LauncherWindow : public QMainWindow {
  Q_OBJECT

 public:
  explicit LauncherWindow(QWidget* parent = nullptr);

 protected:
  // Closing the window hides it instead of quitting; only Quit (dock/menu)
  // actually exits.
  void closeEvent(QCloseEvent* event) override;

 private:
  // --- Top bar (title, version pill, update button, settings) ---
  QWidget* buildHeader();
  void showSettingsMenu();
  void onUpdateChecked(bool available, const QString& version,
                       const QString& htmlUrl);
  void maybeAskTelemetryConsent();
  void showEvent(QShowEvent* event) override;

  // --- Server tab ---
  QWidget* buildServerTab();
  QWidget* buildCrossOverCard();
  QWidget* buildServerFilesCard();
  void refreshCards();
  void setupBottle();
  void deleteBottle();
  void startServer();   // kills any stray server first
  void stopServer();
  void restartServer();
  bool preflight();
  void appendLog(const QString& text);
  void setServerRunningUi(bool running);

  // --- Config tab ---
  QWidget* buildConfigTab();
  void loadConfigIntoForm();
  void saveConfigFromForm();
  void populateScriptDropdowns();
  // Advanced: auto-built editors for every config.json key not in the basic
  // form, grouped into collapsible category cards. Returns the container.
  QWidget* buildAdvancedConfig();
  void rebuildAdvancedConfig();      // (re)populate from config_
  void applyAdvancedToConfig();      // write advanced editors back into config_

  // --- Bans tab ---
  QWidget* buildBansTab();
  void loadBans();
  void addBan();
  void removeSelectedBan();
  void saveBans();

  // --- License tab (data-driven from LicenseInfo) ---
  QWidget* buildLicenseTab();
  void rebuildLicense();   // (re)populate banner + pills + text from license_

  // Paths in the server folder (the .app's parent dir).
  QString configPath() const;
  QString bansPath() const;
  QString logPath() const;

  // --- widgets ---
  QTabWidget* tabs_ = nullptr;

  // header
  QLabel* versionPill_ = nullptr;
  QPushButton* updateButton_ = nullptr;
  QString updateUrl_;

  // cards
  QLabel* cxPill_ = nullptr;
  QLabel* cxDetail_ = nullptr;
  QPushButton* cxSetupButton_ = nullptr;
  QPushButton* cxDeleteButton_ = nullptr;
  QLabel* filesPill_ = nullptr;
  QLabel* filesDetail_ = nullptr;

  // server controls + log
  QPushButton* startButton_ = nullptr;
  QPushButton* stopButton_ = nullptr;
  QPushButton* restartButton_ = nullptr;
  QPlainTextEdit* log_ = nullptr;
  QProcess* server_ = nullptr;

  // config form
  QLineEdit* cfgHostname_ = nullptr;
  QComboBox* cfgGamemode_ = nullptr;
  QComboBox* cfgFilterscript_ = nullptr;
  QSpinBox* cfgPort_ = nullptr;
  QSpinBox* cfgMaxPlayers_ = nullptr;
  QLineEdit* cfgPassword_ = nullptr;
  QLineEdit* cfgRcon_ = nullptr;
  QJsonObject config_;  // full parsed config; form edits a subset, rest kept
  // Advanced editors: each maps a dotted JSON path -> its editor widget. Used
  // to read values back on save. Basic-form keys are excluded.
  QVector<QPair<QString, QWidget*>> advancedEditors_;
  QWidget* advancedContainer_ = nullptr;  // holds the category collapsibles

  // bans
  QListWidget* bansList_ = nullptr;

  // license (detected from text, refreshed from GitHub)
  class LicenseInfo* license_ = nullptr;
  QWidget* licenseContainer_ = nullptr;  // rebuilt when license changes
  TelemetryManager* telemetry_ = nullptr;
  bool consentPopupPending_ = false;
  QWidget* consentOverlay_ = nullptr;
  QWidget* settingsOverlay_ = nullptr;

  // tray + quit state
  QSystemTrayIcon* tray_ = nullptr;
  bool quitting_ = false;
};

#endif // LAUNCHERWINDOW_H
