import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Page d'accueil affichée sur web (GitHub Pages).
///
/// L'IDE complet nécessite l'app Android (proot/Alpine natif) : cette page
/// présente le produit et redirige vers le téléchargement de l'APK.
class WebHome extends StatelessWidget {
  const WebHome({super.key});

  static const _accent = Color(0xff5090c8);
  static const _bg = Color(0xff1b1b1f);
  static const _surface = Color(0xff252525);
  static const _border = Color(0xff3a3a3a);

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('WebHome: cannot open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(),
                  const SizedBox(height: 72),
                  _hero(context),
                  const SizedBox(height: 88),
                  _featuresGrid(context),
                  const SizedBox(height: 88),
                  _howItWorks(context),
                  const SizedBox(height: 88),
                  _ctaCard(context),
                  const SizedBox(height: 48),
                  _footer(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          _pandaBadge(size: 38, radius: 11),
          const SizedBox(width: 12),
          const Text(
            'Panda IDE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          _navBtn('GitHub', 'https://github.com/ferelking242/panda-ide'),
          const SizedBox(width: 10),
          _navBtn('Releases',
              'https://github.com/ferelking242/panda-ide/releases'),
        ],
      ),
    );
  }

  Widget _navBtn(String label, String url) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => _open(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xffe0e0e0),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Hero ───────────────────────────────────────────────────────────────────
  Widget _hero(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
          ),
          child: const Text(
            'IDE mobile · Alpine Linux réel · Agent IA',
            style: TextStyle(
              color: Color(0xff9ec3e8),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 22),
        SelectableText.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Codez partout.\n'),
              TextSpan(
                text: 'Vraiment.',
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          style: TextStyle(
            color: Colors.white,
            fontSize: _responsive(context, 52, 34),
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const Text(
            "Panda IDE transforme votre téléphone en environnement de "
            'développement complet : terminal Alpine Linux via proot, éditeur '
            'avec coloration syntaxique, Git intégré et un agent IA qui pilote '
            'votre projet depuis le chat.',
            style: TextStyle(
              color: Color(0xffb8b8b8),
              fontSize: 16.5,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _open(_latestReleaseApkUrl),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.android, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Télécharger l\'APK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  _open('https://github.com/ferelking242/panda-ide'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.code, color: Color(0xffe0e0e0), size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Code source',
                      style: TextStyle(
                        color: Color(0xffe0e0e0),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _latestReleaseApkUrl =
      'https://github.com/ferelking242/panda-ide/releases/latest';

  // ── Features ───────────────────────────────────────────────────────────────
  Widget _featuresGrid(BuildContext context) {
    const features = [
      (
        Icons.terminal,
        'Terminal Alpine Linux',
        'Un vrai environnement Linux sur Android grâce à proot : apk, git, '
            'python, node… installez ce que vous voulez avec apk.'
      ),
      (
        Icons.edit_note,
        'Éditeur de code',
        'Coloration syntaxique, auto-complétion, pliage de code, '
            'recherche et multi-onglets pensés pour le tactile.'
      ),
      (
        Icons.smart_toy_outlined,
        'Panda Agent',
        'Un agent IA qui réfléchit, exécute des commandes dans votre '
            'terminal et construit vos fichiers sous votre supervision.'
      ),
      (
        Icons.account_tree_outlined,
        'Git intégré',
        'Clonez, committez, poussez vers GitHub directement depuis '
            'l\'application, clés SSH et tokens gérés proprement.'
      ),
      (
        Icons.widgets_outlined,
        'Runtimes multiples',
        'Node.js, Python, Java, Go, Rust… des toolchains préconfigurés '
            'installables en un geste.'
      ),
      (
        Icons.extension_outlined,
        'Gestionnaire de paquets',
        'Cherchez, installez et mettez à jour les paquets apk depuis une '
            'interface graphique, sans passer par le terminal.'
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 760 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Tout ce qu\'il faut pour coder'),
          const SizedBox(height: 26),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final f in features)
                SizedBox(
                  width: (c.maxWidth - (cols - 1) * 18) / cols,
                  child: _featureCard(f.$1, f.$2, f.$3),
                ),
            ],
          ),
        ],
      );
    });
  }

  Widget _featureCard(IconData icon, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: _accent, size: 22),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: const TextStyle(
              color: Color(0xffa8a8a8),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── How it works ───────────────────────────────────────────────────────────
  Widget _howItWorks(BuildContext context) {
    final steps = const [
      ('1', 'Installez l\'APK',
          'Récupérez la dernière version depuis GitHub Releases.'),
      ('2', 'Configurez en 6 étapes',
          'Permissions, certificats et Alpine Linux s\'installent '
              'automatiquement au premier lancement.'),
      ('3', 'Ouvrez un projet',
          'Clonez un repo Git ou créez-en un, puis codez avec le terminal, '
              'l\'éditeur et l\'agent IA.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Démarrage en 3 étapes'),
        const SizedBox(height: 26),
        for (var i = 0; i < steps.length; i++) ...[
          _stepRow(steps[i].$1, steps[i].$2, steps[i].$3),
          if (i < steps.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _stepRow(String num, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withValues(alpha: 0.14),
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              num,
              style: const TextStyle(
                color: _accent,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    color: Color(0xffa8a8a8),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── CTA ────────────────────────────────────────────────────────────────────
  Widget _ctaCard(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _responsive(context, 40, 24),
        vertical: 46,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accent.withValues(alpha: 0.16),
            _surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'Prêt à coder depuis votre poche ?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Gratuit et open source. ARM64 uniquement.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xffb8b8b8), fontSize: 14.5),
          ),
          const SizedBox(height: 26),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _open(_latestReleaseApkUrl),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Obtenir Panda IDE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _footer() {
    return Column(
      children: [
        Divider(color: _border.withValues(alpha: 0.5), height: 1),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              _pandaBadge(size: 26, radius: 8),
              const SizedBox(width: 9),
              const Text(
                'Panda IDE',
                style: TextStyle(
                  color: Color(0xff9a9a9a),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
            InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () =>
                  _open('https://github.com/ferelking242/panda-ide'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  'ferelking242/panda-ide',
                  style: TextStyle(
                    color: Color(0xff777777),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 27,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
      ),
    );
  }

  Widget _pandaBadge({required double size, required double radius}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        '🐼',
        style: TextStyle(fontSize: size * 0.55),
      ),
    );
  }

  double _responsive(BuildContext context, double wide, double narrow) {
    return MediaQuery.sizeOf(context).width >= 640 ? wide : narrow;
  }
}
