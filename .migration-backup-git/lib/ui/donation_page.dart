import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/ui_bloc/ui_bloc.dart';

class BuyMeCoffee extends StatelessWidget {
  const BuyMeCoffee({super.key});

  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _launchUPI(){
    const upiUrl = 'upi://pay?pa=athulas2005@oksbi&pn=HECKMON&tn=Support%20Panda&cu=INR';
    final intent = AndroidIntent(
      action: 'action_view',
      data: upiUrl,
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
      ],
    );

    intent.launch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<AppThemeBloc, AppThemeState>(
      builder: (context, appThemeState) {
        return Scaffold(
          backgroundColor: appThemeState.appTheme.scaffoldBg,
          appBar: AppBar(
            iconTheme: IconThemeData(color: appThemeState.appTheme.selectScreenCardTextColor),
            title: Text(
              'Support the Developer',
              style: TextStyle(
                color: appThemeState.appTheme.selectScreenCardTextColor,
                fontWeight: FontWeight.bold
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        'Enjoying Panda?',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: appThemeState.appTheme.selectScreenCardTextColor
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'If you like this project, consider buying me a coffee! Your support helps keep development active and the app free for everyone.',
                        style: TextStyle(
                          color: appThemeState.appTheme.selectScreenCardTextColor
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      InkWell(
                        onTap: () => _launchURL('https://www.buymeacoffee.com/bames_jond'),
                        child: SvgPicture.asset(
                          'assets/icons/bmc-button.svg',
                          height: 38,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text('Or support via:', style: TextStyle(
                        color: appThemeState.appTheme.selectScreenCardTextColor,
                        fontSize: 15
                      )),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IconButton(
                                icon: SvgPicture.asset('assets/icons/upi.svg', height: 18.5, width: 18.5),
                                onPressed: _launchUPI,
                                tooltip: 'UPI',
                              ),
                              IconButton(
                                icon: SvgPicture.asset('assets/icons/PayPal.svg', height: 18.5, width: 18.5),
                                onPressed: () => _launchURL('https://www.paypal.me/DollarDino'),
                                tooltip: 'PayPal',
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              dense: true,
                              leading: SvgPicture.asset(
                                height: 30,
                                width: 30,
                                'assets/icons/btc.svg'
                              ),
                              title: Text(
                                "bc1qsweu9pq82y4xdecsudadet78tw00lxd3cd2ke6",
                                softWrap: false,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text("Bitcoin Network"),
                              titleTextStyle: TextStyle(
                                color: appThemeState.appTheme.selectScreenCardTextColor
                              ),
                              subtitleTextStyle: TextStyle(
                                color: appThemeState.appTheme.selectScreenCardTextColor
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.copy,
                                  size: 18,
                                  color: appThemeState.appTheme.selectScreenCardTextColor
                                ),
                                tooltip: "Copy Address",
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: 'bc1qsweu9pq82y4xdecsudadet78tw00lxd3cd2ke6')
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Center(child: Row(
                                        children: [
                                          Text('Copied to clipboard!'),
                                          const SizedBox(width: 3),
                                          Icon(Icons.check_circle, size: 18, color: Colors.green)
                                        ],
                                      )),
                                      elevation: 3,
                                      width: 200,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)
                                      ),
                                    )
                                  );
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              dense: true,
                              leading: SvgPicture.asset(
                                height: 30,
                                width: 30,
                                'assets/icons/eth.svg'
                              ),
                              title: Text(
                                "0x1184E46A37d26e99F899e0a3e5a1E5D86897F6A1",
                                softWrap: false,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text("Ethereum Network"),
                              titleTextStyle: TextStyle(
                                color: appThemeState.appTheme.selectScreenCardTextColor
                              ),
                              subtitleTextStyle: TextStyle(
                                color: appThemeState.appTheme.selectScreenCardTextColor
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.copy,
                                  size: 18,
                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                ),
                                tooltip: "Copy Address",
                                onPressed: (){
                                  Clipboard.setData(
                                    const ClipboardData(text: '0x1184E46A37d26e99F899e0a3e5a1E5D86897F6A1')
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Center(child: Row(
                                        children: [
                                          Text('Copied to clipboard!'),
                                          const SizedBox(width: 3),
                                          Icon(Icons.check_circle, size: 18, color: Colors.green)
                                        ],
                                      )),
                                      elevation: 3,
                                      width: 200,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)
                                      ),
                                    )
                                  );
                                },
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Thank you for your support! ❤️',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.pink, fontWeight: FontWeight.bold),
                      ),
                    ],
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