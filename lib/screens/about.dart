import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

class About extends StatefulWidget {
  const About({Key? key}) : super(key: key);

  @override
  State<About> createState() => _AboutState();
}

class _AboutState extends State<About> with SingleTickerProviderStateMixin {
  final TextStyle contributerStyle = const TextStyle(fontSize: 18);

  late final Animation<Color?> animation;

  final paleColor = const Color.fromARGB(20, 255, 255, 255);

  final ButtonStyle externalBtn = ButtonStyle(
    side: MaterialStateProperty.resolveWith<BorderSide>((states) => const BorderSide(color: Colors.white)),
    backgroundColor: MaterialStateProperty.resolveWith<Color>((states) => Colors.white),
    // minimumSize: MaterialStateProperty.resolveWith<Size>((states) => const Size(30, 40)),
    padding: MaterialStateProperty.resolveWith<EdgeInsetsGeometry>((states) => const EdgeInsets.all(20)),
    shape: MaterialStateProperty.resolveWith<OutlinedBorder>((_) {
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
    }),
    textStyle:
        MaterialStateProperty.resolveWith<TextStyle>((states) => const TextStyle(color: Colors.white, fontSize: 22)),
  );

  @override
  _AboutState();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("About"),
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
            padding: const EdgeInsets.only(top: 50, bottom: 50),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                /// --- Header Img
                SvgPicture.asset(
                  "assets/images/xcnav.logo.type.svg",
                  width: MediaQuery.of(context).size.width / 5,
                  // height: MediaQuery.of(context).size.width / 4,
                ),

                SizedBox(
                  width: MediaQuery.of(context).size.width / 1.5,
                  child: const Text(
                    "This project was started by Caleb Johnson with the goal of to put all the tools for coordinating a group, cross-country flight into one app. This app is free and open source. We rely on your contributions to keep it alive.",
                    textAlign: TextAlign.center,
                  ),
                ),

                /// --- Links to external resources
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Give Back",
                      style: TextStyle(fontSize: 24),
                    ),
                    SizedBox(
                        width: MediaQuery.of(context).size.width / 2,
                        child: const Divider(
                          color: Colors.white,
                        )),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Container(),
                        SizedBox(
                          width: MediaQuery.of(context).size.width / 5,
                          height: MediaQuery.of(context).size.width / 5,
                          child: ElevatedButton(
                              style: externalBtn,
                              onPressed: () => {launchUrl(Uri.parse("https://www.patreon.com/xcnav"))},
                              child: Image.asset(
                                "assets/external/Digital-Patreon-Logo_FieryCoral.png",
                                width: MediaQuery.of(context).size.width / 10,
                              )),
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width / 5,
                          height: MediaQuery.of(context).size.width / 5,
                          child: ElevatedButton(
                              style: externalBtn,
                              onPressed: () => {launchUrl(Uri.parse("https://github.com/eidolonFIRE/xcNav"))},
                              child: Image.asset("assets/external/GitHub-Mark-120px-plus.png",
                                  width: MediaQuery.of(context).size.width / 10)),
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width / 5,
                          height: MediaQuery.of(context).size.width / 5,
                          child: ElevatedButton(
                              style: externalBtn,
                              onPressed: () => {launchUrl(Uri.parse("https://discord.gg/Fwv8Sz4HJN"))},
                              child: SvgPicture.asset(
                                "assets/external/icon_clyde_white_RGB.svg",
                              )),
                        ),
                        Container()
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ));
  }
}
