import 'package:flutter/material.dart';
import 'dart:math' as math;

class AiStudioWorkingIndicator extends StatefulWidget {
  final String text;
  final Color textColor;
  
  const AiStudioWorkingIndicator({
    Key? key,
    required this.text,
    this.textColor = const Color(0xff9e9e9e),
  }) : super(key: key);

  @override
  State<AiStudioWorkingIndicator> createState() => _AiStudioWorkingIndicatorState();
}

class _AiStudioWorkingIndicatorState extends State<AiStudioWorkingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indicator = AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(18, 18),
          painter: AiStudioIndicatorPainter(_ctrl.value),
        );
      },
    );
    
    if (widget.text.isEmpty) {
      return indicator;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(width: 8),
        Text(
          widget.text,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class AiStudioIndicatorPainter extends CustomPainter {
  final double progress;
  AiStudioIndicatorPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    
    // Draw the spark in the center
    final sparkPaint = Paint()
      ..color = const Color(0xff9e9e9e)
      ..style = PaintingStyle.fill;
    
    final sparkPath = Path();
    final innerR = size.width * 0.15;
    final outerR = size.width * 0.35;
    
    sparkPath.moveTo(cx, cy - outerR);
    sparkPath.quadraticBezierTo(cx, cy, cx + outerR, cy);
    sparkPath.quadraticBezierTo(cx, cy, cx, cy + outerR);
    sparkPath.quadraticBezierTo(cx, cy, cx - outerR, cy);
    sparkPath.quadraticBezierTo(cx, cy, cx, cy - outerR);
    sparkPath.close();
    
    canvas.drawPath(sparkPath, sparkPaint);
    
    // Draw the rotating arc
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - 1);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
      
    final gradient = SweepGradient(
      colors: const [
        Color(0xff4285f4), // blue
        Color(0xffea4335), // red
        Color(0xfffbbc04), // yellow
        Color(0xff34a853), // green
        Color(0xff4285f4), // blue again for smooth transition
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(progress * 2 * math.pi),
    );
    
    arcPaint.shader = gradient.createShader(rect);
    
    // Arc is about 270 degrees (3/4 of a circle)
    final startAngle = (progress * 2 * math.pi);
    final sweepAngle = 1.5 * math.pi; // 270 degrees
    
    canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _AiStudioIndicatorPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
