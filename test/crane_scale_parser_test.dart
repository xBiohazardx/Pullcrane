import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pullcrane/domain/services/crane_scale_parser.dart';

Uint8List advertisementWithWeight(int rawHundredths) {
  final bytes = Uint8List(20);
  ByteData.sublistView(bytes).setInt16(
    CraneScaleParser.weightOffset,
    rawHundredths,
    Endian.big,
  );
  return bytes;
}

void main() {
  test('parses big-endian int16 hundredths of kg at the default offset', () {
    // 80.00 kg -> 8000 hundredths.
    expect(
      CraneScaleParser.parseWeightKg(
        advertisementWithWeight(8000),
        maxForceKg: 200,
      ),
      80,
    );
  });

  test('parses weights above 100 kg (no artificial ceiling)', () {
    // 145.32 kg -> 14532 hundredths.
    expect(
      CraneScaleParser.parseWeightKg(
        advertisementWithWeight(14532),
        maxForceKg: 200,
      ),
      145,
    );
  });

  test('clamps to the configured maximum force', () {
    expect(
      CraneScaleParser.parseWeightKg(
        advertisementWithWeight(30000),
        maxForceKg: 200,
      ),
      200,
    );
  });

  test('clamps negative readings (tare drift) to zero', () {
    expect(
      CraneScaleParser.parseWeightKg(
        advertisementWithWeight(-350),
        maxForceKg: 200,
      ),
      0,
    );
  });

  test('returns null when the buffer is too short', () {
    expect(
      CraneScaleParser.parseWeightKg(
        Uint8List(CraneScaleParser.weightOffset + 1),
        maxForceKg: 200,
      ),
      isNull,
    );
  });

  test('parses at the payload offset when requested', () {
    final payload = Uint8List(16);
    ByteData.sublistView(payload).setInt16(
      CraneScaleParser.payloadWeightOffset,
      10250,
      Endian.big,
    );
    expect(
      CraneScaleParser.parseWeightKg(
        payload,
        offset: CraneScaleParser.payloadWeightOffset,
        maxForceKg: 200,
      ),
      103, // rounds half up from 102.5
    );
  });
}
