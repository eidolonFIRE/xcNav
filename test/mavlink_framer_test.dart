import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:xcnav/models/mavlink.dart';

/// Build a fake 46 byte traffic report frame (contents beyond header don't matter for framing).
List<int> frame(int fill) => [0xFE, 38, 0, 1, 1, 246, ...List.filled(38, fill), 0xAA, 0xBB];

void main() {
  test("single frame in one chunk", () {
    final framer = MavlinkFramer();
    final out = framer.add(frame(7));
    expect(out.length, 1);
    expect(out.first, Uint8List.fromList(frame(7)));
  });

  test("frame split across chunks with leading garbage", () {
    final framer = MavlinkFramer();
    final data = [1, 2, 3, ...frame(5)];
    expect(framer.add(data.sublist(0, 4)), isEmpty);
    expect(framer.add(data.sublist(4, 20)), isEmpty);
    final out = framer.add(data.sublist(20));
    expect(out.length, 1);
    expect(out.first, Uint8List.fromList(frame(5)));
  });

  test("header split between chunks", () {
    final framer = MavlinkFramer();
    final data = frame(9);
    expect(framer.add([0x00, data[0]]), isEmpty);
    final out = framer.add(data.sublist(1));
    expect(out.length, 1);
    expect(out.first, Uint8List.fromList(data));
  });

  test("multiple frames in one chunk", () {
    final framer = MavlinkFramer();
    final out = framer.add([...frame(1), 0x00, ...frame(2), ...frame(3).sublist(0, 10)]);
    expect(out.length, 2);
    expect(out[0], Uint8List.fromList(frame(1)));
    expect(out[1], Uint8List.fromList(frame(2)));
    final rest = framer.add(frame(3).sublist(10));
    expect(rest.length, 1);
    expect(rest.first, Uint8List.fromList(frame(3)));
  });

  test("other message lengths are skipped", () {
    final framer = MavlinkFramer();
    final out = framer.add([0xFE, 14, 0, 1, 1, 29, ...List.filled(16, 0), ...frame(4)]);
    expect(out.length, 1);
    expect(out.first, Uint8List.fromList(frame(4)));
  });

  test("clear drops partial frame", () {
    final framer = MavlinkFramer();
    framer.add(frame(1).sublist(0, 20));
    framer.clear();
    expect(framer.add(frame(1).sublist(20)), isEmpty);
  });
}
