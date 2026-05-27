import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pullcrane/data/app_repositories.dart';
import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController thresholdController;
  late final TextEditingController hysteresisController;

  bool enableTargetHaptics = AppSettings.defaults.enableTargetHaptics;
  bool requireZeroBeforeSetStart = AppSettings.defaults.requireZeroBeforeSetStart;
  bool isExternalDbEnabled = false;
  String? externalDbPath;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    thresholdController = TextEditingController();
    hysteresisController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    thresholdController.dispose();
    hysteresisController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppSettings settings = await AppRepositories.settings.load();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    if (!mounted) {
      return;
    }

    setState(() {
      thresholdController.text = settings.forceThresholdKg.toString();
      hysteresisController.text = settings.targetHysteresisKg.toString();
      enableTargetHaptics = settings.enableTargetHaptics;
      requireZeroBeforeSetStart = settings.requireZeroBeforeSetStart;
      
      externalDbPath = prefs.getString('external_db_dir');
      isExternalDbEnabled = externalDbPath != null;
      
      isLoading = false;
    });
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final AppSettings settings = AppSettings(
      forceThresholdKg: int.parse(thresholdController.text.trim()),
      targetHysteresisKg: int.parse(hysteresisController.text.trim()),
      enableTargetHaptics: enableTargetHaptics,
      requireZeroBeforeSetStart: requireZeroBeforeSetStart,
    );

    await AppRepositories.settings.save(settings);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );
  }

  Future<void> _toggleExternalStorage(bool enable) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    if (enable) {
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          await Permission.storage.request();
        }
        
        if (!await Permission.manageExternalStorage.isGranted && !await Permission.storage.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission is required to save data externally.')));
          return;
        }
      }

      final String? selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory == null) {
        // User canceled the picker
        return;
      }

      await prefs.setString('external_db_dir', selectedDirectory);
      setState(() {
        externalDbPath = selectedDirectory;
        isExternalDbEnabled = true;
      });
    } else {
      await prefs.remove('external_db_dir');
      setState(() {
        externalDbPath = null;
        isExternalDbEnabled = false;
      });
    }

    if (!mounted) return;

    // Show loading while databases are being reloaded
    setState(() {
      isLoading = true;
    });

    try {
      await AppRepositories.reload();
      await _load(); // reload settings from the newly active DB
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enable 
              ? 'Database location moved to $externalDbPath' 
              : 'Switched back to internal database'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to switch database: $e')),
      );
      // Revert UI state on failure
      setState(() {
        if (enable) {
          isExternalDbEnabled = false;
          externalDbPath = null;
          prefs.remove('external_db_dir');
        } else {
          isExternalDbEnabled = true;
          externalDbPath = prefs.getString('external_db_dir');
        }
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Execution',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: thresholdController,
                    decoration: const InputDecoration(
                      labelText: 'Default force threshold (kg)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final int? parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed <= 0 || parsed > 100) {
                        return 'Enter threshold between 1 and 100 kg.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: hysteresisController,
                    decoration: const InputDecoration(
                      labelText: 'Target area hysteresis (kg)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final int? parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 0 || parsed > 20) {
                        return 'Enter hysteresis between 0 and 20 kg.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Target haptics'),
                    subtitle: const Text('Vibrate when force is inside target zone.'),
                    value: enableTargetHaptics,
                    onChanged: (value) {
                      setState(() {
                        enableTargetHaptics = value;
                      });
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require zero before set start'),
                    subtitle: const Text('Force must drop to 0 before threshold can start a set.'),
                    value: requireZeroBeforeSetStart,
                    onChanged: (value) {
                      setState(() {
                        requireZeroBeforeSetStart = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Storage',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Save data externally'),
                    subtitle: Text(isExternalDbEnabled && externalDbPath != null
                        ? 'Saving to: $externalDbPath'
                        : 'Choose a folder to save your data to'),
                    value: isExternalDbEnabled,
                    onChanged: _toggleExternalStorage,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save Settings'),
                  ),
                ],
              ),
            ),
    );
  }
}
