import 'dart:async';

import 'package:fast_log/fast_log.dart';
import 'package:flutter/material.dart';

void main() => runFlutterServer((context) async {
  info("Server is running");
});

typedef ServerRunner = Future<void> Function(BuildContext context);

/// Call this to start your server. Runner is where you run your server but your given context
Future<void> runFlutterServer(ServerRunner runner) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FlutterServerApplication(runner: runner));
}

class FlutterServerApplication extends StatelessWidget {
  final ServerRunner runner;

  const FlutterServerApplication({super.key, required this.runner});

  @override
  Widget build(BuildContext context) => MaterialApp(
    color: Colors.blue,
    home: FlutterServerStateView(runner: runner),
  );
}

class FlutterServerStateView extends StatefulWidget {
  final ServerRunner runner;

  const FlutterServerStateView({super.key, required this.runner});

  @override
  State<FlutterServerStateView> createState() => FlutterServerStateViewState();
}

class FlutterServerStateViewState extends State<FlutterServerStateView> {
  @override
  void initState() {
    super.initState();
    widget.runner(context).catchError((e, es) {
      error(e);
      error(es);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
