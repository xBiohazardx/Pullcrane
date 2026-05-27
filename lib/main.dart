import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  StackTrace? startupStackTrace;
  try {
    await AppStores.init();
  } catch (error, stackTrace) {
    startupError = error;
    startupStackTrace = stackTrace;
    debugPrint('Startup initialization failed: $error');
    debugPrint('$stackTrace');
  }
  runApp(MyApp(
    startupError: startupError,
    startupStackTrace: startupStackTrace,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.startupError, this.startupStackTrace});

  final Object? startupError;
  final StackTrace? startupStackTrace;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final ColorScheme fallbackLight = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.light,
    );
    final ColorScheme fallbackDark = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    );

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'Pullcrane',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightDynamic ?? fallbackLight,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkDynamic ?? fallbackDark,
          ),
          themeMode: ThemeMode.system,
          home: startupError == null
              ? const AppShell()
              : _StartupErrorPage(
                  error: startupError!,
                  stackTrace: startupStackTrace,
                ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Startup Error')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          'Failed to initialize app storage.\n\n$error\n\n${stackTrace ?? ''}',
        ),
      ),
    );
  }
}
