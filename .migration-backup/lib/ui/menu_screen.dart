import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../ui/editor_page.dart';
import '../utils/constants.dart';
import '../utils/languages.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Card> allLangs = languages
        .map((e) => Card(child: ListTile(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          leading: e.icon ?? langtxt.icon,
          title: Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Text(e.name),
          ),
          subtitle: Text(e.details),
          onTap: () => Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                EditorPage(
                  languageDetails: e,
                  rootDir: templateDir,
                  isProject: false,
                ),
              transitionsBuilder:(context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              })),
            )))
        .toList();
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) => context.read<MenuSearchBloc>().add(Search(searchedLangs: const [])),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(expandedHeight: 65, actions: [
              const SizedBox(height: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 55, right: 20),
                  child: TextField(
                      onEditingComplete: () => context.read<MenuSearchBloc>().add(Search(searchedLangs: const [])),
                      onChanged: (data) {
                        List<Language> searched = languages
                          .where((language) => language.name.toLowerCase().contains(data.toLowerCase())).toList()..sort((a, b) {
                          String query = data.toLowerCase();
                          String nameA = a.name.toLowerCase();
                          String nameB = b.name.toLowerCase();
                          if (nameA.startsWith(query) &&
                              !nameB.startsWith(query)) {
                            return -1;
                          } else if (!nameA.startsWith(query) &&
                              nameB.startsWith(query)) {
                            return 1;
                          }
                            return 0;
                          });
                        List<Card> searchedLangs = searched
                          .map((e) => Card(child: ListTile(
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(10))),
                            leading: e.icon ?? langtxt.icon,
                            title: Padding(
                              padding: const EdgeInsets.only(left: 5),
                              child: Text(e.name),
                            ),
                            subtitle: Text(e.details),
                            onTap: () => Navigator.of(context).push(
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) =>
                                  EditorPage(languageDetails: e, rootDir: templateDir, isProject: false),
                                transitionsBuilder:(context, animation, secondaryAnimation, child) {
                                  return SizeTransition(
                                    sizeFactor: animation,
                                    child: child,
                                  );
                                }
                              )
                            ),
                          ))).toList();
                        context.read<MenuSearchBloc>().add(Search(searchedLangs:data.isEmpty ? [] : searchedLangs));
                      },
                      style: const TextStyle(color: Colors.grey),
                      cursorColor: const Color(0xff6d6d6d),
                      decoration: const InputDecoration(
                          hintText: "Search language",
                          prefixIcon: Icon(Icons.search),
                          focusedBorder: OutlineInputBorder(
                            borderSide:BorderSide(color: Color(0xff0178b9)),
                            borderRadius:BorderRadius.all(Radius.circular(35))),
                          border: OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(35)))
                      )
                    ),
                ),
              )
            ]),
            BlocBuilder<MenuSearchBloc, MenuSearchState>(
              builder: (context, state) {
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    childCount: state.searchedLangs.isEmpty
                      ? languages.length
                      : state.searchedLangs.length,
                    (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 3),
                        child: state.searchedLangs.isEmpty
                          ? allLangs[index]
                          : state.searchedLangs[index],
                      );
                    },
                  ),
                );
              },
            )
          ],
        ),
      ),
    );
  }
}
