import 'package:flutter/material.dart';

class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({required this.isSuccess, super.key});

  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScannerOverlayPainter(isSuccess: isSuccess),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isSuccess
                ? Semantics(
                    liveRegion: true,
                    label: 'Barcode captured',
                    child: const Icon(
                      Icons.check_circle,
                      key: Key('scanSuccessIcon'),
                      size: 64,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({required this.isSuccess});

  final bool isSuccess;

  @override
  void paint(Canvas canvas, Size size) {
    final cutoutWidth = (size.width - 48).clamp(240.0, 420.0);
    final cutoutHeight = (cutoutWidth * 0.58).clamp(160.0, 220.0);
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.46),
      width: cutoutWidth,
      height: cutoutHeight,
    );
    final cutout = RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16));
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(cutout)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.62));

    final color = isSuccess ? const Color(0xFF47CD89) : Colors.white;
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    const corner = 30.0;
    final path = Path()
      ..moveTo(cutoutRect.left, cutoutRect.top + corner)
      ..lineTo(cutoutRect.left, cutoutRect.top)
      ..lineTo(cutoutRect.left + corner, cutoutRect.top)
      ..moveTo(cutoutRect.right - corner, cutoutRect.top)
      ..lineTo(cutoutRect.right, cutoutRect.top)
      ..lineTo(cutoutRect.right, cutoutRect.top + corner)
      ..moveTo(cutoutRect.right, cutoutRect.bottom - corner)
      ..lineTo(cutoutRect.right, cutoutRect.bottom)
      ..lineTo(cutoutRect.right - corner, cutoutRect.bottom)
      ..moveTo(cutoutRect.left + corner, cutoutRect.bottom)
      ..lineTo(cutoutRect.left, cutoutRect.bottom)
      ..lineTo(cutoutRect.left, cutoutRect.bottom - corner);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter oldDelegate) => oldDelegate.isSuccess != isSuccess;
}
