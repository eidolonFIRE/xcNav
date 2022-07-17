import 'dart:developer';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

// Providers
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';

class QRScanner extends StatefulWidget {
  const QRScanner({Key? key}) : super(key: key);

  @override
  State<QRScanner> createState() => _QRScannerState();
}

class _QRScannerState extends State<QRScanner> {
  QRViewController? controller;
  bool goodResult = false;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final TextEditingController inputGroupId = TextEditingController();

  // In order to get hot reload to work we need to pause the camera if the platform
  // is android, or resume the camera if the platform is iOS.
  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 20),
              child: SizedBox(
                height: 50,
                child: TextField(
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.name,
                  decoration: const InputDecoration(hintText: "Group Code"),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9]"))],
                  controller: inputGroupId,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (text) => {joinCode(text)},
                ),
              ),
            ),
          ),
          IconButton(onPressed: () => {joinCode(inputGroupId.text)}, icon: const Icon(Icons.arrow_forward))
        ]),
      ),
      body: Column(
        // direction: Axis.vertical,
        // crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                QRView(
                  key: qrKey,
                  onQRViewCreated: _onQRViewCreated,
                  overlay: QrScannerOverlayShape(
                      borderColor: Colors.red,
                      borderRadius: 10,
                      borderLength: 30,
                      borderWidth: 10,
                      cutOutSize: MediaQuery.of(context).size.width / 2),
                  onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
                ),
                Positioned(
                    right: 10,
                    bottom: 10,
                    child: IconButton(
                      onPressed: () async {
                        await controller?.flipCamera();
                        setState(() {});
                      },
                      iconSize: 30,
                      icon: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                      ),
                    ))
              ],
            ),
          ),
          Expanded(
              child: Container(
                  color: Colors.white,
                  child: Stack(children: [
                    (Provider.of<Group>(context).currentGroupID != null)
                        ? Center(
                            child: QrImage(
                              foregroundColor: Colors.black,
                              backgroundColor: Colors.white,
                              data: Provider.of<Group>(context).currentGroupID!,
                              version: QrVersions.auto,
                              gapless: true,
                              padding: const EdgeInsets.all(60),
                            ),
                          )
                        : const Center(
                            child: SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                    Positioned(
                        bottom: 0,
                        width: MediaQuery.of(context).size.width,
                        child: TextButton.icon(
                          onPressed: () =>
                              {Share.share(Provider.of<Group>(context, listen: false).currentGroupID ?? "")},
                          icon: const Icon(
                            Icons.share,
                            color: Colors.black,
                          ),
                          label: Text(Provider.of<Group>(context).currentGroupID?.toUpperCase() ?? "",
                              style: const TextStyle(color: Colors.black)),
                        )),
                  ]))),
        ],
      ),
    );
  }

  void joinCode(String code) {
    controller!.pauseCamera().then((_) {
      final exp = RegExp(r'([0-9A-Z]{8})');
      if (exp.hasMatch(code)) {
        debugPrint("Joined code: $code");
        Navigator.pop<bool>(context, true);
        Provider.of<Client>(context, listen: false).joinGroup(context, code);
      } else {
        debugPrint("Invalid code: $code");
      }
    });
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      this.controller = controller;
    });
    controller.scannedDataStream.listen((scanData) {
      debugPrint("QR scanner scanData: ${scanData.code}");
      // Follow invite link
      if (scanData.code != null && !goodResult) {
        goodResult = true;
        joinCode(scanData.code!);
      }
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    log('${DateTime.now().toIso8601String()}_onPermissionSet $p');
    if (!p) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('no Permission')),
      );
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
