// Server Launcher — a macOS-style sliding toggle. GNU GPL v3 or later.

#ifndef TOGGLESWITCH_H
#define TOGGLESWITCH_H

#include <QWidget>

// A pill toggle that animates a knob left/right. Off = red track, On = green
// track (per request). Emits toggled(bool).
class ToggleSwitch : public QWidget {
  Q_OBJECT
  Q_PROPERTY(qreal pos READ pos WRITE setPos)

 public:
  explicit ToggleSwitch(QWidget* parent = nullptr);

  bool isChecked() const { return checked_; }
  void setChecked(bool on);

  QSize sizeHint() const override { return QSize(46, 26); }

  qreal pos() const { return pos_; }
  void setPos(qreal p);

 signals:
  void toggled(bool on);

 protected:
  void paintEvent(QPaintEvent*) override;
  void mouseReleaseEvent(QMouseEvent*) override;

 private:
  bool checked_ = false;
  qreal pos_ = 0.0;  // 0 = off (left), 1 = on (right)
};

#endif // TOGGLESWITCH_H
