import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ADSBhelp extends StatefulWidget {
  const ADSBhelp({super.key});

  @override
  State<ADSBhelp> createState() => _ADSBhelpState();
}

class _ADSBhelpState extends State<ADSBhelp> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("ADSB Info"),
        ),
        body: Container(
          width: MediaQuery.of(context).size.width,
          decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
            Color.fromARGB(255, 0xC9, 0xFF, 0xFF),
            Color.fromARGB(255, 0x52, 0x9E, 0x9E),
            Color.fromARGB(255, 0x1E, 0x3E, 0x4F),
            Color.fromARGB(255, 0x16, 0x16, 0x2E),
            Color.fromARGB(255, 0x0A, 0x0A, 0x14),
          ], stops: [
            0,
            0.27,
            0.58,
            0.83,
            1
          ], begin: Alignment.topLeft, end: Alignment.bottomRight, transform: GradientRotation(0))),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// ---
                Text(
                  "Recommended Device:",
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width / 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: GestureDetector(
                            onTap: () => {launchUrl(Uri.parse("https://uavionix.com/products/pingusb/"))},
                            child: const Text(
                              "pingUSB  by  uAvioni",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18, color: Colors.lightBlue, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                        const Text(
                          "This is a dual-band ADSB receiver that has been tested with xcNav on both iOS/Android.",
                          softWrap: true,
                          maxLines: 10,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width / 3,
                    child: GestureDetector(
                      onTap: () => {launchUrl(Uri.parse("https://uavionix.com/products/pingusb/"))},
                      child: Image.network(
                          "https://mlimxgb6oftt.i.optimole.com/iOeAD64.AtMc~34070/w:672/h:1500/q:mauto/https://uavionix.com/wp-content/uploads/2020/11/pingUSB.png"),
                    ),
                  ),
                ]),

                /// ---
                Text(
                  "FAQ:",
                  style: Theme.of(context).textTheme.headlineMedium,
                ),

                const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Why does it still say \"No Data\"?",
                      textAlign: TextAlign.start,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "\nThe device communicates over a UDP socket. This app won't know for sure the device is connected correctly until the first packet of date is received. If you are in a remote area, it may take a few minutes until an airplane passes nearby.",
                      softWrap: true,
                      maxLines: 10,
                    )
                  ],
                ),
              ],
            ),
          ),
        ));
  }
}
