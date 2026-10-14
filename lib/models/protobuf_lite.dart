import 'dart:convert';
import 'dart:typed_data';

/// Protobuf wire types
class PbWireType {
  static const int varint = 0;
  static const int fixed64 = 1;
  static const int lengthDelimited = 2;
  static const int fixed32 = 5;
}

/// A single raw field from a protobuf message.
class PbField {
  final int number;
  final int wireType;

  /// Set for varint, fixed32, and fixed64 fields.
  final int? intValue;

  /// Set for length-delimited fields.
  final Uint8List? bytes;

  const PbField(this.number, this.wireType, {this.intValue, this.bytes});
}

/// Minimal protobuf wire-format codec.
///
/// Keeps every field it decodes (including ones it doesn't understand) so a message can be read,
/// tweaked, and re-encoded without dropping data. Only the handful of features the Meshtastic BLE
/// API needs are supported (no packed repeated fields, no groups).
class PbMessage {
  final List<PbField> fields;

  PbMessage([List<PbField>? fields]) : fields = fields ?? [];

  /// Throws [FormatException] if the data is malformed.
  factory PbMessage.decode(List<int> data) {
    final reader = _PbReader(data);
    final fields = <PbField>[];
    while (!reader.done) {
      final key = reader.readVarint();
      final number = key >>> 3;
      final wireType = key & 0x7;
      if (number == 0) throw const FormatException("Invalid protobuf field number 0");
      switch (wireType) {
        case PbWireType.varint:
          fields.add(PbField(number, wireType, intValue: reader.readVarint()));
          break;
        case PbWireType.fixed64:
          fields.add(PbField(number, wireType, intValue: reader.readFixed64()));
          break;
        case PbWireType.lengthDelimited:
          fields.add(PbField(number, wireType, bytes: reader.readBytes(reader.readVarint())));
          break;
        case PbWireType.fixed32:
          fields.add(PbField(number, wireType, intValue: reader.readFixed32()));
          break;
        default:
          throw FormatException("Unsupported protobuf wire type $wireType");
      }
    }
    return PbMessage(fields);
  }

  /// Deep copy
  PbMessage copy() => PbMessage(fields.toList());

  // --- Getters (last occurrence wins, matching protobuf semantics)

  PbField? _last(int number) {
    for (int i = fields.length - 1; i >= 0; i--) {
      if (fields[i].number == number) return fields[i];
    }
    return null;
  }

  bool has(int number) => _last(number) != null;

  int? getInt(int number) => _last(number)?.intValue;

  bool getBool(int number) => (getInt(number) ?? 0) != 0;

  double? getFloat(int number) {
    final value = getInt(number);
    if (value == null) return null;
    return (ByteData(4)..setUint32(0, value & 0xFFFFFFFF, Endian.little)).getFloat32(0, Endian.little);
  }

  Uint8List? getBytes(int number) => _last(number)?.bytes;

  String? getString(int number) {
    final bytes = getBytes(number);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// Returns null if the field is missing or can't be parsed.
  PbMessage? getMessage(int number) {
    final bytes = getBytes(number);
    if (bytes == null) return null;
    try {
      return PbMessage.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  // --- Setters (replace any existing occurrence, keeping field order)

  void _set(PbField field) {
    final index = fields.indexWhere((e) => e.number == field.number);
    fields.removeWhere((e) => e.number == field.number);
    if (index >= 0 && index <= fields.length) {
      fields.insert(index, field);
    } else {
      fields.add(field);
    }
  }

  void setVarint(int number, int value) => _set(PbField(number, PbWireType.varint, intValue: value));

  void setBool(int number, bool value) => setVarint(number, value ? 1 : 0);

  void setFixed32(int number, int value) =>
      _set(PbField(number, PbWireType.fixed32, intValue: value & 0xFFFFFFFF));

  void setBytes(int number, List<int> value) =>
      _set(PbField(number, PbWireType.lengthDelimited, bytes: Uint8List.fromList(value)));

  void setString(int number, String value) => setBytes(number, utf8.encode(value));

  void setMessage(int number, PbMessage value) => setBytes(number, value.encode());

  void remove(int number) => fields.removeWhere((e) => e.number == number);

  Uint8List encode() {
    final out = BytesBuilder(copy: false);
    for (final field in fields) {
      _writeVarint(out, (field.number << 3) | field.wireType);
      switch (field.wireType) {
        case PbWireType.varint:
          _writeVarint(out, field.intValue!);
          break;
        case PbWireType.fixed64:
          out.add((ByteData(8)..setInt64(0, field.intValue!, Endian.little)).buffer.asUint8List());
          break;
        case PbWireType.lengthDelimited:
          _writeVarint(out, field.bytes!.length);
          out.add(field.bytes!);
          break;
        case PbWireType.fixed32:
          out.add((ByteData(4)..setUint32(0, field.intValue! & 0xFFFFFFFF, Endian.little)).buffer.asUint8List());
          break;
      }
    }
    return out.takeBytes();
  }

  static void _writeVarint(BytesBuilder out, int value) {
    // Negative numbers are written as 10 byte two's complement, per the protobuf spec.
    do {
      int byte = value & 0x7F;
      value = value >>> 7;
      if (value != 0) byte |= 0x80;
      out.addByte(byte);
    } while (value != 0);
  }
}

class _PbReader {
  final List<int> data;
  int pos = 0;

  _PbReader(this.data);

  bool get done => pos >= data.length;

  int _next() {
    if (pos >= data.length) throw const FormatException("Truncated protobuf");
    return data[pos++];
  }

  int readVarint() {
    int result = 0;
    for (int shift = 0; shift < 70; shift += 7) {
      final byte = _next();
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
    }
    throw const FormatException("Varint too long");
  }

  int readFixed32() {
    int result = 0;
    for (int i = 0; i < 4; i++) {
      result |= _next() << (8 * i);
    }
    return result;
  }

  int readFixed64() {
    int result = 0;
    for (int i = 0; i < 8; i++) {
      result |= _next() << (8 * i);
    }
    return result;
  }

  Uint8List readBytes(int length) {
    if (length < 0 || pos + length > data.length) throw const FormatException("Truncated protobuf");
    final bytes = Uint8List.fromList(data.sublist(pos, pos + length));
    pos += length;
    return bytes;
  }
}
