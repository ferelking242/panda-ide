/// Modèle d'onglet du navigateur.
class BrowserTab {
  final String id;
  String title;
  String url;
  String profileId;
  bool isLoading;

  BrowserTab({
    required this.id,
    required this.url,
    required this.profileId,
    this.title = 'Nouvel onglet',
    this.isLoading = false,
  });

  BrowserTab copyWith({
    String? title,
    String? url,
    String? profileId,
    bool? isLoading,
  }) =>
      BrowserTab(
        id: id,
        title: title ?? this.title,
        url: url ?? this.url,
        profileId: profileId ?? this.profileId,
        isLoading: isLoading ?? this.isLoading,
      );
}
