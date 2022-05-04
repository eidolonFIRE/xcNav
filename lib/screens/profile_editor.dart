import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:image_crop/image_crop.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/widgets/avatar_round.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({Key? key}) : super(key: key);

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  XFile inputFile = XFile("assets/images/default_avatar.png");
  File? croppedImage;
  Uint8List? inputImage;

  final TextEditingController nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final cropKey = GlobalKey<CropState>();

  String? currentName;
  bool isOptional = false;

  @override
  _ProfileEditorState();

  @override
  void initState() {
    super.initState();
    var profile = Provider.of<Profile>(context, listen: false);
    currentName = profile.name;
    isOptional = currentName != null && currentName != "";
    nameController.value = TextEditingValue(text: currentName ?? "");

    // initial image
    if (profile.avatarRaw != null) {
      path_provider.getTemporaryDirectory().then((tempDir) {
        var infile = File(tempDir.path + "/avatar.jpg");
        infile.exists().then((exists) {
          if (exists) {
            infile.readAsBytes().then((value) {
              setState(() {
                inputImage = value;
              });
              refreshCropped();
            });
          } else {
            debugPrint("avatar.jpg wasn't saved");
          }
        });
      });
    }
  }

  void pickGallery() {
    _picker.pickImage(source: ImageSource.gallery).then((value) {
      if (value != null) {
        inputFile = value;
        inputFile.readAsBytes().then((value) {
          setState(() {
            inputImage = value;
          });
          refreshCropped();
        });
      }
    });
  }

  void pickCamera() {
    _picker.pickImage(source: ImageSource.camera).then((value) {
      if (value != null) {
        inputFile = value;
        inputFile.readAsBytes().then((value) {
          setState(() {
            inputImage = value;
          });
          refreshCropped();
        });
      }
    });
  }

  void refreshCropped() {
    // use full crop in none set
    Rect area = const Rect.fromLTWH(0, 0, 1, 1);
    if (cropKey.currentState != null && cropKey.currentState!.area != null) {
      area = cropKey.currentState!.area!;
    }

    // use crop state
    ImageCrop.cropImage(file: File(inputFile.path), area: area).then((value) {
      path_provider.getTemporaryDirectory().then((dir) {
        final targetPath = dir.absolute.path + "/temp_${area.toString()}.jpg";
        FlutterImageCompress.compressAndGetFile(value.absolute.path, targetPath,
                minHeight: 128, minWidth: 128, quality: 90)
            .then((value) => {
                  setState(() {
                    croppedImage = value;
                  })
                });
      });
    });
  }

  void accept(BuildContext contex, bool isOptional) {
    // TODO: validate text correctly
    if (nameController.text.length > 1 && croppedImage != null) {
      croppedImage!.readAsBytes().then((value) {
        Provider.of<Profile>(context, listen: false)
            .updateNameAvatar(nameController.text, value);
        if (isOptional) {
          Navigator.pop(contex);
        } else {
          Navigator.popAndPushNamed(context, "/home");
        }
      });
    }
  }

  Widget _buildCropImage() {
    return Crop(
      image: MemoryImage(inputImage!),
      key: cropKey,
      aspectRatio: 1,
      maximumScale: 10,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: isOptional,
        title: const Text("Edit Profile"),
        actions: [
          IconButton(
            iconSize: 40,
            onPressed: () => accept(context, isOptional),
            icon: const Icon(
              Icons.check,
              color: Colors.lightGreen,
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- Image Cropper Window
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 10, right: 20),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Card(
                    child: Stack(fit: StackFit.expand, children: [
                      inputImage != null
                          ? Listener(
                              child: _buildCropImage(),
                              onPointerUp: (event) => refreshCropped(),
                            )
                          : const Center(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 70),
                                child: Text(
                                  "Set Avatar",
                                  style: TextStyle(fontStyle: FontStyle.italic),
                                ),
                              ),
                            ),
                      // --- buttons
                      Row(
                        mainAxisAlignment: inputImage != null
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        crossAxisAlignment: inputImage != null
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        children: [
                          IconButton(
                              onPressed: pickGallery,
                              icon: const Icon(Icons.collections)),
                          IconButton(
                              onPressed: pickCamera,
                              icon: const Icon(Icons.photo_camera))
                        ]
                            .map((e) => Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: e,
                                ))
                            .toList(),
                      ),
                    ]),
                  ),
                ),
              ),

              // --- Text Input
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 20, top: 4),
                    child: AvatarRound(
                        croppedImage != null
                            ? Image.file(croppedImage!)
                            : Image.asset("assets/images/default_avatar.png"),
                        25),
                  ),
                  Expanded(
                    child: TextField(
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 20),
                      maxLength: 20,
                      autofocus: true,
                      controller: nameController,
                      decoration: const InputDecoration(
                        label: Text("Pilot Name"),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ]),
      ),
    );
  }
}
