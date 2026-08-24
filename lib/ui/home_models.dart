import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/languages.dart';

/// Rail icon item for the activity bar.
class RailItem {
  final IconData icon;
  final String   label;
  final int      idx;
  const RailItem({required this.icon, required this.label, required this.idx});
}

/// Defines an editor tab (id = 'welcome', 'marketplace', file path, etc.).
class TabDef {
  final String   id;
  final String   title;
  final IconData icon;
  const TabDef({required this.id, required this.title, required this.icon});
}

/// Holds the data needed to render an EditorPage inside a tab.
class EditorTabConfig {
  final File?     file;
  final String    rootDir;
  final Language? languageDetails;
  final bool      isProject;
  final bool      isCloned;

  EditorTabConfig({
    this.file,
    required this.rootDir,
    this.languageDetails,
    this.isProject = false,
    this.isCloned  = false,
  });
}

/// Custom clipper for the sidebar panel shape (rounded right corners).
class SidebarClipper extends CustomClipper<Path> {
  static const double _radius = 20.0;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - _radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, _radius)
      ..lineTo(size.width, size.height - _radius)
      ..quadraticBezierTo(
          size.width, size.height, size.width - _radius, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
