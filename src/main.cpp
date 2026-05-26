// Server Launcher — entry point. GNU GPL v3 or later.

#include <QApplication>
#include <QCoreApplication>
#include <QDir>
#include <QEvent>
#include <QIcon>
#include <QObject>

#include "LauncherWindow.h"

// Reshow the window when the dock icon is clicked while the window is hidden
// (closing the window only hides it; the app stays running until Quit).
class ReopenFilter : public QObject {
 public:
  explicit ReopenFilter(QWidget* w) : w_(w) {}
  bool eventFilter(QObject* obj, QEvent* e) override {
    if (e->type() == QEvent::ApplicationActivate ||
        e->type() == QEvent::ApplicationStateChange) {
      if (!w_->isVisible()) {
        w_->show();
        w_->raise();
      }
    }
    return QObject::eventFilter(obj, e);
  }
 private:
  QWidget* w_;
};

int main(int argc, char** argv) {
  QApplication app(argc, argv);
  QCoreApplication::setApplicationName("open.mp Server Launcher");
  QCoreApplication::setOrganizationName("openmultiplayer");
  app.setWindowIcon(QIcon(":/icon.png"));

  // open.mp-styled dark theme: purple accent, rounded inputs, pill tabs.
  app.setStyleSheet(R"(
    QWidget { background: #20242C; color: #C8CDD6; font-size: 13px; }
    /* Labels are transparent by default so they never paint a box over cards;
       pills/banners set their own background explicitly. */
    QLabel { background: transparent; }
    QToolTip { background: #2A2F38; color: #E6E9EE; border: 1px solid #3A3F4B; }
    QPushButton, QToolButton { cursor: pointing-hand; }

    /* Inputs */
    QLineEdit, QComboBox, QSpinBox, QPlainTextEdit {
      background: #171A20; border: 1px solid #333A45; border-radius: 8px;
      padding: 7px 10px; color: #E6E9EE; selection-background-color: #7B5CFF;
    }
    QLineEdit:focus, QComboBox:focus, QSpinBox:focus {
      border: 1px solid #7B5CFF;
    }
    QComboBox::drop-down { border: none; width: 22px; }
    QComboBox QAbstractItemView {
      background: #171A20; border: 1px solid #333A45; color: #E6E9EE;
      selection-background-color: #7B5CFF;
    }

    /* Spin box up/down buttons — styled for the dark theme. */
    QSpinBox::up-button, QSpinBox::down-button,
    QDoubleSpinBox::up-button, QDoubleSpinBox::down-button {
      background: #262B34; border: none; width: 20px;
      subcontrol-origin: border;
    }
    QSpinBox::up-button, QDoubleSpinBox::up-button {
      subcontrol-position: top right; border-top-right-radius: 8px;
    }
    QSpinBox::down-button, QDoubleSpinBox::down-button {
      subcontrol-position: bottom right; border-bottom-right-radius: 8px;
    }
    QSpinBox::up-button:hover, QSpinBox::down-button:hover,
    QDoubleSpinBox::up-button:hover, QDoubleSpinBox::down-button:hover {
      background: #323845;
    }
    QSpinBox::up-arrow, QDoubleSpinBox::up-arrow {
      image: none; width: 0; height: 0;
      border-left: 4px solid transparent; border-right: 4px solid transparent;
      border-bottom: 5px solid #C8CDD6;
    }
    QSpinBox::down-arrow, QDoubleSpinBox::down-arrow {
      image: none; width: 0; height: 0;
      border-left: 4px solid transparent; border-right: 4px solid transparent;
      border-top: 5px solid #C8CDD6;
    }

    /* Pill tab bar */
    QTabWidget::pane { border: none; top: 6px; }
    QTabBar { qproperty-drawBase: 0; }
    QTabBar::tab {
      background: #171A20; color: #9AA1AD; border: 1px solid #2A2F38;
      border-radius: 9px; padding: 8px 18px; margin: 2px 6px 2px 0;
      font-weight: 600;
    }
    QTabBar::tab:selected {
      background: #7B5CFF; color: white; border-color: #7B5CFF;
    }
    QTabBar::tab:hover:!selected {
      background: #262B34; color: #E6E9EE; border-color: #3A4250;
    }

    QScrollBar:vertical { background: transparent; width: 10px; }
    QScrollBar::handle:vertical { background: #3A4250; border-radius: 5px; min-height: 24px; }
    QScrollBar::add-line, QScrollBar::sub-line { height: 0; }
  )");

#ifdef Q_OS_MACOS
  // Launched from Finder, the working directory is "/". The server's config and
  // components live beside the .app, so make that the working directory.
  {
    QDir dir(QCoreApplication::applicationDirPath());  // .app/Contents/MacOS
    dir.cdUp();  // Contents
    dir.cdUp();  // .app
    dir.cdUp();  // folder containing the .app
    QDir::setCurrent(dir.absolutePath());
  }
#endif

  LauncherWindow w;
  w.show();
  app.installEventFilter(new ReopenFilter(&w));
  return app.exec();
}
