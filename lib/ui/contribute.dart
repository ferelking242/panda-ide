import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:panda/bloc/ui_bloc/ui_bloc.dart';
import 'package:panda/utils/themes.dart';

class ContributePage extends StatelessWidget {
  final String repoUrl = 'https://github.com/heckmon/roxum-ide';

  const ContributePage({super.key});

  void _launchRepo() async {
    final uri = Uri.parse(repoUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildContributionItem(Icon icon, String text, AppTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: theme.selectScreenCardTextColor.withAlpha(200),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppThemeBloc, AppThemeState>(
      builder: (context, appThemeState) {
        final theme = appThemeState.appTheme;
        final isDark = theme.isDark;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Contribute'),
            backgroundColor: theme.appBarTheme.backgroundColor,
            foregroundColor: theme.appBarTheme.foregroundColor,
            elevation: theme.appBarTheme.elevation,
          ),
          body: Container(
            color: theme.scaffoldBg,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  color: theme.cardTheme.color,
                  elevation: theme.cardTheme.elevation,
                  shape: theme.cardTheme.shape,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.volunteer_activism,
                          color: isDark ? Colors.pinkAccent : Colors.pink,
                          size: 56,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Contribute to Roxum!',
                          style: TextStyle(
                            color: theme.selectScreenCardTextColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Roxum is a powerful, open-source code editor and IDE built with Flutter, designed for developers on the go.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.selectScreenCardTextColor.withAlpha(180),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ways to Contribute:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: theme.selectScreenCardTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.center,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildContributionItem(Icon(Icons.star, color: Colors.yellow), 'Star the repo.', theme),
                              _buildContributionItem(Icon(Icons.bug_report, color: Colors.red[800]), 'Report Bugs.', theme),
                              _buildContributionItem(Icon(Icons.lightbulb, color: Colors.yellow), 'Suggest Features.', theme),
                              _buildContributionItem(Icon(Icons.edit_document, color: Colors.grey), 'Improve Documentation.', theme),
                              _buildContributionItem(FaIcon(FontAwesomeIcons.vial, color: Colors.green, size: 20), 'Test and Provide Feedback.', theme),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.blueAccent : Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            elevation: 4,
                          ),
                          onPressed: _launchRepo,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text(
                            'Go to GitHub',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}