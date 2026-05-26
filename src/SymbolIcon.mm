// Server Launcher — SF Symbols -> QIcon bridge. GNU GPL v3 or later.

#include "SymbolIcon.h"

#include <QImage>
#include <QPixmap>

#ifdef Q_OS_MACOS
#import <AppKit/AppKit.h>

namespace {
// Convert an NSImage to a QImage at the given pixel size.
QImage nsImageToQImage(NSImage* img, int px) {
  NSRect rect = NSMakeRect(0, 0, px, px);
  CGImageRef cg = [img CGImageForProposedRect:&rect context:nil hints:nil];
  if (!cg) {
    return QImage();
  }
  const size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
  QImage out(static_cast<int>(w), static_cast<int>(h),
             QImage::Format_RGBA8888_Premultiplied);
  out.fill(Qt::transparent);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(
      out.bits(), w, h, 8, out.bytesPerLine(), cs,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(cs);
  if (!ctx) {
    return QImage();
  }
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
  CGContextRelease(ctx);
  return out;
}
}  // namespace

QIcon SymbolIcon::load(const QString& symbolName, int pointSize,
                       const QColor& color) {
  @autoreleasepool {
    NSString* name = symbolName.toNSString();
    NSImage* base = nil;
    if (@available(macOS 11.0, *)) {
      base = [NSImage imageWithSystemSymbolName:name
                       accessibilityDescription:nil];
    }
    if (!base) {
      return QIcon();
    }

    // Apply a point-size + weight configuration and a tint color.
    if (@available(macOS 11.0, *)) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration
          configurationWithPointSize:pointSize
                              weight:NSFontWeightRegular];
      NSImage* configured = [base imageWithSymbolConfiguration:cfg];
      if (configured) base = configured;
    }

    // Tint by drawing the template image with a fill color.
    const int px = pointSize * 2;  // 2x for retina crispness
    NSImage* tinted = [[NSImage alloc] initWithSize:NSMakeSize(px, px)];
    [tinted lockFocus];
    NSRect r = NSMakeRect(0, 0, px, px);
    [base drawInRect:r
            fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver
            fraction:1.0];
    [[NSColor colorWithSRGBRed:color.redF()
                         green:color.greenF()
                          blue:color.blueF()
                         alpha:1.0] set];
    NSRectFillUsingOperation(r, NSCompositingOperationSourceAtop);
    [tinted unlockFocus];

    QImage qimg = nsImageToQImage(tinted, px);
    if (qimg.isNull()) {
      return QIcon();
    }
    QPixmap pm = QPixmap::fromImage(qimg);
    pm.setDevicePixelRatio(2.0);
    return QIcon(pm);
  }
}

#else  // not macOS

QIcon SymbolIcon::load(const QString&, int, const QColor&) {
  return QIcon();
}

#endif
