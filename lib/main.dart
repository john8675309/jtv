import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xtream_code_client/xtream_code_client.dart';
import 'screens/SiginInScreen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'epg_models.dart';
import 'package:ffi/ffi.dart';

void main() async {
  await Hive.initFlutter();
  Hive.registerAdapter(EPGChannelAdapter());
  Hive.registerAdapter(EPGProgramAdapter());
  if (Platform.isLinux) {
    final libc = DynamicLibrary.open('libc.so.6');
    final setlocale = libc.lookupFunction<
        Pointer<Utf8> Function(Int32, Pointer<Utf8>),
        Pointer<Utf8> Function(int, Pointer<Utf8>)>('setlocale');
    final LC_NUMERIC = 1; // LC_NUMERIC constant in Linux
    setlocale(LC_NUMERIC, 'C'.toNativeUtf8());
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => XtreamCodeManager(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xtream Codes App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/signin',
      routes: {
        '/signin': (context) => SignInScreen(),
      },
    );
  }
}

class XtreamCodeManager extends ChangeNotifier {
  XtreamCode? client;

  Future<void> initialize(
      String url, String port, String username, String password) async {
    client = await XtreamCode.initialize(
      url: url,
      port: port,
      username: username,
      password: password,
    );
    notifyListeners();
  }
}
