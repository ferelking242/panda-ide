import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_json/flutter_json.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import '../../utils/llama_wrapper.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:path/path.dart' as path;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:panda/utils/agentic_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bloc/repo_bloc/repo_bloc.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../terminal/terminal.dart';
import '../../utils/ai.dart';
import '../../utils/copilot_chat.dart';
import '../../utils/functions.dart';
import '../../utils/languages.dart';
import '../../utils/themes.dart';
import '../../utils/constants.dart';

// Git commit graph
// Extracted from widgets.dart

const List<Color> _gitGraphColors = [
  Color(0xFF007ACC),
  Color(0xFFD14B4B),
  Color(0xFF4EC9B0),
  Color(0xFFCE9178),
  Color(0xFFC586C0),
  Color(0xFF9CDCFE),
  Color(0xFFB5CEA8),
  Color(0xFFDCDCAA),
  Color(0xFF4FC1FF),
];

Color _getGraphColor(int index) {
  return _gitGraphColors[index % _gitGraphColors.length];
}

class VSCodeGitGraphPainter extends CustomPainter {
  final CommitRowInfo rowInfo;
  final double laneWidth;
  final double rowHeight;
  final bool isDark;
  final Color textColor;
  final Color secondaryTextColor;
  final Color backgroundColor;
  final double maxWidth;

  VSCodeGitGraphPainter({
    required this.rowInfo,
    required this.textColor,
    required this.secondaryTextColor,
    required this.backgroundColor,
    required this.maxWidth,
    this.laneWidth = 16,
    this.rowHeight = 36,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final nodePaint = Paint()..style = PaintingStyle.fill;
    final nodeStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final nodeCapPaint = Paint()..style = PaintingStyle.fill;

    final commitX = rowInfo.commitLane * laneWidth + laneWidth / 2;
    final commitY = rowHeight / 2;

    for (final line in rowInfo.lines) {
      final fromX = line.fromLane * laneWidth + laneWidth / 2;
      final toX = line.toLane * laneWidth + laneWidth / 2;
      final color = _getGraphColor(line.colorIndex);
      linePaint.color = color;

      if (line.isPassThrough) {
        canvas.drawLine(Offset(fromX, 0), Offset(fromX, rowHeight), linePaint);
      } else if (line.fromLane == line.toLane) {
        canvas.drawLine(
          Offset(fromX, commitY + 5),
          Offset(fromX, rowHeight),
          linePaint,
        );
      } else {
        final path = Path();

        if (line.toLane > line.fromLane) {
          path.moveTo(fromX, commitY + 5);
          path.cubicTo(
            fromX,
            commitY + 10,
            fromX + 14,
            rowHeight - 12,
            toX,
            rowHeight,
          );
        } else {
          path.moveTo(fromX, commitY + 5);
          path.cubicTo(
            fromX,
            commitY + 12,
            toX + 15,
            rowHeight,
            toX,
            rowHeight,
          );
        }
        canvas.drawPath(path, linePaint);
      }
    }

    final nodeColor = _getGraphColor(rowInfo.colorIndex);
    final isReferenceCommit = rowInfo.commit.isHead || rowInfo.commit.isRemoteHead;

    if (!isReferenceCommit) {
      linePaint.color = nodeColor;
      canvas.drawLine(
        Offset(commitX, 0),
        Offset(commitX, commitY - 5),
        linePaint,
      );
    }

    if (isReferenceCommit) {
      nodeCapPaint.color = backgroundColor;
      canvas.drawCircle(Offset(commitX, commitY), 8, nodeCapPaint);
      nodeStrokePaint.color = nodeColor.withAlpha(220);
      canvas.drawCircle(Offset(commitX, commitY), 7, nodeStrokePaint);
      nodePaint.color = nodeColor;
      canvas.drawCircle(Offset(commitX, commitY), 4, nodePaint);
    } else if (rowInfo.commit.isMerge) {
      nodePaint.color = nodeColor;
      canvas.drawCircle(Offset(commitX, commitY), 5, nodePaint);
      nodeStrokePaint.color = nodeColor.withAlpha(180);
      canvas.drawCircle(Offset(commitX, commitY), 7, nodeStrokePaint);
    } else {
      nodePaint.color = nodeColor;
      canvas.drawCircle(Offset(commitX, commitY), 5, nodePaint);
    }

    int maxLaneInRow = rowInfo.commitLane;
    for (final line in rowInfo.lines) {
      if (line.fromLane > maxLaneInRow) maxLaneInRow = line.fromLane;
      if (line.toLane > maxLaneInRow) maxLaneInRow = line.toLane;
    }

    final graphWidth = (maxLaneInRow + 1) * laneWidth + 12;
    double textStartX = graphWidth;
    final availableWidth = maxWidth - textStartX;

    if (availableWidth > 50) {
      if (rowInfo.commit.isMerge) {
        final badgePainter = TextPainter(
          text: TextSpan(
            text: 'Merge',
            style: TextStyle(
              color: _getGraphColor(rowInfo.colorIndex),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        badgePainter.layout();

        final badgeWidth = badgePainter.width + 8;
        final badgeHeight = badgePainter.height + 2;
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(textStartX, 8, badgeWidth, badgeHeight),
          const Radius.circular(3),
        );

        final badgeBgPaint = Paint()
          ..color = _getGraphColor(rowInfo.colorIndex).withAlpha(40)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(badgeRect, badgeBgPaint);

        final badgeBorderPaint = Paint()
          ..color = _getGraphColor(rowInfo.colorIndex).withAlpha(100)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRRect(badgeRect, badgeBorderPaint);
        badgePainter.paint(canvas, Offset(textStartX + 4, 8));
        textStartX += badgeWidth + 6;
      }

      final messagePainter = TextPainter(
        text: TextSpan(
          text: rowInfo.commit.message,
          style: TextStyle(color: textColor, fontSize: 13, height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      messagePainter.layout(
        maxWidth: availableWidth - (rowInfo.commit.isMerge ? 50 : 0),
      );
      messagePainter.paint(canvas, Offset(textStartX, 6));

      final datePart = rowInfo.commit.date.isNotEmpty ? ' · ${rowInfo.commit.date}' : '';
      final authorHash =
          '${rowInfo.commit.author} • ${rowInfo.commit.hash.substring(0, 7)}$datePart';
      final authorPainter = TextPainter(
        text: TextSpan(
          text: authorHash,
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 10,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      authorPainter.layout(maxWidth: availableWidth);
      authorPainter.paint(canvas, Offset(graphWidth, 22));
    }
  }

  @override
  bool shouldRepaint(covariant VSCodeGitGraphPainter oldDelegate) {
    return oldDelegate.rowInfo != rowInfo ||
        oldDelegate.maxWidth != maxWidth ||
        oldDelegate.textColor != textColor;
  }
}

class GitCommitGraph extends StatelessWidget {
  final List<CommitNode> commits;
  final AppTheme appTheme;

  const GitCommitGraph({
    super.key,
    required this.commits,
    required this.appTheme,
  });

  @override
  Widget build(BuildContext context) {
    final rowInfos = assignVSCodeLanes(commits);
    const contentWidth = 500.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: contentWidth,
        height: commits.length * 36.0,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: rowInfos.length,
          itemBuilder: (context, index) {
            final rowInfo = rowInfos[index];
            return SizedBox(
              height: 36,
              child: CustomPaint(
                size: Size(contentWidth, 36),
                painter: VSCodeGitGraphPainter(
                  rowInfo: rowInfo,
                  isDark: appTheme.isDark,
                  textColor: appTheme.selectScreenCardTextColor,
                  secondaryTextColor: appTheme.selectScreenCardTextColor.withAlpha(150),
                  backgroundColor: appTheme.scaffoldBg,
                  maxWidth: contentWidth,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget settingsTextField(
  TextEditingController controller,
  IconData icon,
  String labelText,
  Color labelColor,
  String? hintText,
  String? Function(String?) validator,
  [bool obscure = false]
){
  return TextFormField(
    controller: controller,
    style: TextStyle(
      color: labelColor
    ),
    obscureText: obscure,
    cursorColor: Colors.lightBlue,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: Color(0xff007acc)),
      hintStyle: TextStyle(
        color: labelColor.withAlpha(150),
        fontStyle: FontStyle.italic,
        fontSize: 12
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: BorderSide(
          color: Color(0xff007acc),
          width: 2,
        )
      ),
      hintText: hintText,
      labelText: labelText,
      labelStyle: TextStyle(
        color: labelColor.withAlpha(150),
        fontSize: 15
      ),
    ),
    validator: validator,
  );
}

Widget copyArea(
  BuildContext context,
  AppTheme appTheme,
  String text,
  double height
) => Container(
  height: height,
    width: 350,
    decoration: BoxDecoration(
      color: appTheme.scaffoldBg,
      border: Border.all(
        color: appTheme.selectScreenCardTextColor.withAlpha(120),
        width: 1
      ),
      borderRadius: BorderRadius.circular(6)
    ),
  child: Stack(
    children: [
      Padding(
        padding: const EdgeInsets.only(right: 35, top: 15, left: 10),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: "monospace",
            fontSize: 14
          )
        ),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: IconButton(
          onPressed: () async{
            await Clipboard.setData(
              ClipboardData(text: text)
            );
            if(context.mounted){
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          icon: Icon(
            Icons.copy,
            color: appTheme.selectScreenCardTextColor.withAlpha(200)
          )
        ),
      )
    ]
  ),
);
