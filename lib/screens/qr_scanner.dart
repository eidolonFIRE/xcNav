import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

// Providers
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';

class QRScanner extends StatefulWidget {
  const QRScanner({super.key});

  @override
  State<QRScanner> createState() => _QRScannerState();
}

class _QRScannerState extends State<QRScanner> with WidgetsBindingObserver {
  MobileScannerController controller = MobileScannerController();
  bool goodResult = false;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final TextEditingController inputGroupId = TextEditingController();
  final groupCodeExp = RegExp(r'^([0-9a-zA-Z]{6,})$');
  static const groupCodePrefix = "xcNav_Group:";

  StreamSubscription<Object?>? _subscription;

  @override
  void initState() {
    super.initState();
    // Start listening to lifecycle changes.
    WidgetsBinding.instance.addObserver(this);

    // Start listening to the barcode events.
    _subscription = controller.barcodes.listen(handleScan);

    // Finally, start the scanner itself.
    unawaited(controller.start());
  }

  @override
  Future<void> dispose() async {
    // Stop listening to lifecycle changes.
    WidgetsBinding.instance.removeObserver(this);
    // Stop listening to the barcode events.
    unawaited(_subscription?.cancel());
    _subscription = null;
    // Dispose the widget itself.
    super.dispose();
    // Finally, dispose of the controller.
    await controller.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the controller is not ready, do not try to start or stop it.
    // Permission dialogs can trigger lifecycle changes before the controller is ready.
    if (!controller.value.hasCameraPermission) {
      return;
    }

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        // Restart the scanner when the app is resumed.
        // Don't forget to resume listening to the barcode events.
        _subscription = controller.barcodes.listen(handleScan);

        unawaited(controller.start());
      case AppLifecycleState.inactive:
        // Stop the scanner when the app is paused.
        // Also stop the barcode events subscription.
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(controller.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: (() => Navigator.popUntil(context, ModalRoute.withName("/home"))),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 20),
              child: SizedBox(
                height: 50,
                child: TextField(
                  // maxLength: 6,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.name,
                  decoration: const InputDecoration(hintText: "Group Code"),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9]"))],
                  controller: inputGroupId,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (text) => {handleCode(text)},
                ),
              ),
            ),
          ),
          IconButton(onPressed: () => {handleCode(inputGroupId.text)}, icon: const Icon(Icons.login))
        ]),
      ),
      body: Column(
        // direction: Axis.vertical,
        // crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  key: qrKey,
                  controller: controller,
                ),
                Positioned(
                    right: 10,
                    bottom: 10,
                    child: IconButton(
                      onPressed: () async {
                        await controller.switchCamera();
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
                            child: QrImageView(
                              eyeStyle: const QrEyeStyle(color: Colors.black),
                              backgroundColor: Colors.white,
                              data: "$groupCodePrefix${Provider.of<Group>(context).currentGroupID!.toUpperCase()}",
                              version: QrVersions.auto,
                              gapless: true,
                              padding: const EdgeInsets.all(60),
                            ),
                          )
                        : const Center(
                            child: SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                    Positioned(
                        bottom: 0,
                        width: MediaQuery.of(context).size.width,
                        child: TextButton.icon(
                          onPressed: () => {
                            Share.share(Provider.of<Group>(context, listen: false).currentGroupID?.toUpperCase() ?? "")
                          },
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

  void handleScan(BarcodeCapture scanned) {
    debugPrint("Scanned Code: $scanned");
    final code = scanned.barcodes[0].toString();
    handleCode(code);
  }

  bool handleCode(String code) {
    if (groupCodeExp.hasMatch(code)) {
      debugPrint("Joined code: $code");

      Provider.of<Client>(context, listen: false).joinGroup(context, code);
      Navigator.pop(context);
      return true;
    } else {
      debugPrint("Invalid code: $code");
      return false;
    }
  }
}
