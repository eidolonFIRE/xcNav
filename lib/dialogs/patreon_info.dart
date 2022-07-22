import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void showPatreonInfoDialog(BuildContext context) {
  showDialog(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text("What is this for?"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Patreons of xcNav receive recognition in this app. To receive the benefit, these fields must match your patreon account exactly.\n\nThis information is hashed before it's sent to the server to be compared with the list of patrons (it remains private to you).",
                  softWrap: true,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ElevatedButton(
                      style: ButtonStyle(
                        side: MaterialStateProperty.resolveWith<BorderSide>(
                            (states) => const BorderSide(color: Colors.white)),
                        backgroundColor: MaterialStateProperty.resolveWith<Color>((states) => Colors.white),
                        // minimumSize: MaterialStateProperty.resolveWith<Size>((states) => const Size(30, 40)),
                        padding:
                            MaterialStateProperty.resolveWith<EdgeInsetsGeometry>((states) => const EdgeInsets.all(20)),
                        shape: MaterialStateProperty.resolveWith<OutlinedBorder>((_) {
                          return RoundedRectangleBorder(borderRadius: BorderRadius.circular(2));
                        }),
                        textStyle: MaterialStateProperty.resolveWith<TextStyle>(
                            (states) => const TextStyle(color: Colors.white, fontSize: 22)),
                      ),
                      onPressed: () => {launchUrl(Uri.parse("https://www.patreon.com/xcnav"))},
                      child: Image.asset(
                        "assets/external/Digital-Patreon-Logo_FieryCoral.png",
                        width: MediaQuery.of(context).size.width / 10,
                      )),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                  icon: const Icon(
                    Icons.check,
                    color: Colors.lightGreen,
                  ),
                  onPressed: () => {Navigator.pop(context)},
                  label: const Text("Ok"))
            ],
          ));
}
