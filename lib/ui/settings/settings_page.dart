import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pullcrane/data/app_database.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:pullcrane/domain/services/bluetooth_manager.dart';
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
  late final TextEditingController maxForceController;
  late final TextEditingController deviceNameController;

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
    maxForceController = TextEditingController();
    deviceNameController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    thresholdController.dispose();
    hysteresisController.dispose();
    maxForceController.dispose();
    deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppSettings settings = await AppStores.settings.load();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    if (!mounted) {
      return;
    }

    setState(() {
      thresholdController.text = settings.forceThresholdKg.toString();
      hysteresisController.text = settings.targetHysteresisKg.toString();
      maxForceController.text = settings.maxForceKg.toString();
      enableTargetHaptics = settings.enableTargetHaptics;
      requireZeroBeforeSetStart = settings.requireZeroBeforeSetStart;
      deviceNameController.text =
          prefs.getString('ble_device_name') ?? CraneScaleService.defaultDeviceName;

      externalDbPath = prefs.getString('external_db_dir');
      isExternalDbEnabled = externalDbPath != null;

      isLoading = false;
    });

    if (AppDatabase.instance.externalDirectoryMissing && isExternalDbEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'The external folder "$externalDbPath" is unavailable. '
            'Using the internal database until it is back. '
            'Your external data has not been deleted.',
          ),
        ),
      );
    }
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
      maxForceKg: int.parse(maxForceController.text.trim()),
    );

    await AppStores.settings.save(settings);

    // Apply live so the change takes effect without an app restart.
    CraneScaleService.instance.maxForceKg = settings.maxForceKg;
    final String deviceName = deviceNameController.text.trim();
    CraneScaleService.instance.deviceNameFilter = deviceName;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('ble_device_name', deviceName);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );
  }

  Future<void> _toggleExternalStorage(bool enable) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? previousPath = externalDbPath;

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
      // Copy external data back first so it is not orphaned.
      try {
        await AppDatabase.instance.copyExternalToInternal();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to copy external database back: $e')),
        );
        return;
      }
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
      await AppStores.reload();
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
      // Revert preference and UI state on failure
      if (enable) {
        await prefs.remove('external_db_dir');
      } else if (previousPath != null) {
        await prefs.setString('external_db_dir', previousPath);
      }
      setState(() {
        isExternalDbEnabled = !enable;
        externalDbPath = enable ? null : previousPath;
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
                  TextFormField(
                    controller: maxForceController,
                    decoration: const InputDecoration(
                      labelText: 'Maximum force (kg)',
                      helperText:
                          'Upper limit for readings and targets. Set it above your heaviest lift.',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final int? parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 100 || parsed > 500) {
                        return 'Enter maximum force between 100 and 500 kg.';
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
                    'Scale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: deviceNameController,
                    decoration: const InputDecoration(
                      labelText: 'Bluetooth device name',
                      helperText:
                          'Only devices advertising this exact name are listed.',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Enter a device name.';
                      }
                      return null;
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
