import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/auth_token_holder.dart';
import 'core/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    runApp(_BootErrorApp(error: details.exception, stack: details.stack));
  };
  try {
    await dotenv.load(fileName: '.env');
    await AuthTokenHolder.instance.load();
    await NotificationService.instance.init();
    runApp(const ProviderScope(child: DriveCheckApp()));
  } catch (e, st) {
    runApp(_BootErrorApp(error: e, stack: st));
  }
}

class _BootErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace? stack;
  const _BootErrorApp({required this.error, this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Boot error', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.red)),
                  const SizedBox(height: 12),
                  Text(error.toString(), style: const TextStyle(fontSize: 16, color: Colors.black)),
                  const SizedBox(height: 16),
                  if (stack != null) Text(stack.toString(), style: const TextStyle(fontSize: 11, color: Colors.black54, fontFamily: 'Courier')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
