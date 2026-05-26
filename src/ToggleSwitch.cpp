// Server Launcher — a macOS-style sliding toggle. GNU GPL v3 or later.

#include "ToggleSwitch.h"

#include <QMouseEvent>
#include <QPainter>
#include <QPropertyAnimation>

ToggleSwitch::ToggleSwitch(QWidget* parent) : QWidget(parent) {
  setCursor(Qt::PointingHandCursor);
  setFixedSize(46, 26);
}

void ToggleSwitch::setChecked(bool on) {
  if (checked_ == on) {
    return;
  }
  checked_ = on;
  QPropertyAnimation* a = new QPropertyAnimation(this, "pos", this);
  a->setDuration(140);
  a->setStartValue(pos_);
  a->setEndValue(on ? 1.0 : 0.0);
  a->start(QAbstractAnimation::DeleteWhenStopped);
  emit toggled(on);
}

void ToggleSwitch::setPos(qreal p) {
  pos_ = p;
  update();
}

void ToggleSwitch::mouseReleaseEvent(QMouseEvent* e) {
  if (e->button() == Qt::LeftButton && rect().contains(e->pos())) {
    setChecked(!checked_);
  }
}

void ToggleSwitch::paintEvent(QPaintEvent*) {
  QPainter p(this);
  p.setRenderHint(QPainter::Antialiasing);

  const int h = height();
  const int w = width();
  const QRectF track(0, 0, w, h);

  // Track color blends gray (off) -> green (on) by knob position.
  const QColor off(0x56, 0x5D, 0x6A);   // gray
  const QColor on(0x1F, 0xA8, 0x5C);    // green
  QColor track_c(
      off.red() + (on.red() - off.red()) * pos_,
      off.green() + (on.green() - off.green()) * pos_,
      off.blue() + (on.blue() - off.blue()) * pos_);
  p.setPen(Qt::NoPen);
  p.setBrush(track_c);
  p.drawRoundedRect(track, h / 2.0, h / 2.0);

  // Knob.
  const qreal margin = 3.0;
  const qreal knob = h - 2 * margin;
  const qreal x = margin + pos_ * (w - knob - 2 * margin);
  p.setBrush(Qt::white);
  p.setPen(QPen(QColor(0, 0, 0, 18), 1.0));
  p.drawEllipse(QRectF(x, margin, knob, knob));
}
