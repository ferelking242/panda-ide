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

// API testing panel
// Extracted from widgets.dart

class APITesting extends StatelessWidget {
  final Map<String, String> params, headers;
  final TextEditingController apiUrlController;
  final AppTheme appTheme;
  final TabController paramTabController, apiTabController;
  const APITesting({
    super.key,
    required this.params,
    required this.headers,
    required this.apiUrlController,
    required this.appTheme,
    required this.paramTabController,
    required this.apiTabController,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 15),
      child: BlocBuilder<ApiBloc, ApiState>(
        builder: (context, webState) {
          Map<TextEditingController, TextEditingController> paramControllers = {
            for (int _ in Iterable.generate(webState.params.length + 1))
              TextEditingController(): TextEditingController(),
          };
          Map<TextEditingController, TextEditingController> headerControllers =
              {
                for (int _ in Iterable.generate(webState.headers.length + 1))
                  TextEditingController(): TextEditingController(),
              };
          if (webState.params.isNotEmpty) {
            for (int index = 0; index < webState.params.length; index++) {
              paramControllers.keys.toList()[index].text = webState.params.keys.toList()[index];
              paramControllers.values.toList()[index].text = webState.params.values.toList()[index];
              params[webState.params.keys.toList()[index]] = webState.params.values.toList()[index];
            }
          }
          if (webState.headers.isNotEmpty) {
            for (int index = 0; index < webState.headers.length; index++) {
              headerControllers.keys.toList()[index].text = webState.headers.keys.toList()[index];
              headerControllers.values.toList()[index].text = webState.headers.values.toList()[index];
              headers[webState.headers.keys.toList()[index]] = webState.headers.values.toList()[index];
            }
          }
          apiUrlController.text = webState.url ?? "Enter URL";
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 15),
              Text(
                "API TESTING",
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor,
                  fontWeight: appTheme.isDark
                    ? FontWeight.w300
                    : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 15),
              DropdownButtonHideUnderline(
                child: DropdownButton(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  value: webState.method,
                  dropdownColor: appTheme.isDark
                    ? const Color(0xff2b2b2b)
                    : const Color.fromARGB(255, 241, 241, 241),
                  items: [
                    DropdownMenuItem(
                      value: "POST",
                      child: Text(
                        "POST",
                        style: TextStyle(
                          color: const Color(0xffe0790b),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: "GET",
                      child: Text(
                        "GET",
                        style: TextStyle(
                          color: const Color(0xff26cda3),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: "PUT",
                      child: Text(
                        "PUT",
                        style: TextStyle(
                          color: const Color(0xff097bed),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: "DELETE",
                      child: Text(
                        "DELETE",
                        style: TextStyle(
                          color: const Color(0xfff22814),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    context.read<ApiBloc>().add(ApiEvent(method: value!));
                  },
                ),
              ),
              SizedBox(
                height: 50,
                width: 250,
                child: TextField(
                  controller: apiUrlController,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: Colors.grey),
                  cursorColor: Colors.grey,
                  onChanged: (val) {
                    context.read<ApiBloc>().add(GetUrl(url: val));
                  },
                  decoration: const InputDecoration(
                    hintText: "Enter Url",
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xff0e639c)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TabBar(
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                controller: paramTabController,
                dividerColor: appTheme.isDark
                  ? const Color.fromARGB(255, 61, 61, 61)
                  : const Color.fromARGB(255, 182, 182, 182),
                dividerHeight: 1.5,
                unselectedLabelColor: appTheme.isDark
                  ? Colors.grey
                  : const Color.fromARGB(255, 102, 102, 102),
                labelColor: const Color.fromARGB(255, 62, 142, 195),
                indicatorColor: const Color(0xff0e639c),
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(text: "Params"),
                  Tab(text: "Headers"),
                  Tab(text: "Body"),
                ],
              ),
              const SizedBox(height: 15),
              SizedBox(
                height:
                    60 *
                    ((() {
                      if (webState.params.isEmpty && webState.headers.isEmpty) {
                        return 1.0;
                      }
                      if (webState.params.length > webState.headers.length) {
                        return webState.params.length.toDouble() + 1.0;
                      }
                      return webState.headers.length.toDouble() + 1.0;
                    })()),
                child: TabBarView(
                  controller: paramTabController,
                  children: [
                    Column(
                      children: List.generate(webState.params.length + 1, (
                        index,
                      ) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: TextStyle(
                                    color: appTheme.selectScreenCardTextColor,
                                  ),
                                  controller: paramControllers.keys
                                      .toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: TextStyle(
                                    color: appTheme.selectScreenCardTextColor,
                                  ),
                                  controller: paramControllers.values
                                      .toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (index == webState.params.length) {
                                    if (paramControllers.keys.toList()[index].text.isNotEmpty &&
                                        paramControllers.values.toList()[index].text.isNotEmpty) {
                                      params.addEntries({
                                          paramControllers.keys.toList()[index].text: paramControllers.values.toList()[index].text,
                                        }.entries,
                                      );
                                    }
                                  } else {
                                    params.remove(
                                      paramControllers.keys.toList()[index].text,
                                    );
                                  }
                                  context.read<ApiBloc>().add(
                                    GetParams(params: params),
                                  );
                                  String baseUrl = apiUrlController.text.split(
                                    '?',
                                  )[0];
                                  String queryString = '';
                                  if (params.isNotEmpty) {
                                    queryString = params.entries.map((entry) =>'${entry.key}=${entry.value}').join('&');
                                  }
                                  String newUrl = queryString.isNotEmpty
                                    ? '$baseUrl?$queryString'
                                    : baseUrl;
                                  apiUrlController.value = apiUrlController.value.copyWith(
                                    text: newUrl,
                                    selection: TextSelection.collapsed(
                                      offset: newUrl.length,
                                    ),
                                  );
                                  context.read<ApiBloc>().add(
                                    GetUrl(url: newUrl),
                                  );
                                },
                                icon: Icon(
                                  index == webState.params.length
                                    ? Icons.add
                                    : Icons.remove,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    Column(
                      children: List.generate(webState.headers.length + 1, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: const TextStyle(color: Colors.grey),
                                  controller: headerControllers.keys.toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: const TextStyle(color: Colors.grey),
                                  controller: headerControllers.values.toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (index == webState.headers.length) {
                                    if (headerControllers.keys.toList()[index].text.isNotEmpty &&
                                        headerControllers.values.toList()[index].text.isNotEmpty) {
                                      headers.addEntries({
                                        headerControllers.keys.toList()[index].text: headerControllers.values.toList()[index].text,
                                      }.entries,
                                      );
                                    }
                                  } else {
                                    headers.remove(
                                      headerControllers.keys.toList()[index].text,
                                    );
                                  }
                                  context.read<ApiBloc>().add(
                                    GetHeaders(headers: headers),
                                  );
                                },
                                icon: Icon(
                                  index == webState.headers.length
                                    ? Icons.add
                                    : Icons.remove,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 7),
                      child: TextField(
                        textAlignVertical: TextAlignVertical.top,
                        cursorColor: Colors.grey,
                        style: TextStyle(color: Colors.grey),
                        maxLines: null,
                        minLines: null,
                        decoration: InputDecoration(
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xff0e639c)),
                          ),
                          border: OutlineInputBorder(),
                        ),
                        expands: true,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 100,
                child: ElevatedButton(
                  onPressed: () async {
                    Map<String, dynamic> data = await sendRequest(
                      url: apiUrlController.text,
                      method: webState.method,
                      headers: webState.headers,
                    );
                    if (context.mounted) {
                      context.read<ApiBloc>().add(GotApiData(data: data));
                    }
                  },
                  style: const ButtonStyle(
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    backgroundColor: WidgetStatePropertyAll(Color(0xff0e639c)),
                    foregroundColor: WidgetStatePropertyAll(Colors.white),
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  child: const Text("Send"),
                ),
              ),
              webState.data == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: TabBar(
                      controller: apiTabController,
                      dividerColor: const Color.fromARGB(255, 61, 61, 61),
                      dividerHeight: 1.5,
                      unselectedLabelColor: Colors.grey,
                      labelColor: const Color.fromARGB(255, 62, 142, 195),
                      indicatorColor: const Color(0xff0e639c),
                      indicatorWeight: 2.5,
                      tabs: const [
                        Tab(
                          child: Text("{ }", style: TextStyle(fontSize: 22)),
                        ),
                        Tab(icon: FaIcon(FontAwesomeIcons.html5)),
                        Tab(icon: Icon(Icons.raw_on_sharp, size: 35)),
                      ],
                    ),
                  ),
              const SizedBox(height: 20),
              webState.data == null
                ? const SizedBox.shrink()
                : Expanded(
                    child: TabBarView(
                      controller: apiTabController,
                      children: [
                        JsonWidget(
                          expandIcon: const Icon(
                            Icons.keyboard_arrow_down_sharp,
                            color: Colors.grey,
                          ),
                          collapseIcon: const Icon(
                            Icons.keyboard_arrow_right_sharp,
                            color: Colors.grey,
                          ),
                          json: webState.data!,
                        ),
                        InAppWebView(
                          onWebViewCreated: (InAppWebViewController webViewController) {
                            webViewController.loadData(
                              data: webState.data!['body'],
                            );
                          },
                        ),
                        SingleChildScrollView(
                          child: Text(
                            webState.data!.toString(),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}


