import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_repositories.dart';
import 'package:pullcrane/domain/models/app_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController thresholdController;
  late final TextEditingController hysteresisController;
  late final TextEditingController maxLiftController;

  bool enableTargetHaptics = AppSettings.defaults.enableTargetHaptics;
  bool requireZeroBeforeSetStart =
      AppSettings.defaults.requireZeroBeforeSetStart;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    thresholdController = TextEditingController();
    hysteresisController = TextEditingController();
    maxLiftController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    thresholdController.dispose();
    hysteresisController.dispose();
    maxLiftController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppSettings settings = await AppRepositories.settings.load();
    if (!mounted) {
      return;
    }

    setState(() {
      thresholdController.text = settings.forceThresholdKg.toString();
      hysteresisController.text = settings.targetHysteresisKg.toString();
      maxLiftController.text = settings.userMaxLiftKg.toString();
      enableTargetHaptics = settings.enableTargetHaptics;
      requireZeroBeforeSetStart = settings.requireZeroBeforeSetStart;
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
      userMaxLiftKg: int.parse(maxLiftController.text.trim()),
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
                    'Max Lift',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: maxLiftController,
                    decoration: const InputDecoration(
                      labelText: 'Current max lift (kg)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final int? parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed <= 0 || parsed > 500) {
                        return 'Enter max lift between 1 and 500 kg.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Max-lift measurement page will be added in phase 4.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.fitness_center),
                    label: const Text('Measure max lift (coming soon)'),
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

