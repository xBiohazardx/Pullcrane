import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:pullcrane/domain/services/bluetooth_manager.dart';
import 'package:pullcrane/ui/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  StackTrace? startupStackTrace;
  try {
    await AppStores.init();

    // Apply persisted configuration to the force input service.
    final AppSettings settings = await AppStores.settings.load();
    CraneScaleService.instance.maxForceKg = settings.maxForceKg;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    CraneScaleService.instance.deviceNameFilter =
        prefs.getString('ble_device_name') ?? CraneScaleService.defaultDeviceName;
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
