import 'dart:typed_data';

/// Pure parsing logic for WH-C06 crane scale advertisements.
///
/// The scale broadcasts its current weight in advertisement manufacturer
/// data as a big-endian int16 in 1/100 kg. Kept free of Flutter and BLE
/// imports so it can be unit-tested directly.
class CraneScaleParser {
  CraneScaleParser._();

  /// Byte offset of the weight inside the full manufacturer data blob
  /// (company id included).
  static const int weightOffset = 12;

  /// Offset to try inside the manufacturer data payload (without company id).
  static const int payloadWeightOffset = weightOffset - 2;

  static const int weightLength = 2;

  /// Parses the weight in whole kilograms from [bytes] at [offset].
  ///
  /// Returns `null` when [bytes] is too short to contain a weight at
  /// [offset]. Negative readings (tare drift) clamp to 0 and readings are
  /// capped at [maxForceKg].
  static int? parseWeightKg(
    Uint8List bytes, {
    int offset = weightOffset,
    required int maxForceKg,
  }) {
    if (offset < 0 || bytes.length < offset + weightLength) {
      return null;
    }

    final ByteData data = ByteData.sublistView(
      bytes,
      offset,
      offset + weightLength,
    );
    final int rawWeight = data.getInt16(0, Endian.big);
    final double kilograms = rawWeight / 100.0;
    return kilograms.round().clamp(0, maxForceKg);
  }
}
