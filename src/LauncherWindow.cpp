// Server Launcher — main window. GNU GPL v3 or later.

#include "LauncherWindow.h"

#include <QApplication>
#include <QCheckBox>
#include <QCloseEvent>
#include <QComboBox>
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QDoubleSpinBox>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFrame>
#include <QHBoxLayout>
#include <QInputDialog>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QTextEdit>
#include <QTextOption>
#include <QProcess>
#include <QProcessEnvironment>
#include <QPushButton>
#include <QRegularExpression>
#include <QRegularExpressionValidator>
#include <QScrollArea>
#include <QSettings>
#include <QSpinBox>
#include <QStyle>
#include <QSystemTrayIcon>
#include <QTabWidget>
#include <QToolButton>
#include <QUrl>
#include <QVBoxLayout>

#include "AppInfo.h"
#include "CrossOver.h"
#include "LicenseInfo.h"
#include "SymbolIcon.h"
#include "TelemetryManager.h"
#include "ToggleSwitch.h"
#include "Updater.h"

namespace {
const char* kPrimaryBtn =
    "QPushButton { border-radius: 9px; padding: 9px 20px; background: #7B5CFF; "
    "color: white; font-weight: 600; border: none; }"
    "QPushButton:hover { background: #8C70FF; }"
    "QPushButton:disabled { background: #3A4250; color: #6B7280; }";
const char* kGreenBtn =
    "QPushButton { border-radius: 9px; padding: 9px 20px; background: #1FA85C; "
    "color: white; font-weight: 600; border: none; }"
    "QPushButton:hover { background: #25BD68; }"
    "QPushButton:disabled { background: #3A4250; color: #6B7280; }";
const char* kRedBtn =
    "QPushButton { border-radius: 9px; padding: 9px 20px; background: #E5484D; "
    "color: white; font-weight: 600; border: none; }"
    "QPushButton:hover { background: #F05A5F; }"
    "QPushButton:disabled { background: #3A4250; color: #6B7280; }";
const char* kNeutralBtn =
    "QPushButton { border-radius: 9px; padding: 9px 20px; background: transparent; "
    "color: #C8CDD6; font-weight: 600; border: 1px solid #3A4250; }"
    "QPushButton:hover { background: #262B34; border-color: #4A5363; }"
    "QPushButton:disabled { color: #6B7280; border-color: #2C333D; }";

void stylePill(QLabel* pill, const QString& text, bool good) {
  pill->setText("  " + text + "  ");
  pill->setStyleSheet(
      QStringLiteral("background: %1; color: white; border-radius: 9px; "
                     "font-size: 11px; font-weight: 600; padding: 2px 4px;")
          .arg(good ? QStringLiteral("#27AE60") : QStringLiteral("#C0392B")));
}

QFrame* cardFrame() {
  QFrame* card = new QFrame;
  card->setObjectName("card");
  card->setStyleSheet(
      "#card { background: #171A20; border: 1px solid #2A2F38; "
      "border-radius: 10px; }");
  return card;
}

// A collapsible card: a rounded clickable header with a file icon on the left
// and a right-aligned arrow indicator.
QWidget* collapsible(const QString& title, const QString& dotColor,
                     QWidget* content, bool expanded = false) {
  QFrame* box = new QFrame;
  box->setObjectName("collapsibleCard");
  box->setStyleSheet(
      "#collapsibleCard { background: #171A20; border: 1px solid #2A2F38; "
      "border-radius: 10px; }");
  QVBoxLayout* v = new QVBoxLayout(box);
  v->setContentsMargins(0, 0, 0, 0);
  v->setSpacing(0);

  QPushButton* head = new QPushButton;
  head->setCursor(Qt::PointingHandCursor);
  head->setCheckable(true);
  head->setChecked(expanded);
  head->setFlat(true);
  head->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
  head->setStyleSheet(QStringLiteral(
      "QPushButton { border: none; background: transparent; padding: 11px 12px; }"
      "QPushButton:hover { background: #20242C; }"));

  QLabel* iconLabel = new QLabel;
  QIcon icon = SymbolIcon::load("doc.text", 14);
  if (icon.isNull()) {
    icon = head->style()->standardIcon(QStyle::SP_FileIcon);
  }
  if (!icon.isNull()) {
    iconLabel->setPixmap(icon.pixmap(QSize(16, 16)));
  } else {
    iconLabel->setText(QStringLiteral("📄"));
  }
  iconLabel->setFixedSize(18, 18);
  iconLabel->setAlignment(Qt::AlignCenter);
  QLabel* label = new QLabel(title);
  label->setStyleSheet("color: #E6E9EE; font-weight: 600; font-size: 14px;");
  QLabel* arrow = new QLabel(expanded ? QStringLiteral("▾")
                                     : QStringLiteral("▸"));
  arrow->setStyleSheet("color: #9AA1AD; font-size: 14px;");

  QHBoxLayout* headLayout = new QHBoxLayout(head);
  headLayout->setContentsMargins(0, 0, 0, 0);
  headLayout->setSpacing(12);
  headLayout->addWidget(iconLabel, 0, Qt::AlignVCenter);
  headLayout->addWidget(label, 1, Qt::AlignVCenter);
  headLayout->addStretch(1);
  headLayout->addWidget(arrow, 0, Qt::AlignVCenter);

  content->setVisible(expanded);
  QObject::connect(head, &QPushButton::clicked, head,
                   [content, arrow] {
                     const bool show = !content->isVisible();
                     content->setVisible(show);
                     arrow->setText(show ? QStringLiteral("▾")
                                         : QStringLiteral("▸"));
                   });

  v->addWidget(head);
  v->addWidget(content);
  return box;
}

// A capability pill: leading glyph icon + text, colored by kind.
// kind: 0 = allow (green), 1 = must (amber), 2 = forbid (red).
QLabel* capPill(const QString& glyph, const QString& text, int kind) {
  const char* bg = kind == 0 ? "#173E2B" : kind == 1 ? "#3A2E14" : "#3A1A1C";
  const char* fg = kind == 0 ? "#3FCF7F" : kind == 1 ? "#E0A23C" : "#F0686D";
  QLabel* l = new QLabel(glyph + "  " + text);
  l->setStyleSheet(QStringLiteral("background: %1; color: %2; "
                                  "border-radius: 10px; padding: 6px 12px; "
                                  "font-size: 12px; font-weight: 600;")
                       .arg(bg, fg));
  return l;
}
}  // namespace

LauncherWindow::LauncherWindow(QWidget* parent) : QMainWindow(parent) {
  setWindowTitle(tr("open.mp Server Launcher"));

  QWidget* central = new QWidget(this);
  central->setStyleSheet("background: #282C34; color: #C8CDD6;");
  QVBoxLayout* root = new QVBoxLayout(central);
  root->setContentsMargins(0, 0, 0, 0);
  root->setSpacing(0);

  // License model — detected from the bundled text, refreshed from GitHub.
  license_ = new LicenseInfo(this);
  connect(license_, &LicenseInfo::changed, this,
          [this] { rebuildLicense(); });

  root->addWidget(buildHeader());

  tabs_ = new QTabWidget;
  tabs_->setDocumentMode(true);
  tabs_->setIconSize(QSize(16, 16));
  tabs_->addTab(buildServerTab(), tr("Server"));
  tabs_->addTab(buildConfigTab(), tr("Config"));
  tabs_->addTab(buildBansTab(), tr("Bans"));
  tabs_->addTab(buildLicenseTab(), tr("License"));
  // Tab icons from Apple SF Symbols (falls back to QStyle if unavailable).
  QStyle* st = style();
  auto tabIcon = [&](const QString& sym, QStyle::StandardPixmap fallback) {
    QIcon ic = SymbolIcon::load(sym, 16);
    return ic.isNull() ? st->standardIcon(fallback) : ic;
  };
  tabs_->setTabIcon(0, tabIcon("server.rack", QStyle::SP_ComputerIcon));
  tabs_->setTabIcon(1, tabIcon("gearshape", QStyle::SP_FileDialogDetailedView));
  tabs_->setTabIcon(2, tabIcon("person.slash", QStyle::SP_MessageBoxCritical));
  tabs_->setTabIcon(3, tabIcon("doc.text", QStyle::SP_FileDialogInfoView));
  QWidget* tabsWrap = new QWidget;
  QVBoxLayout* tw = new QVBoxLayout(tabsWrap);
  tw->setContentsMargins(20, 4, 20, 0);
  tw->addWidget(tabs_);
  root->addWidget(tabsWrap, 1);

  setCentralWidget(central);
  setMinimumSize(620, 480);
  resize(680, 560);

  refreshCards();
  loadConfigIntoForm();
  loadBans();
  setServerRunningUi(false);

  // Telemetry manager: only sends events when the user has consented.
  telemetry_ = new TelemetryManager(this);
  consentPopupPending_ = telemetry_ && !telemetry_->hasConsent();

  // Async update check on launch.
  Updater* up = new Updater(this);
  connect(up, &Updater::finished, this, &LauncherWindow::onUpdateChecked);
  up->check();

  // Refresh the license live from the repo so changing it there updates the
  // pills here automatically.
  license_->fetchFromGitHub(AppInfo::kUpdateOwner, AppInfo::kUpdateRepo);

  // Optional menu-bar (tray) presence, controlled from Settings.
  QSettings s;
  if (s.value("ShowInMenuBar", false).toBool()) {
    tray_ = new QSystemTrayIcon(windowIcon(), this);
    QMenu* m = new QMenu(this);
    m->addAction(tr("Show Launcher"), this, [this] { show(); raise(); });
    m->addAction(tr("Quit"), this, [this] { quitting_ = true; qApp->quit(); });
    tray_->setContextMenu(m);
    tray_->setToolTip(tr("open.mp Server Launcher"));
    tray_->show();
  }

  if (telemetry_->enabled()) {
    telemetry_->sendEvent(QStringLiteral("app_launched"));
  }
}

// ---------------------------------------------------------------- header ----

QWidget* LauncherWindow::buildHeader() {
  QWidget* bar = new QWidget;
  QHBoxLayout* h = new QHBoxLayout(bar);
  h->setContentsMargins(20, 16, 20, 8);
  h->setSpacing(10);

  QLabel* title = new QLabel(tr("open.mp Server Launcher"));
  title->setStyleSheet("font-size: 20px; font-weight: 600; color: #FFFFFF;");
  h->addWidget(title);
  h->addStretch(1);

  // Update button (hidden until an update is found), then version pill,
  // then Settings — laid out: [update] [v pill] [settings].
  updateButton_ = new QPushButton;
  updateButton_->setCursor(Qt::PointingHandCursor);
  updateButton_->setVisible(false);
  updateButton_->setStyleSheet(kGreenBtn);
  connect(updateButton_, &QPushButton::clicked, this, [this] {
    if (!updateUrl_.isEmpty()) {
      QDesktopServices::openUrl(QUrl(updateUrl_));
    }
  });
  h->addWidget(updateButton_);

  // Subtle, bordered version pill (not a loud filled chip).
  versionPill_ = new QLabel("v" + AppInfo::kVersion);
  versionPill_->setStyleSheet(
      "background: transparent; color: #9AA1AD; border: 1px solid #333A45; "
      "border-radius: 9px; font-size: 12px; font-weight: 600; padding: 4px 10px;");
  h->addWidget(versionPill_);

  // Bigger, bordered settings button.
  QToolButton* settings = new QToolButton;
  settings->setText("⚙");
  settings->setCursor(Qt::PointingHandCursor);
  settings->setToolTip(tr("Settings"));
  settings->setFixedSize(38, 34);
  settings->setStyleSheet(
      "QToolButton { border: 1px solid #333A45; border-radius: 9px; "
      "color: #C8CDD6; font-size: 18px; background: transparent; }"
      "QToolButton:hover { background: #262B34; border-color: #7B5CFF; }");
  connect(settings, &QToolButton::clicked, this,
          [this] { showSettingsMenu(); });
  h->addWidget(settings);

  return bar;
}

void LauncherWindow::showSettingsMenu() {
  QWidget* central = centralWidget();
  if (!central) {
    return;
  }

  if (settingsOverlay_) {
    settingsOverlay_->close();
    return;
  }

  settingsOverlay_ = new QWidget(central);
  settingsOverlay_->setObjectName("settingsOverlay");
  settingsOverlay_->setStyleSheet("background: rgba(10, 12, 18, 200);");
  settingsOverlay_->setAttribute(Qt::WA_DeleteOnClose);
  settingsOverlay_->setGeometry(central->rect());
  settingsOverlay_->show();

  const int panelWidth = qMin(central->width() - 80, 520);
  const int panelHeight = qMin(central->height() - 80, 460);
  QFrame* surface = new QFrame(settingsOverlay_);
  surface->setObjectName("settingsSurface");
  surface->setStyleSheet(
      "#settingsSurface { background: #20242C; border: 1px solid #333A45; "
      "border-radius: 16px; }");
  surface->setFixedSize(panelWidth, panelHeight);
  surface->move((central->width() - panelWidth) / 2,
                (central->height() - panelHeight) / 2);

  QVBoxLayout* v = new QVBoxLayout(surface);
  v->setContentsMargins(20, 18, 20, 18);
  v->setSpacing(16);

  QHBoxLayout* titleRow = new QHBoxLayout;
  QLabel* title = new QLabel(tr("Settings"));
  title->setStyleSheet("font-size: 16px; font-weight: 700; color: #FFFFFF;");
  titleRow->addWidget(title);
  titleRow->addStretch(1);
  QToolButton* close = new QToolButton;
  close->setText("✕");
  close->setCursor(Qt::PointingHandCursor);
  close->setFixedSize(28, 28);
  close->setStyleSheet(
      "QToolButton { border: none; border-radius: 14px; color: #9AA1AD; "
      "font-size: 14px; background: #2A2F38; }"
      "QToolButton:hover { background: #E5484D; color: white; }");
  connect(close, &QToolButton::clicked, settingsOverlay_, &QWidget::close);
  titleRow->addWidget(close);
  v->addLayout(titleRow);

  auto toggleRow = [&](const QString& t, const QString& sub,
                       bool checked) -> ToggleSwitch* {
    QHBoxLayout* r = new QHBoxLayout;
    QVBoxLayout* txt = new QVBoxLayout;
    txt->setSpacing(2);
    QLabel* tl = new QLabel(t);
    tl->setStyleSheet("color: #E6E9EE; font-weight: 600; font-size: 14px;");
    QLabel* sl = new QLabel(sub);
    sl->setStyleSheet("color: #9AA1AD; font-size: 11px;");
    txt->addWidget(tl);
    txt->addWidget(sl);
    r->addLayout(txt, 1);
    ToggleSwitch* sw = new ToggleSwitch;
    sw->setChecked(checked);
    r->addWidget(sw, 0, Qt::AlignVCenter);
    v->addLayout(r);
    return sw;
  };

  ToggleSwitch* startup =
      toggleRow(tr("Run at login"),
                tr("Launch automatically when you sign in."),
                QSettings().value("RunAtLogin", false).toBool());
  ToggleSwitch* menubar =
      toggleRow(tr("Show in menu bar"),
                tr("Keep an icon in the macOS menu bar."),
                QSettings().value("ShowInMenuBar", false).toBool());

  connect(startup, &ToggleSwitch::toggled, settingsOverlay_, [this](bool on) {
    QSettings().setValue("RunAtLogin", on);
#ifdef Q_OS_MACOS
    const QString appPath =
        QDir(QCoreApplication::applicationDirPath() + "/../..").absolutePath();
    if (on) {
      QProcess::execute(
          "osascript",
          {"-e", QStringLiteral("tell application \"System Events\" to make "
                                "login item at end with properties "
                                "{path:\"%1\", hidden:false}")
                     .arg(appPath)});
    } else {
      QProcess::execute(
          "osascript",
          {"-e", QStringLiteral("tell application \"System Events\" to delete "
                                "login item \"open.mp Server Launcher\"")});
    }
#endif
  });

  connect(menubar, &ToggleSwitch::toggled, settingsOverlay_, [this](bool on) {
    QSettings().setValue("ShowInMenuBar", on);
    if (on && !tray_) {
      tray_ = new QSystemTrayIcon(windowIcon(), this);
      QMenu* m = new QMenu(this);
      m->addAction(tr("Show Launcher"), this, [this] { show(); raise(); });
      m->addAction(tr("Quit"), this,
                   [this] { quitting_ = true; qApp->quit(); });
      tray_->setContextMenu(m);
      tray_->show();
    } else if (!on && tray_) {
      tray_->hide();
      tray_->deleteLater();
      tray_ = nullptr;
    }
  });

  QLabel* telemetryHdr = new QLabel(tr("Telemetry"));
  telemetryHdr->setStyleSheet(
      "color: #E6E9EE; font-weight: 700; font-size: 13px; background: transparent;");
  v->addWidget(telemetryHdr);

  QLabel* telemetryInfo = new QLabel(
      tr("Optional anonymous telemetry helps improve the app. No personal data, "
         "usernames, passwords, or IP addresses are collected. Data is sent only "
         "when telemetry is enabled and environment variables are configured."));
  telemetryInfo->setWordWrap(true);
  telemetryInfo->setStyleSheet("color: #9AA1AD; font-size: 12px; background: transparent;");
  v->addWidget(telemetryInfo);

  ToggleSwitch* telemetrySwitch =
      toggleRow(tr("Enable anonymous telemetry"),
                tr("Send anonymous usage events."),
                telemetry_->enabled());
  ToggleSwitch* extendedSwitch =
      toggleRow(tr("Enable extended diagnostics"),
                tr("Include additional anonymous server config details."),
                telemetry_->extended());
  extendedSwitch->setEnabled(telemetry_->enabled());

  QLabel* envInfo = new QLabel(
      tr("Please configure telemetry endpoint and key as environment variables "
         "before launching the app. No keys are stored in the repository."));
  envInfo->setWordWrap(true);
  envInfo->setStyleSheet("color: #9AA1AD; font-size: 12px; background: transparent;");
  v->addWidget(envInfo);

  connect(telemetrySwitch, &ToggleSwitch::toggled, telemetry_,
          &TelemetryManager::setEnabled);
  connect(extendedSwitch, &ToggleSwitch::toggled, telemetry_,
          &TelemetryManager::setExtended);
  connect(telemetrySwitch, &ToggleSwitch::toggled, extendedSwitch,
          &ToggleSwitch::setEnabled);

  connect(settingsOverlay_, &QWidget::destroyed, [this] {
    settingsOverlay_ = nullptr;
  });
}

void LauncherWindow::onUpdateChecked(bool available, const QString& version,
                                     const QString& htmlUrl) {
  if (!available) {
    return;
  }
  updateUrl_ = htmlUrl;
  updateButton_->setText(tr("⬆  Update %1").arg(version));
  updateButton_->setVisible(true);
}

void LauncherWindow::showEvent(QShowEvent* event) {
  QMainWindow::showEvent(event);
  if (consentPopupPending_ && telemetry_ && !telemetry_->hasConsent()) {
    consentPopupPending_ = false;
    maybeAskTelemetryConsent();
  }
}

void LauncherWindow::maybeAskTelemetryConsent() {
  if (!telemetry_ || telemetry_->hasConsent()) {
    return;
  }

  QWidget* central = centralWidget();
  if (!central) {
    return;
  }

  consentOverlay_ = new QWidget(central);
  consentOverlay_->setObjectName("telemetryOverlay");
  consentOverlay_->setStyleSheet("background: rgba(10, 12, 18, 200);");
  consentOverlay_->setAttribute(Qt::WA_DeleteOnClose);
  consentOverlay_->setGeometry(central->rect());
  consentOverlay_->show();

  QFrame* card = new QFrame(consentOverlay_);
  card->setStyleSheet(
      "background: #20242C; border: 1px solid #333A45; border-radius: 16px;");
  card->setFixedSize(520, 260);
  card->move((consentOverlay_->width() - card->width()) / 2,
             (consentOverlay_->height() - card->height()) / 2);

  QVBoxLayout* v = new QVBoxLayout(card);
  v->setContentsMargins(22, 20, 22, 20);
  v->setSpacing(12);

  QLabel* title = new QLabel(tr("Help improve open.mp Server Launcher"));
  title->setStyleSheet("font-size: 16px; font-weight: 700; color: #FFFFFF;");
  v->addWidget(title);

  QLabel* details = new QLabel(tr(
      "Allow anonymous telemetry to be sent to Supabase. This helps us "
      "improve launcher behavior and diagnose issues. No personal data, "
      "usernames, passwords, or IP addresses are collected."));
  details->setWordWrap(true);
  details->setStyleSheet("color: #C8CDD6; font-size: 13px; background: transparent;");
  v->addWidget(details);

  QLabel* standard = new QLabel(tr(
      "Standard telemetry includes app version, OS version, architecture, "
      "feature usage, and basic event counts."));
  standard->setWordWrap(true);
  standard->setStyleSheet("color: #9AA1AD; font-size: 12px; background: transparent;");
  v->addWidget(standard);

  QLabel* extra = new QLabel(tr(
      "If you enable extended diagnostics later, we can optionally send "
      "anonymous server config details such as port, gamemode, and filterscript."));
  extra->setWordWrap(true);
  extra->setStyleSheet("color: #9AA1AD; font-size: 12px; background: transparent;");
  v->addWidget(extra);

  QHBoxLayout* buttons = new QHBoxLayout;
  buttons->setSpacing(10);
  QPushButton* reject = new QPushButton(tr("No thanks"));
  reject->setCursor(Qt::PointingHandCursor);
  reject->setStyleSheet(kNeutralBtn);
  QPushButton* accept = new QPushButton(tr("Enable telemetry"));
  accept->setCursor(Qt::PointingHandCursor);
  accept->setStyleSheet(kGreenBtn);
  buttons->addStretch(1);
  buttons->addWidget(reject);
  buttons->addWidget(accept);
  v->addLayout(buttons);

  connect(reject, &QPushButton::clicked, consentOverlay_, [this] {
    if (telemetry_) {
      telemetry_->setConsentAsked(true);
      telemetry_->setEnabled(false);
    }
    consentOverlay_->close();
  });
  connect(accept, &QPushButton::clicked, consentOverlay_, [this] {
    if (telemetry_) {
      telemetry_->setConsentAsked(true);
      telemetry_->setEnabled(true);
      telemetry_->sendEvent(QStringLiteral("app_launched"));
    }
    consentOverlay_->close();
  });
  connect(consentOverlay_, &QWidget::destroyed, [this] {
    consentOverlay_ = nullptr;
  });
}

// --------------------------------------------------------------- server  ----

QWidget* LauncherWindow::buildServerTab() {
  QWidget* page = new QWidget;
  QVBoxLayout* v = new QVBoxLayout(page);
  v->setContentsMargins(20, 16, 20, 20);
  v->setSpacing(16);

  QHBoxLayout* cards = new QHBoxLayout;
  cards->setSpacing(16);
  cards->addWidget(buildCrossOverCard(), 1);
  cards->addWidget(buildServerFilesCard(), 1);
  v->addLayout(cards);

  // Start / Stop / Restart row.
  QHBoxLayout* ctl = new QHBoxLayout;
  ctl->setSpacing(10);
  startButton_ = new QPushButton(tr("▶  Start server"));
  startButton_->setMinimumHeight(40);
  startButton_->setCursor(Qt::PointingHandCursor);
  startButton_->setStyleSheet(kGreenBtn);
  connect(startButton_, &QPushButton::clicked, this, [this] { startServer(); });

  stopButton_ = new QPushButton(tr("■  Stop server"));
  stopButton_->setMinimumHeight(40);
  stopButton_->setCursor(Qt::PointingHandCursor);
  stopButton_->setStyleSheet(kRedBtn);
  connect(stopButton_, &QPushButton::clicked, this, [this] { stopServer(); });

  restartButton_ = new QPushButton(tr("⟳  Restart server"));
  restartButton_->setMinimumHeight(40);
  restartButton_->setCursor(Qt::PointingHandCursor);
  restartButton_->setStyleSheet(kNeutralBtn);
  connect(restartButton_, &QPushButton::clicked, this,
          [this] { restartServer(); });

  ctl->addWidget(startButton_, 1);
  ctl->addWidget(stopButton_, 1);
  ctl->addWidget(restartButton_, 1);
  v->addLayout(ctl);

  // Log view + open-log-file button.
  QHBoxLayout* logHdr = new QHBoxLayout;
  QLabel* logLbl = new QLabel(tr("Server log"));
  logLbl->setStyleSheet("font-weight: 600; color: #FFFFFF;");
  logHdr->addWidget(logLbl);
  logHdr->addStretch(1);
  QPushButton* openLog = new QPushButton(tr("Open log.txt"));
  openLog->setCursor(Qt::PointingHandCursor);
  openLog->setStyleSheet(kNeutralBtn);
  connect(openLog, &QPushButton::clicked, this, [this] {
    const QString p = logPath();
    if (QFileInfo::exists(p)) {
      QDesktopServices::openUrl(QUrl::fromLocalFile(p));
    } else {
      QMessageBox::information(this, tr("Log"),
                               tr("No log.txt in the server folder yet."));
    }
  });
  logHdr->addWidget(openLog);
  v->addLayout(logHdr);

  log_ = new QPlainTextEdit;
  log_->setReadOnly(true);
  log_->setStyleSheet(
      "background: #1B1F25; color: #C8CDD6; border: 1px solid #3A3F4B; "
      "border-radius: 8px;");
  QFont mono("Menlo");
  mono.setStyleHint(QFont::Monospace);
  log_->setFont(mono);
  v->addWidget(log_, 1);

  return page;
}

QWidget* LauncherWindow::buildCrossOverCard() {
  QFrame* card = cardFrame();
  QVBoxLayout* cv = new QVBoxLayout(card);
  cv->setContentsMargins(18, 16, 18, 16);
  cv->setSpacing(10);

  QHBoxLayout* titleRow = new QHBoxLayout;
  QLabel* t = new QLabel(tr("CrossOver"));
  t->setStyleSheet("font-size: 16px; font-weight: 600; color: #FFFFFF;");
  titleRow->addWidget(t);
  titleRow->addStretch(1);
  cxPill_ = new QLabel;
  cxPill_->setAlignment(Qt::AlignCenter);
  titleRow->addWidget(cxPill_);
  cv->addLayout(titleRow);

  cxDetail_ = new QLabel;
  cxDetail_->setWordWrap(true);
  cxDetail_->setStyleSheet("color: #9AA1AD; font-size: 12px; background: transparent; border: none;");
  cv->addWidget(cxDetail_, 1);

  QHBoxLayout* btnRow = new QHBoxLayout;
  cxSetupButton_ = new QPushButton;
  cxSetupButton_->setCursor(Qt::PointingHandCursor);
  cxSetupButton_->setMinimumHeight(34);
  cxSetupButton_->setStyleSheet(kPrimaryBtn);
  connect(cxSetupButton_, &QPushButton::clicked, this, [this] { setupBottle(); });
  btnRow->addWidget(cxSetupButton_, 0);

  cxDeleteButton_ = new QPushButton(tr("Delete bottle"));
  cxDeleteButton_->setCursor(Qt::PointingHandCursor);
  cxDeleteButton_->setMinimumHeight(34);
  cxDeleteButton_->setStyleSheet(kRedBtn);
  connect(cxDeleteButton_, &QPushButton::clicked, this, [this] { deleteBottle(); });
  btnRow->addWidget(cxDeleteButton_, 0);
  btnRow->addStretch(1);
  cv->addLayout(btnRow);
  return card;
}

QWidget* LauncherWindow::buildServerFilesCard() {
  QFrame* card = cardFrame();
  QVBoxLayout* cv = new QVBoxLayout(card);
  cv->setContentsMargins(18, 16, 18, 16);
  cv->setSpacing(10);

  QHBoxLayout* titleRow = new QHBoxLayout;
  QLabel* t = new QLabel(tr("Server files"));
  t->setStyleSheet("font-size: 16px; font-weight: 600; color: #FFFFFF;");
  titleRow->addWidget(t);
  titleRow->addStretch(1);
  filesPill_ = new QLabel;
  filesPill_->setAlignment(Qt::AlignCenter);
  titleRow->addWidget(filesPill_);
  cv->addLayout(titleRow);

  filesDetail_ = new QLabel;
  filesDetail_->setWordWrap(true);
  filesDetail_->setStyleSheet("color: #9AA1AD; font-size: 12px; background: transparent; border: none;");
  cv->addWidget(filesDetail_, 1);
  return card;
}

void LauncherWindow::refreshCards() {
  if (!CrossOver::isInstalled()) {
    stylePill(cxPill_, tr("● Not detected"), false);
    cxDetail_->setText(tr(
        "CrossOver was not found in /Applications. It runs the Windows open.mp "
        "server under Wine. Install CrossOver to launch the server on macOS."));
    cxSetupButton_->setVisible(false);
    cxDeleteButton_->setVisible(false);
  } else {
    const QString ver = CrossOver::version();
    stylePill(cxPill_,
              ver.isEmpty() ? tr("● Detected") : tr("● Detected · v%1").arg(ver),
              true);
    if (CrossOver::bottleExists()) {
      cxDetail_->setText(
          tr("The 32-bit \"%1\" bottle is ready. The server runs through it.")
              .arg(CrossOver::kBottle));
      cxSetupButton_->setVisible(false);
      cxDeleteButton_->setVisible(true);
    } else {
      cxDetail_->setText(
          tr("No \"%1\" bottle yet. Create a 32-bit bottle to run the server "
             "through CrossOver.")
              .arg(CrossOver::kBottle));
      cxSetupButton_->setText(tr("Set up %1 bottle").arg(CrossOver::kBottle));
      cxSetupButton_->setEnabled(true);
      cxSetupButton_->setVisible(true);
      cxDeleteButton_->setVisible(false);
    }
  }

  const QStringList missing = CrossOver::missingFiles();
  if (missing.isEmpty()) {
    stylePill(filesPill_, tr("● Detected"), true);
    filesDetail_->setText(
        tr("The server files (%1) are in this folder. Keep the launcher next to "
           "omp-server.exe, config.json, gamemodes/, filterscripts/, and components/.")
            .arg(CrossOver::requiredFiles().join(", ")));
  } else {
    stylePill(filesPill_, tr("● Not detected"), false);
    filesDetail_->setText(
        tr("Missing from this folder: %1. Place the launcher beside omp-server.exe and "
           "the open.mp server files in the same folder.")
            .arg(missing.join(", ")));
  }
}

void LauncherWindow::setupBottle() {
  cxSetupButton_->setText(tr("Creating bottle…"));
  cxSetupButton_->repaint();  // block after repaint -> native beachball
  QString error;
  const bool ok = CrossOver::createBottle(&error);
  if (!ok) {
    QMessageBox::warning(this, tr("CrossOver"),
                         tr("Could not create the \"%1\" bottle.\n\n%2")
                             .arg(CrossOver::kBottle, error));
  }
  refreshCards();
}

void LauncherWindow::deleteBottle() {
  QMessageBox box(this);
  box.setWindowTitle(tr("Delete bottle"));
  box.setText(tr("Delete the 32-bit \"%1\" CrossOver bottle?").arg(CrossOver::kBottle));
  box.setInformativeText(
      tr("You can recreate it afterwards with \"Set up %1 bottle\".")
          .arg(CrossOver::kBottle));
  box.setIcon(QMessageBox::Warning);
  box.setStandardButtons(QMessageBox::Yes | QMessageBox::Cancel);
  box.setDefaultButton(QMessageBox::Cancel);
  if (box.exec() != QMessageBox::Yes) {
    return;
  }
  cxDeleteButton_->setText(tr("Deleting…"));
  cxDeleteButton_->repaint();
  QString error;
  const bool ok = CrossOver::deleteBottle(&error);
  cxDeleteButton_->setText(tr("Delete bottle"));
  if (!ok) {
    QMessageBox::warning(this, tr("CrossOver"),
                         tr("Could not delete the \"%1\" bottle.\n\n%2")
                             .arg(CrossOver::kBottle, error));
  }
  refreshCards();
}

bool LauncherWindow::preflight() {
  QStringList problems;
  if (!CrossOver::isInstalled()) {
    problems << tr("• CrossOver is not installed.");
  } else if (!CrossOver::bottleExists()) {
    problems << tr("• The 32-bit \"%1\" bottle has not been created yet.")
                    .arg(CrossOver::kBottle);
  }
  const QStringList missing = CrossOver::missingFiles();
  if (!missing.isEmpty()) {
    problems << tr("• Missing server files: %1.").arg(missing.join(", "));
  }
  if (problems.isEmpty()) {
    return true;
  }
  QMessageBox::warning(
      this, tr("Cannot start server"),
      tr("Running the server needs CrossOver and the open.mp server files:\n\n%1")
          .arg(problems.join("\n\n")));
  return false;
}

void LauncherWindow::appendLog(const QString& text) {
  if (text.isEmpty()) {
    return;
  }
  log_->moveCursor(QTextCursor::End);
  log_->insertPlainText(text);
  log_->moveCursor(QTextCursor::End);
}

void LauncherWindow::setServerRunningUi(bool running) {
  startButton_->setEnabled(!running);
  stopButton_->setEnabled(running);
  restartButton_->setEnabled(running);
}

void LauncherWindow::startServer() {
  if (!preflight()) {
    return;
  }
  // Preflight: if a server is already running (this app or external), kill it
  // first so we don't double-bind the port.
  if (CrossOver::serverRunning() ||
      (server_ && server_->state() != QProcess::NotRunning)) {
    appendLog(tr("[a server was already running — stopping it first]\n"));
    if (server_ && server_->state() != QProcess::NotRunning) {
      server_->kill();
      server_->waitForFinished(5000);
    }
    CrossOver::killRunningServers();
  }

  const QString wrapper = QCoreApplication::applicationDirPath() +
                          QStringLiteral("/run-omp-server-wine.sh");
  const QString serverDir = CrossOver::serverDir();
  if (!QFileInfo::exists(wrapper)) {
    QMessageBox::warning(this, tr("Server Launcher"),
                         tr("run-omp-server-wine.sh is missing from the app."));
    return;
  }

  log_->clear();
  appendLog(tr("Starting open.mp server in the \"%1\" bottle…\n\n")
                .arg(CrossOver::kBottle));

  server_ = new QProcess(this);
  server_->setProcessChannelMode(QProcess::MergedChannels);
  server_->setWorkingDirectory(serverDir);
  QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
  env.insert(QStringLiteral("OMP_SERVER_DIR"), serverDir);
  server_->setProcessEnvironment(env);

  connect(server_, &QProcess::readyRead, this,
          [this] { appendLog(QString::fromLocal8Bit(server_->readAll())); });
  connect(server_,
          QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
          [this](int code, QProcess::ExitStatus) {
            appendLog(tr("\n[server exited, code %1]\n").arg(code));
            setServerRunningUi(false);
            server_->deleteLater();
            server_ = nullptr;
          });
  connect(server_, &QProcess::errorOccurred, this,
          [this](QProcess::ProcessError) {
            appendLog(tr("\n[failed to start: %1]\n").arg(server_->errorString()));
          });

  setServerRunningUi(true);
  server_->start(wrapper, {});
  if (telemetry_ && telemetry_->enabled()) {
    telemetry_->sendEvent(QStringLiteral("server_started"));
  }
}

void LauncherWindow::stopServer() {
  if (server_ && server_->state() != QProcess::NotRunning) {
    appendLog(tr("\n[stopping server]\n"));
    server_->kill();
  }
  CrossOver::killRunningServers();
  setServerRunningUi(false);
  if (telemetry_ && telemetry_->enabled()) {
    telemetry_->sendEvent(QStringLiteral("server_stopped"));
  }
}

void LauncherWindow::restartServer() {
  appendLog(tr("\n[restarting server]\n"));
  if (server_ && server_->state() != QProcess::NotRunning) {
    server_->kill();
    server_->waitForFinished(5000);
  }
  CrossOver::killRunningServers();
  startServer();
  if (telemetry_ && telemetry_->enabled()) {
    telemetry_->sendEvent(QStringLiteral("server_restarted"));
  }
}

// --------------------------------------------------------------- config  ----

QString LauncherWindow::configPath() const {
  return CrossOver::serverDir() + QStringLiteral("/config.json");
}
QString LauncherWindow::bansPath() const {
  return CrossOver::serverDir() + QStringLiteral("/bans.json");
}
QString LauncherWindow::logPath() const {
  return CrossOver::serverDir() + QStringLiteral("/log.txt");
}

QWidget* LauncherWindow::buildConfigTab() {
  QWidget* page = new QWidget;
  QVBoxLayout* outer = new QVBoxLayout(page);
  outer->setContentsMargins(20, 12, 20, 12);
  outer->setSpacing(12);

  QLabel* intro = new QLabel(tr(
      "Edit the main open.mp server settings in one screen. Known config values "
      "are preserved when saving.") );
  intro->setWordWrap(true);
  intro->setStyleSheet("color: #9AA1AD; font-size: 12px; background: transparent;");
  outer->addWidget(intro);

  QScrollArea* pageScroll = new QScrollArea(page);
  pageScroll->setWidgetResizable(true);
  pageScroll->setFrameShape(QFrame::NoFrame);
  pageScroll->setStyleSheet("background: transparent;");

  QWidget* scrollContent = new QWidget;
  scrollContent->setObjectName("configContent");
  scrollContent->setStyleSheet("background: transparent;");
  QVBoxLayout* scrollLayout = new QVBoxLayout(scrollContent);
  scrollLayout->setContentsMargins(0, 0, 0, 0);
  scrollLayout->setSpacing(12);
  pageScroll->setWidget(scrollContent);

  outer->addWidget(pageScroll);

  QFrame* card = new QFrame(scrollContent);
  card->setObjectName("configCard");
  card->setStyleSheet(
      "#configCard { background: #171A20; border: 1px solid #2A2F38; "
      "border-radius: 10px; }");
  QVBoxLayout* v = new QVBoxLayout(card);
  v->setContentsMargins(16, 14, 16, 16);
  v->setSpacing(20);
  scrollLayout->addWidget(card);

  auto sectionLabel = [&](const QString& text) {
    QLabel* l = new QLabel(text);
    l->setStyleSheet("color: #E6E9EE; font-weight: 700; font-size: 14px; "
                     "background: transparent;");
    return l;
  };
  auto labelFor = [&](const QString& text) {
    QLabel* l = new QLabel(text);
    l->setStyleSheet("color: #C8CDD6; background: transparent; font-size: 13px;");
    l->setAutoFillBackground(false);
    return l;
  };

  auto fileCombo = []() {
    QComboBox* c = new QComboBox;
    c->setEditable(true);
    c->lineEdit()->setAlignment(Qt::AlignLeft);
    c->setStyleSheet("QComboBox { text-align: left; }");
    return c;
  };

  // Server section.
  QWidget* serverSection = new QWidget;
  QGridLayout* serverGrid = new QGridLayout(serverSection);
  serverGrid->setContentsMargins(0, 0, 0, 0);
  serverGrid->setHorizontalSpacing(18);
  serverGrid->setVerticalSpacing(10);
  serverGrid->setColumnStretch(1, 1);

  cfgHostname_ = new QLineEdit;
  cfgMaxPlayers_ = new QSpinBox;
  cfgMaxPlayers_->setRange(1, 1000);
  cfgPassword_ = new QLineEdit;

  serverGrid->addWidget(sectionLabel(tr("Server")), 0, 0, 1, 2);
  serverGrid->addWidget(labelFor(tr("Server name")), 1, 0);
  serverGrid->addWidget(cfgHostname_, 1, 1);
  serverGrid->addWidget(labelFor(tr("Max players")), 2, 0);
  serverGrid->addWidget(cfgMaxPlayers_, 2, 1);
  serverGrid->addWidget(labelFor(tr("Password")), 3, 0);
  serverGrid->addWidget(cfgPassword_, 3, 1);
  v->addWidget(serverSection);

  // Network section.
  QWidget* networkSection = new QWidget;
  QGridLayout* networkGrid = new QGridLayout(networkSection);
  networkGrid->setContentsMargins(0, 0, 0, 0);
  networkGrid->setHorizontalSpacing(18);
  networkGrid->setVerticalSpacing(10);
  networkGrid->setColumnStretch(1, 1);

  cfgPort_ = new QSpinBox;
  cfgPort_->setRange(1, 65535);
  cfgRcon_ = new QLineEdit;

  networkGrid->addWidget(sectionLabel(tr("Network")), 0, 0, 1, 2);
  networkGrid->addWidget(labelFor(tr("Port")), 1, 0);
  networkGrid->addWidget(cfgPort_, 1, 1);
  networkGrid->addWidget(labelFor(tr("RCON password")), 2, 0);
  networkGrid->addWidget(cfgRcon_, 2, 1);
  v->addWidget(networkSection);

  // Scripts section.
  QWidget* scriptsSection = new QWidget;
  QGridLayout* scriptsGrid = new QGridLayout(scriptsSection);
  scriptsGrid->setContentsMargins(0, 0, 0, 0);
  scriptsGrid->setHorizontalSpacing(18);
  scriptsGrid->setVerticalSpacing(10);
  scriptsGrid->setColumnStretch(1, 1);

  cfgGamemode_ = fileCombo();
  cfgFilterscript_ = fileCombo();

  scriptsGrid->addWidget(sectionLabel(tr("Scripts")), 0, 0, 1, 2);
  scriptsGrid->addWidget(labelFor(tr("Gamemode")), 1, 0);
  scriptsGrid->addWidget(cfgGamemode_, 1, 1);
  scriptsGrid->addWidget(labelFor(tr("Filterscript")), 2, 0);
  scriptsGrid->addWidget(cfgFilterscript_, 2, 1);
  v->addWidget(scriptsSection);

  advancedContainer_ = new QWidget;
  advancedContainer_->setStyleSheet("background: transparent;");
  QVBoxLayout* advancedLayout = new QVBoxLayout(advancedContainer_);
  advancedLayout->setContentsMargins(0, 0, 0, 0);
  advancedLayout->setSpacing(12);
  v->addWidget(advancedContainer_, 1);

  // Save / reload controls.
  QHBoxLayout* btns = new QHBoxLayout;
  btns->addStretch(1);
  QPushButton* reload = new QPushButton(tr("Reload"));
  reload->setCursor(Qt::PointingHandCursor);
  reload->setStyleSheet(kNeutralBtn);
  connect(reload, &QPushButton::clicked, this, [this] { loadConfigIntoForm(); });
  QPushButton* save = new QPushButton(tr("Save config"));
  save->setCursor(Qt::PointingHandCursor);
  save->setStyleSheet(kPrimaryBtn);
  connect(save, &QPushButton::clicked, this, [this] { saveConfigFromForm(); });
  btns->addWidget(reload);
  btns->addWidget(save);
  outer->addLayout(btns);

  return page;
}

void LauncherWindow::populateScriptDropdowns() {
  const QString dir = CrossOver::serverDir();
  QIcon fileIcon = SymbolIcon::load("doc.text", 13);
  if (fileIcon.isNull()) {
    fileIcon = style()->standardIcon(QStyle::SP_FileIcon);
  }
  auto fill = [&](QComboBox* box, const QString& sub) {
    const QString cur = box->currentText();
    box->clear();
    box->addItem("");  // allow empty
    QDir d(dir + "/" + sub);
    for (const QString& f :
         d.entryList({"*.amx"}, QDir::Files, QDir::Name)) {
      box->addItem(fileIcon, QFileInfo(f).completeBaseName());
    }
    box->setCurrentText(cur);
  };
  fill(cfgGamemode_, "gamemodes");
  fill(cfgFilterscript_, "filterscripts");
}

namespace {
// Keys handled by the basic form (dotted paths); excluded from Advanced.
bool isBasicKey(const QString& path) {
  static const QStringList basic = {
      "name", "password", "max_players", "network.port", "rcon.password",
      "pawn.main_scripts", "pawn.side_scripts"};
  return basic.contains(path);
}

// Build a type-appropriate editor for a JSON scalar. Returns the widget; the
// caller records (path -> widget) for saving.
QWidget* editorForValue(const QJsonValue& val) {
  if (val.isBool()) {
    ToggleSwitch* sw = new ToggleSwitch;
    sw->setChecked(val.toBool());
    return sw;
  }
  if (val.isDouble()) {
    const double d = val.toDouble();
    if (qFuzzyCompare(d, qRound(d)) && qAbs(d) < 2.1e9) {
      QSpinBox* sb = new QSpinBox;
      sb->setRange(-2147483647, 2147483647);
      sb->setValue(static_cast<int>(d));
      return sb;
    }
    QDoubleSpinBox* sb = new QDoubleSpinBox;
    sb->setRange(-1e12, 1e12);
    sb->setDecimals(5);
    sb->setValue(d);
    return sb;
  }
  QLineEdit* le = new QLineEdit(val.toString());
  return le;
}

QJsonValue valueFromEditor(QWidget* w, const QJsonValue& orig) {
  if (auto* sw = qobject_cast<ToggleSwitch*>(w)) return sw->isChecked();
  if (auto* cb = qobject_cast<QCheckBox*>(w)) return cb->isChecked();
  if (auto* sb = qobject_cast<QSpinBox*>(w)) return sb->value();
  if (auto* sb = qobject_cast<QDoubleSpinBox*>(w)) return sb->value();
  if (auto* le = qobject_cast<QLineEdit*>(w)) return le->text();
  return orig;
}
}  // namespace

void LauncherWindow::rebuildAdvancedConfig() {
  if (!advancedContainer_) {
    return;
  }
  advancedEditors_.clear();
  // Clear the container's layout.
  QLayout* lay = advancedContainer_->layout();
  QLayoutItem* it;
  while ((it = lay->takeAt(0))) {
    if (it->widget()) it->widget()->deleteLater();
    delete it;
  }
  QVBoxLayout* v = static_cast<QVBoxLayout*>(lay);
  v->setContentsMargins(0, 0, 0, 0);
  v->setSpacing(8);

  // A small grid form for one category's scalar keys.
  auto makeCategory = [&](const QString& prefix, const QJsonObject& obj) {
    int added = 0;
    QWidget* section = new QWidget;
    section->setStyleSheet(
        "background: #14171C; border: 1px solid #2A2F38; border-radius: 10px;");
    QVBoxLayout* sl = new QVBoxLayout(section);
    sl->setContentsMargins(14, 14, 14, 14);
    sl->setSpacing(10);

    QLabel* title = new QLabel(prefix.isEmpty() ? tr("General") : prefix);
    title->setStyleSheet("color: #E6E9EE; font-weight: 700; font-size: 13px;");
    sl->addWidget(title);

    QWidget* body = new QWidget;
    body->setStyleSheet("background: transparent;");
    QVBoxLayout* bl = new QVBoxLayout(body);
    bl->setContentsMargins(0, 0, 0, 0);
    bl->setSpacing(10);

    for (auto k = obj.begin(); k != obj.end(); ++k) {
      const QString path = prefix.isEmpty() ? k.key() : prefix + "." + k.key();
      if (k.value().isObject() || k.value().isArray() || isBasicKey(path)) {
        continue;
      }
      QHBoxLayout* r = new QHBoxLayout;
      r->setContentsMargins(0, 0, 0, 0);
      r->setSpacing(14);
      QLabel* l = new QLabel(k.key());
      l->setFixedWidth(220);
      l->setStyleSheet("color: #C8CDD6; background: transparent;");
      QWidget* ed = editorForValue(k.value());
      r->addWidget(l);
      r->addWidget(ed, 1);
      bl->addLayout(r);
      advancedEditors_.append({path, ed});
      ++added;
    }
    if (added == 0) {
      delete section;
      return;
    }

    sl->addWidget(body);
    v->addWidget(section);
  };

  // Top-level scalars first (General), then each nested object as a category.
  makeCategory(QString(), config_);
  for (auto it = config_.begin(); it != config_.end(); ++it) {
    if (it.value().isObject()) {
      makeCategory(it.key(), it.value().toObject());
    }
  }
  v->addStretch(1);
}

void LauncherWindow::applyAdvancedToConfig() {
  // Write each advanced editor back into config_ at its dotted path. Only one
  // level of nesting exists in open.mp's config, so handle "a" and "a.b".
  for (const auto& pair : advancedEditors_) {
    const QStringList parts = pair.first.split('.');
    if (parts.size() == 1) {
      config_.insert(parts[0],
                     valueFromEditor(pair.second, config_.value(parts[0])));
    } else {
      QJsonObject sub = config_.value(parts[0]).toObject();
      sub.insert(parts[1],
                 valueFromEditor(pair.second, sub.value(parts[1])));
      config_.insert(parts[0], sub);
    }
  }
}

void LauncherWindow::loadConfigIntoForm() {
  QFile f(configPath());
  if (!f.open(QIODevice::ReadOnly)) {
    return;
  }
  config_ = QJsonDocument::fromJson(f.readAll()).object();
  f.close();

  populateScriptDropdowns();

  cfgHostname_->setText(config_.value("name").toString());
  cfgPassword_->setText(config_.value("password").toString());
  cfgMaxPlayers_->setValue(config_.value("max_players").toInt(50));

  const QJsonObject net = config_.value("network").toObject();
  cfgPort_->setValue(net.value("port").toInt(7777));

  const QJsonObject rcon = config_.value("rcon").toObject();
  cfgRcon_->setText(rcon.value("password").toString());

  // Gamemodes/filterscripts are arrays of names under pawn.* in open.mp.
  const QJsonObject pawn = config_.value("pawn").toObject();
  const QJsonArray gms = pawn.value("main_scripts").toArray();
  cfgGamemode_->setCurrentText(gms.isEmpty() ? QString()
                                             : gms.first().toString());
  const QJsonArray fss = pawn.value("side_scripts").toArray();
  cfgFilterscript_->setCurrentText(fss.isEmpty() ? QString()
                                                 : fss.first().toString());

  rebuildAdvancedConfig();
}

void LauncherWindow::saveConfigFromForm() {
  // Pull advanced editors back into config_ first, then overwrite basic keys.
  applyAdvancedToConfig();

  // Edit the known keys, leave everything else in config_ untouched.
  config_.insert("name", cfgHostname_->text());
  config_.insert("password", cfgPassword_->text());
  config_.insert("max_players", cfgMaxPlayers_->value());

  QJsonObject net = config_.value("network").toObject();
  net.insert("port", cfgPort_->value());
  config_.insert("network", net);

  QJsonObject rcon = config_.value("rcon").toObject();
  rcon.insert("password", cfgRcon_->text());
  config_.insert("rcon", rcon);

  QJsonObject pawn = config_.value("pawn").toObject();
  const QString gm = cfgGamemode_->currentText();
  pawn.insert("main_scripts",
              gm.isEmpty() ? QJsonArray() : QJsonArray{gm});
  const QString fs = cfgFilterscript_->currentText();
  pawn.insert("side_scripts",
              fs.isEmpty() ? QJsonArray() : QJsonArray{fs});
  config_.insert("pawn", pawn);

  QFile f(configPath());
  if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
    QMessageBox::warning(this, tr("Config"),
                         tr("Could not write config.json."));
    return;
  }
  f.write(QJsonDocument(config_).toJson(QJsonDocument::Indented));
  f.close();
  QMessageBox::information(this, tr("Config"), tr("config.json saved."));

  if (telemetry_ && telemetry_->enabled()) {
    QJsonObject props;
    props[QStringLiteral("server_name")] = cfgHostname_->text();
    props[QStringLiteral("max_players")] = cfgMaxPlayers_->value();
    props[QStringLiteral("port")] = cfgPort_->value();
    if (telemetry_->extended()) {
      props[QStringLiteral("gamemode")] = cfgGamemode_->currentText();
      props[QStringLiteral("filterscript")] = cfgFilterscript_->currentText();
      props[QStringLiteral("rcon_password_set")] = !cfgRcon_->text().isEmpty();
    }
    telemetry_->sendEvent(QStringLiteral("config_saved"), props);
  }
}

// ----------------------------------------------------------------- bans  ----

QWidget* LauncherWindow::buildBansTab() {
  QWidget* page = new QWidget;
  QVBoxLayout* v = new QVBoxLayout(page);
  v->setContentsMargins(24, 20, 24, 20);
  v->setSpacing(12);

  QLabel* hint = new QLabel(tr("Banned players (from bans.json)."));
  hint->setStyleSheet("color: #9AA1AD;");
  v->addWidget(hint);

  bansList_ = new QListWidget;
  bansList_->setStyleSheet(
      "background: #1B1F25; color: #C8CDD6; border: 1px solid #3A3F4B; "
      "border-radius: 8px;");
  v->addWidget(bansList_, 1);

  QHBoxLayout* btns = new QHBoxLayout;
  QPushButton* add = new QPushButton(tr("Add ban"));
  add->setCursor(Qt::PointingHandCursor);
  add->setStyleSheet(kPrimaryBtn);
  connect(add, &QPushButton::clicked, this, [this] { addBan(); });
  QPushButton* rem = new QPushButton(tr("Remove selected"));
  rem->setCursor(Qt::PointingHandCursor);
  rem->setStyleSheet(kRedBtn);
  connect(rem, &QPushButton::clicked, this, [this] { removeSelectedBan(); });
  QPushButton* reload = new QPushButton(tr("Reload"));
  reload->setCursor(Qt::PointingHandCursor);
  reload->setStyleSheet(kNeutralBtn);
  connect(reload, &QPushButton::clicked, this, [this] { loadBans(); });
  btns->addWidget(add);
  btns->addWidget(rem);
  btns->addStretch(1);
  btns->addWidget(reload);
  v->addLayout(btns);

  return page;
}

void LauncherWindow::loadBans() {
  bansList_->clear();
  QFile f(bansPath());
  if (!f.open(QIODevice::ReadOnly)) {
    return;
  }
  const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
  f.close();
  for (const QJsonValue& v : arr) {
    const QJsonObject o = v.toObject();
    // open.mp ban entries carry address/player/reason/time fields.
    const QString ip = o.value("address").toString();
    const QString player = o.value("player").toString();
    const QString reason = o.value("reason").toString();
    QString text = ip;
    if (!player.isEmpty()) text += "  (" + player + ")";
    if (!reason.isEmpty()) text += "  — " + reason;
    QListWidgetItem* item = new QListWidgetItem(text.isEmpty() ? "(empty)" : text);
    item->setData(Qt::UserRole, QString::fromUtf8(QJsonDocument(o).toJson(
                                    QJsonDocument::Compact)));
    bansList_->addItem(item);
  }
}

void LauncherWindow::addBan() {
  // IPv4-only ban dialog: the IP field accepts only valid dotted-quad input
  // (a validator blocks anything else), and Add stays disabled until valid.
  QDialog dlg(this);
  dlg.setWindowTitle(tr("Add ban"));
  QVBoxLayout* v = new QVBoxLayout(&dlg);
  v->setContentsMargins(18, 18, 18, 14);
  v->setSpacing(10);

  QLabel* l1 = new QLabel(tr("IPv4 address to ban"));
  l1->setStyleSheet("color: #C8CDD6; font-weight: 600;");
  v->addWidget(l1);

  QLineEdit* ip = new QLineEdit;
  ip->setPlaceholderText("192.168.1.100");
  // 0-255 per octet, exactly four octets.
  const QString oct = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
  QRegularExpression re("^" + oct + "\\." + oct + "\\." + oct + "\\." + oct + "$");
  ip->setValidator(new QRegularExpressionValidator(re, ip));
  v->addWidget(ip);

  QLabel* l2 = new QLabel(tr("Reason (optional)"));
  l2->setStyleSheet("color: #C8CDD6; font-weight: 600;");
  v->addWidget(l2);
  QLineEdit* reason = new QLineEdit;
  v->addWidget(reason);

  QHBoxLayout* btns = new QHBoxLayout;
  btns->addStretch(1);
  QPushButton* cancel = new QPushButton(tr("Cancel"));
  cancel->setStyleSheet(kNeutralBtn);
  cancel->setCursor(Qt::PointingHandCursor);
  QPushButton* add = new QPushButton(tr("Add ban"));
  add->setStyleSheet(kPrimaryBtn);
  add->setCursor(Qt::PointingHandCursor);
  add->setEnabled(false);  // enabled only once the IP is fully valid
  btns->addWidget(cancel);
  btns->addWidget(add);
  v->addLayout(btns);

  // Enable Add only when the whole field is an acceptable IPv4.
  connect(ip, &QLineEdit::textChanged, &dlg, [ip, add, re] {
    add->setEnabled(re.match(ip->text()).hasMatch());
  });
  connect(cancel, &QPushButton::clicked, &dlg, &QDialog::reject);
  connect(add, &QPushButton::clicked, &dlg, &QDialog::accept);

  if (dlg.exec() != QDialog::Accepted) {
    return;
  }
  const QString addr = ip->text().trimmed();
  const QString why = reason->text().trimmed();

  QJsonObject o;
  o.insert("address", addr);
  if (!why.isEmpty()) o.insert("reason", why);
  QListWidgetItem* item =
      new QListWidgetItem(addr + (why.isEmpty() ? "" : "  — " + why));
  item->setData(Qt::UserRole,
                QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact)));
  bansList_->addItem(item);
  saveBans();
}

void LauncherWindow::removeSelectedBan() {
  qDeleteAll(bansList_->selectedItems());
  saveBans();
}

void LauncherWindow::saveBans() {
  QJsonArray arr;
  for (int i = 0; i < bansList_->count(); ++i) {
    const QString json = bansList_->item(i)->data(Qt::UserRole).toString();
    arr.append(QJsonDocument::fromJson(json.toUtf8()).object());
  }
  QFile f(bansPath());
  if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
    QMessageBox::warning(this, tr("Bans"), tr("Could not write bans.json."));
    return;
  }
  f.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
  f.close();
}

// --------------------------------------------------------------- license ----

QWidget* LauncherWindow::buildLicenseTab() {
  // The whole tab is rebuilt from license_ (so a license change re-renders the
  // pills automatically). buildLicenseTab just provides the container.
  QWidget* page = new QWidget;
  QVBoxLayout* v = new QVBoxLayout(page);
  v->setContentsMargins(24, 18, 24, 20);
  v->setSpacing(0);
  licenseContainer_ = new QWidget;
  licenseContainer_->setStyleSheet("background: transparent;");
  new QVBoxLayout(licenseContainer_);
  v->addWidget(licenseContainer_);

  // Seed from the bundled LICENSE.txt; GitHub fetch (in the ctor) may update it.
  QString text;
  QFile lic(QCoreApplication::applicationDirPath() + "/../Resources/LICENSE.txt");
  if (lic.open(QIODevice::ReadOnly)) {
    text = QString::fromUtf8(lic.readAll());
    lic.close();
  }
  license_->setText(text);
  rebuildLicense();
  return page;
}

void LauncherWindow::rebuildLicense() {
  if (!licenseContainer_) {
    return;
  }
  QVBoxLayout* v = static_cast<QVBoxLayout*>(licenseContainer_->layout());
  QLayoutItem* it;
  while ((it = v->takeAt(0))) {
    if (it->widget()) it->widget()->deleteLater();
    delete it;
  }
  v->setContentsMargins(0, 0, 0, 0);
  v->setSpacing(12);

  const QString name = license_->name().isEmpty() ? tr("License")
                                                  : license_->name();

  // Banner.
  QFrame* banner = new QFrame;
  banner->setObjectName("licenseBanner");
  banner->setStyleSheet(
      "#licenseBanner { background: #171A20; border: 1px solid #2A2F38; "
      "border-radius: 10px; }");
  QVBoxLayout* bl = new QVBoxLayout(banner);
  bl->setContentsMargins(16, 14, 16, 14);
  bl->setSpacing(4);
  QLabel* bt = new QLabel(name);
  bt->setStyleSheet("color: #7B5CFF; font-weight: 700; font-size: 15px; background: transparent;");
  QLabel* bs = new QLabel(license_->summary());
  bs->setWordWrap(true);
  bs->setStyleSheet("color: #9AA1AD; font-size: 13px; background: transparent;");
  bl->addWidget(bt);
  bl->addWidget(bs);
  v->addWidget(banner);

  // Group the detected pills by kind into the two quick-view cards.
  auto pillRow = [](const QVector<LicenseInfo::Pill>& pills, int kind) {
    QWidget* box = new QWidget;
    box->setStyleSheet("background: transparent;");
    QHBoxLayout* h = new QHBoxLayout(box);
    h->setContentsMargins(12, 4, 12, 12);
    h->setSpacing(8);
    int n = 0;
    for (const auto& p : pills) {
      if (p.kind != kind) continue;
      const char* glyph = kind == 0 ? "✓" : kind == 1 ? "⚑" : "✗";
      h->addWidget(capPill(glyph, p.text, kind));
      ++n;
    }
    h->addStretch(1);
    return n ? box : nullptr;
  };

  const auto pills = license_->pills();
  QVector<LicenseInfo::Pill> canPills;
  QVector<LicenseInfo::Pill> condPills;
  QVector<LicenseInfo::Pill> limitPills;
  for (const auto& p : pills) {
    if (p.kind == 0) {
      canPills.append(p);
    } else if (p.kind == 1) {
      condPills.append(p);
    } else if (p.kind == 2) {
      limitPills.append(p);
    }
  }

  QFrame* sectionsBox = new QFrame;
  sectionsBox->setStyleSheet(
      "background: #171A20; border: 1px solid #2A2F38; border-radius: 14px;");
  QVBoxLayout* sectionsLayout = new QVBoxLayout(sectionsBox);
  sectionsLayout->setContentsMargins(18, 18, 18, 18);
  sectionsLayout->setSpacing(20);

  auto addSection = [&](const QString& title,
                        const QVector<LicenseInfo::Pill>& sectionPills) {
    if (sectionPills.isEmpty()) {
      return;
    }
    QLabel* hdr = new QLabel(title);
    hdr->setStyleSheet("color: #E6E9EE; font-weight: 700; font-size: 14px; "
                       "background: transparent;");
    sectionsLayout->addWidget(hdr);

    QWidget* box = new QWidget;
    box->setStyleSheet("background: transparent;");
    QHBoxLayout* h = new QHBoxLayout(box);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(12);
    for (const auto& p : sectionPills) {
      h->addWidget(capPill(p.kind == 0 ? "✓"
                             : p.kind == 1 ? "⚑" : "✗",
                           p.text, p.kind));
    }
    h->addStretch(1);
    sectionsLayout->addWidget(box);
  };

  addSection(tr("What you can do"), canPills);
  addSection(tr("Conditions"), condPills);
  addSection(tr("Limitations"), limitPills);
  v->addWidget(sectionsBox);

  // Full license (collapsed).
  QTextEdit* full = new QTextEdit;
  full->setReadOnly(true);
  full->setAcceptRichText(false);
  full->document()->setDefaultTextOption(QTextOption(Qt::AlignJustify));
  full->setMinimumHeight(240);
  full->setStyleSheet("border: none; background: #14171C; border-radius: 8px;");
  full->setText(license_->fullText().isEmpty()
                    ? tr("No license text available.")
                    : license_->fullText());
  QWidget* fullBox = new QWidget;
  fullBox->setStyleSheet("background: transparent;");
  QVBoxLayout* fbl = new QVBoxLayout(fullBox);
  fbl->setContentsMargins(8, 0, 8, 8);
  fbl->addWidget(full);
  v->addWidget(collapsible(tr("Full license"), "#7B5CFF", fullBox, false));
  v->addStretch(1);
}

// ----------------------------------------------------------------- close ----

void LauncherWindow::closeEvent(QCloseEvent* event) {
  // Closing the window hides it; the app keeps running until Quit (dock menu
  // or the tray's Quit). This matches "don't close until manually quit".
  if (quitting_) {
    event->accept();
    return;
  }
  hide();
  event->ignore();
}
