import 'package:flutter/material.dart';
import 'package:pullcrane/domain/services/bluetooth_manager.dart';

class BluetoothConnectionSheet extends StatefulWidget {
  const BluetoothConnectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const BluetoothConnectionSheet(),
    );
  }

  @override
  State<BluetoothConnectionSheet> createState() => _BluetoothConnectionSheetState();
}

class _BluetoothConnectionSheetState extends State<BluetoothConnectionSheet> {
  @override
  void initState() {
    super.initState();
    if (CraneScaleService.instance.state == ScaleConnectionState.disconnected) {
      CraneScaleService.instance.startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CraneScaleService.instance,
      builder: (context, _) {
        final state = CraneScaleService.instance.state;
        final results = CraneScaleService.instance.scanResults;
        final connectedDevice = CraneScaleService.instance.connectedDevice;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Connect Scale',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (state == ScaleConnectionState.scanning || state == ScaleConnectionState.connecting)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (state == ScaleConnectionState.connected)
                        TextButton(
                          onPressed: () {
                            CraneScaleService.instance.disconnect();
                          },
                          child: const Text('Disconnect'),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () {
                            CraneScaleService.instance.startScan();
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (CraneScaleService.instance.lastError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            CraneScaleService.instance.lastError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state == ScaleConnectionState.connected && (connectedDevice != null || CraneScaleService.instance.isSimulated)) ...[
                   ListTile(
                     leading: const Icon(Icons.bluetooth_connected, color: Colors.green),
                     title: Text(CraneScaleService.instance.isSimulated 
                        ? 'Simulated Device (Finger Drag)' 
                        : (connectedDevice?.name ?? '').isNotEmpty 
                            ? connectedDevice!.name! 
                            : 'Unknown Device'),
                     subtitle: const Text('Connected'),
                     trailing: const Icon(Icons.check, color: Colors.green),
                   ),
                   const Divider(),
                ],
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (state != ScaleConnectionState.connecting && !CraneScaleService.instance.isSimulated)
                        ListTile(
                          leading: const Icon(Icons.touch_app),
                          title: const Text('Simulated Device (Finger Drag)'),
                          subtitle: const Text('Testing without a scale'),
                          onTap: () async {
                            await CraneScaleService.instance.connectSimulated();
                          },
                        ),
                      if (results.isEmpty && state != ScaleConnectionState.scanning && state != ScaleConnectionState.connecting)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: Text('No devices found.')),
                        ),
                      ...results.map((device) {
                        final name = (device.name ?? '').isNotEmpty ? device.name! : 'Unknown Device';
                        return ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(name),
                          subtitle: Text(device.deviceId),
                          trailing: Text('${device.rssi ?? '-'} dBm'),
                          onTap: state == ScaleConnectionState.connecting
                              ? null
                              : () async {
                                  await CraneScaleService.instance.connect(device);
                                },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

