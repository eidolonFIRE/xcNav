import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  XFile? inputFile;
  File? croppedImage;
  Uint8List? inputImage;
  late Timer updateLoop;

  final TextEditingController nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final cropKey = GlobalKey<CropState>();

  String? currentName;
  bool isOptional = false;

  late GlobalKey<FormState> formKey;

  @override
  _ProfileEditorState();

  @override
  void initState() {
    super.initState();
    formKey = GlobalKey<FormState>();

    var profile = Provider.of<Profile>(context, listen: false);
    currentName = profile.name;
    isOptional = currentName != null && currentName != "";
    nameController.value = TextEditingValue(text: currentName ?? "");

    // initial image
    if (profile.avatarRaw != null) {
      path_provider.getTemporaryDirectory().then((tempDir) {
        var infile = File("${tempDir.path}/avatar.jpg");
        infile.exists().then((exists) {
          if (exists) {
            inputFile = XFile("${tempDir.path}/avatar.jpg");
            infile.readAsBytes().then((value) {
              setState(() {
                inputImage = value;
                refreshCropped();
              });
            });
          } else {
            debugPrint("avatar.jpg wasn't saved");
          }
        });
      });
    }

    // This is a hack to work around the lack of callbacks in the cropper
    updateLoop = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      refreshCropped();
    });
  }

  @override
  void dispose() {
    updateLoop.cancel();
    super.dispose();
    croppedImage?.delete();
  }

  void pickGallery() {
    _picker.pickImage(source: ImageSource.gallery).then((value) {
      if (value != null) selectImage(value);
    });
  }

  void pickCamera() {
    _picker.pickImage(source: ImageSource.camera).then((value) {
      if (value != null) selectImage(value);
    });
  }

  void selectImage(XFile file) {
    inputFile = file;
    inputFile!.readAsBytes().then((value) {
      setState(() {
        inputImage = value;
        refreshCropped();
      });
    });
  }

  void refreshCropped() {
    // use full crop in none set
    if (inputFile == null) return;

    Rect area = const Rect.fromLTWH(0, 0, 1, 1);
    if (cropKey.currentState != null && cropKey.currentState!.area != null) {
      area = cropKey.currentState!.area!;
    }

    debugPrint("${area.width} ${area.height}");

    // use crop state
    ImageCrop.cropImage(file: File(inputFile!.path), area: area).then((value) {
      path_provider.getTemporaryDirectory().then((dir) {
        final targetPath = "${dir.absolute.path}/temp_${area.toString()}.jpg";
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

  void accept(BuildContext context, bool isOptional) {
    if (cropKey.currentState != null) {
      refreshCropped();
    }
    debugPrint("${(formKey.currentState?.validate() ?? false)}");
    if ((formKey.currentState?.validate() ?? false) && croppedImage != null) {
      updateLoop.cancel();
      croppedImage!.readAsBytes().then((value) {
        // (workaround to clear animations)
        Timer(const Duration(seconds: 1), () {
          Provider.of<Profile>(context, listen: false).updateNameAvatar(nameController.text, value);
          if (isOptional) {
            Navigator.pop(context);
          } else {
            Navigator.popAndPushNamed(context, "/home");
          }
        });
      });
    }
  }

  Widget _buildCropImage() {
    return Crop(
      image: MemoryImage(inputImage!),
      key: cropKey,
      aspectRatio: 1,
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
                      child: Form(
                    key: formKey,
                    child: TextFormField(
                      controller: nameController,
                      autofocus: true,
                      maxLength: 20,
                      style: const TextStyle(fontSize: 20),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9_ ]"))],
                      validator: (value) {
                        if (value != null) {
                          if (value.trim().length < 2) return "Must be at least 2 characters.";
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        label: Text("Pilot Name"),
                        border: OutlineInputBorder(),
                      ),
                      // onFieldSubmitted: (value) => formKey.currentState?.validate(),
                    ),
                  )),
                ],
              ),

              // --- Image Cropper Window
              Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height / 3),
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 10, right: 20),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Card(
                      child: Stack(fit: StackFit.expand, children: [
                        inputImage != null
                            ? _buildCropImage()
                            : const Center(
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: 70),
                                  child: Text(
                                    "Set Avatar*",
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                        // --- buttons
                        Row(
                          mainAxisAlignment: inputImage != null ? MainAxisAlignment.start : MainAxisAlignment.center,
                          crossAxisAlignment: inputImage != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                          children: [
                            IconButton(onPressed: pickGallery, icon: const Icon(Icons.collections)),
                            IconButton(onPressed: pickCamera, icon: const Icon(Icons.photo_camera))
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
              ),
            ]),
      ),
    );
  }
}
