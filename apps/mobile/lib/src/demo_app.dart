import 'package:flutter/material.dart';
import 'design.dart';
import 'translation.dart';

class SignBridgeApp extends StatelessWidget {
  const SignBridgeApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'SignBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          primaryColor: primary,
          scaffoldBackgroundColor: canvas,
          colorScheme: const ColorScheme.light(primary: primary),
          appBarTheme: const AppBarTheme(
              backgroundColor: canvas, foregroundColor: primary, elevation: 0)),
      home: const TranslationPage());
}
