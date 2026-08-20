// Mock ZK protocol TCP server + test against the real flutter_zkteco client.
// No physical device involved — validates our parsing/wiring assumptions only.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';

const cmdConnect = 1000;
const cmdExit = 1001;
const cmdAckOk = 2000;
const cmdData = 1501;
const cmdFreeData = 1502;
const cmdGetFreeSizes = 50;
const cmdPrepareBuffer = 1503;

Uint8List _topWrap(List<int> header, List<int> payload) {
  final buf = BytesBuilder();
  final top = ByteData(8);
  top.setUint16(0, 20560, Endian.little); // MACHINE_PREPARE_DATA_1
  top.setUint16(2, 32130, Endian.little); // MACHINE_PREPARE_DATA_2
  top.setUint32(4, header.length + payload.length, Endian.little);
  buf.add(top.buffer.asUint8List());
  buf.add(header);
  buf.add(payload);
  return buf.toBytes();
}

List<int> _header(int code, int sessionId, int replyId) {
  final h = ByteData(8);
  h.setUint16(0, code, Endian.little);
  h.setUint16(2, 0, Endian.little); // checksum — client doesn't validate
  h.setUint16(4, sessionId, Endian.little);
  h.setUint16(6, replyId, Endian.little);
  return h.buffer.asUint8List();
}

/// Fakes ONE attendance record (recordSize=8 layout) for uid=7, punch check-in.
Uint8List _fakeAttendancePayload() {
  final rec = ByteData(8);
  rec.setUint16(0, 7, Endian.little); // uid
  rec.setUint8(2, 1); // status (fingerprint)
  rec.setUint32(3, 1723800000, Endian.little); // raw ZK-encoded timestamp
  rec.setUint8(7, 0); // punch type (check-in)

  final sizePrefix = ByteData(4)..setUint32(0, 8, Endian.little); // totalSize
  final buf = BytesBuilder();
  buf.add(sizePrefix.buffer.asUint8List());
  buf.add(rec.buffer.asUint8List());
  return buf.toBytes();
}

/// 80-byte CMD_GET_FREE_SIZES payload: users=0 (skip user sync), records=1.
Uint8List _freeSizesPayload() {
  final fields = List<int>.filled(20, 0);
  fields[4] = 0; // users
  fields[8] = 1; // records
  final bd = ByteData(80);
  for (var i = 0; i < 20; i++) {
    bd.setInt32(i * 4, fields[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

Future<ServerSocket> startMockDevice() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    socket.listen((Uint8List data) {
      if (data.length < 16) return;
      final cmd = ByteData.sublistView(data, 8, 10).getUint16(0, Endian.little);
      final replyId = ByteData.sublistView(data, 14, 16).getUint16(0, Endian.little);

      switch (cmd) {
        case cmdConnect:
          socket.add(_topWrap(_header(cmdAckOk, 1234, replyId), []));
          break;
        case cmdGetFreeSizes:
          socket.add(_topWrap(_header(cmdAckOk, 1234, replyId), _freeSizesPayload()));
          break;
        case cmdPrepareBuffer:
          socket.add(_topWrap(_header(cmdData, 1234, replyId), _fakeAttendancePayload()));
          break;
        case cmdFreeData:
          socket.add(_topWrap(_header(cmdAckOk, 1234, replyId), []));
          break;
        case cmdExit:
          socket.add(_topWrap(_header(cmdAckOk, 1234, replyId), []));
          break;
        default:
          socket.add(_topWrap(_header(cmdAckOk, 1234, replyId), []));
      }
    });
  });
  return server;
}

void main() {
  test('flutter_zkteco connects to a mock device and parses attendance logs', () async {
    final server = await startMockDevice();
    addTearDown(() => server.close());

    final zk = ZKTeco('127.0.0.1', port: server.port, debug: true);

    final connected = await zk.connect(ommitPing: true);
    expect(connected, isTrue, reason: 'connect() should succeed against the mock');

    final logs = await zk.getAttendanceLogs();
    expect(logs, hasLength(1));
    expect(logs.first.id, '7');

    await zk.disconnect();
  });
}
