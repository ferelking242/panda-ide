# 08 — Adaptation Mobile (Phase 4 — Critique)

## Objectif
Panda est mobile-first mais le layout est encore desktop-oriented.
Il faut des breakpoints responsive et des patterns mobile natifs.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/ui/home.dart` | **MODIFIER** — Layout responsive avec breakpoints |
| `lib/ui/widgets/sidebar_drawer.dart` | **CRÉER** — Sidebar en Drawer sur mobile |
| `lib/ui/widgets/bottom_nav.dart` | **CRÉER** — Bottom navigation pour mobile |
| `lib/ui/settings_page.dart` | **MODIFIER** — Settings pleine largeur sur mobile |
| `lib/ui/editor/bottom_panel.dart` | **MODIFIER** — Terminal en bottom sheet sur mobile |
| `lib/utils/responsive.dart` | **CRÉER** — Helper responsive breakpoints |

## Breakpoints

```dart
class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1024;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;
}
```

## Layout par breakpoint

### MOBILE (< 600px)
```
┌──────────────────┐
│  TOP BAR          │
├──────────────────┤
│  EDITOR (full)    │
│                   │
├──────────────────┤
│ BOTTOM NAV        │
│ ⚙️ 🔍 📁 🤖  │
├──────────────────┤
│ STATUS BAR        │
└──────────────────┘

- Sidebar → Drawer (swipe left)
- Terminal → Bottom sheet draggable
- Settings → pleine largeur
```

### TABLET (600-1024px)
```
┌────┬──────────┐
│ SB │  TOP BAR  │
├────┤──────────┤
│    │  EDITOR   │
│    │           │
├────┤──────────┤
│NAV │  BOTTOM   │
│    │  PANEL    │
├────┴──────────┤
│ STATUS BAR     │
└────────────────┘

- Sidebar réduite en icônes (40px)
- Éditeur rétracté
```

### DESKTOP (> 1024px)
```
┌──┬────┬──────────┐
│AB│ SB │  TOP BAR  │
├──┼────┤──────────┤
│  │    │ TABS     │
│  │    ├──────────┤
│  │    │ EDITOR   │
│  │    │          │
├──┼────┤──────────┤
│  │    │ BOTTOM   │
│  │    │ PANEL    │
├──┴────┼──────────┤
│ STATUS BAR       │
└──────────────────┘

- Layout complet VS Code
```

## Code : Sidebar Drawer (mobile)

```dart
// Avant (desktop):
Row(children: [
  _buildActivityBar(),  // 40px
  _buildSidebarPanel(), // 240px
  Expanded(child: _buildEditor()),
])

// Après (responsive):
if (Responsive.isMobile(context))
  Scaffold(
    drawer: _buildSidebarDrawer(),
    body: _buildMobileLayout(),
  )
else
  Row(children: [
    _buildActivityBar(),
    _buildSidebarPanel(),
    Expanded(child: _buildEditor()),
  ])
```

```dart
// Sidebar Drawer (mobile)
Drawer(
  child: Container(
    width: 280,
    child: Column(children: [
      // Header
      SafeArea(child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.folder, color: cs.primary),
          SizedBox(width: 8),
          Text('Explorer', style: TextStyle(fontWeight: FontWeight.w700)),
          Spacer(),
          IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
      )),
      Divider(),
      // File tree
      Expanded(child: _buildFileTree()),
    ]),
  ),
)
```

## Code : Bottom Navigation (mobile)

```dart
// Bottom nav pour mobile
BottomNavigationBar(
  currentIndex: _selectedNavIndex,
  onTap: (i) => setState(() => _selectedNavIndex = i),
  type: BottomNavigationBarType.fixed,
  items: [
    BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Explorer'),
    BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
    BottomNavigationBarItem(icon: Icon(Icons.code), label: 'Editor'),
    BottomNavigationBarItem(icon: Icon(Icons.smart_toy), label: 'Agent'),
    BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
  ],
)
```

## Priorité
**P0 — Critique** — Panda est un IDE mobile.

## Effort
14h (responsive + drawer + bottom nav + settings mobile + terminal sheet)

## Vérification
1. L'app doit être utilisable sur un téléphone 360px de large
2. Swipe left doit ouvrir la sidebar
3. Les 5 boutons bottom nav doivent fonctionner
4. Le terminal doit être une bottom sheet
5. Les settings doivent être pleine largeur
