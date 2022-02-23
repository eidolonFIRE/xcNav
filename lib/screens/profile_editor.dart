import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:image_crop/image_crop.dart';

import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/widgets/avatar_round.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({Key? key}) : super(key: key);

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  XFile imageFile = XFile("assets/images/default_avatar.png");
  File? croppedImage;
  Uint8List? imageRaw;

  final TextEditingController nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final cropKey = GlobalKey<CropState>();

  @override
  _ProfileEditorState();

  pickGallery() {
    _picker.pickImage(source: ImageSource.gallery).then((value) {
      if (value != null) {
        imageFile = value;
        imageFile.readAsBytes().then((value) {
          setState(() {
            imageRaw = value;
          });
        });
      }
    });
  }

  pickCamera() {
    _picker.pickImage(source: ImageSource.camera).then((value) {
      if (value != null) {
        imageFile = value;
        imageFile.readAsBytes().then((value) {
          setState(() {
            imageRaw = value;
          });
        });
      }
    });
  }

  refreshCropped() {
    if (cropKey.currentState != null) {
      ImageCrop.cropImage(
              file: File(imageFile.path), area: cropKey.currentState!.area!)
          .then((value) {
        setState(() {
          croppedImage = value;
        });
      });
    }
  }

  accept(BuildContext context) {
    // TODO: validate text correctly
    if (nameController.text.length > 1 && croppedImage != null) {
      croppedImage!.readAsBytes().then((value) {
        Provider.of<Profile>(context, listen: false)
            .updateNameAvatar(nameController.text, value);
        Navigator.popAndPushNamed(context, "/home");
      });
    }
  }

  Widget _buildCropImage() {
    return Crop(
      image: MemoryImage(imageRaw!),
      key: cropKey,
      aspectRatio: 1,
      maximumScale: 10,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        child: SafeArea(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- Image Cropper Window
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: AspectRatio(
                aspectRatio: 1,
                child: Card(
                  child: Stack(children: [
                    imageRaw != null
                        ? Listener(
                            child: _buildCropImage(),
                            onPointerUp: (event) => refreshCropped(),
                          )
                        : Container(),
                    // --- buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                            onPressed: pickGallery,
                            icon: const Icon(Icons.collections)),
                        IconButton(
                            onPressed: pickCamera,
                            icon: const Icon(Icons.photo_camera))
                      ],
                    ),
                  ]),
                ),
              ),
            ),

            // --- Text Input
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: AvatarRound(
                        croppedImage != null
                            ? Image.file(croppedImage!)
                            : Image.asset("assets/images/default_avatar.png"),
                        25),
                  ),
                  Expanded(
                    child: TextField(
                      style: TextStyle(fontSize: 20),
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
            ),
            ElevatedButton.icon(
                onPressed: () => accept(context),
                // onPressed: () => {},
                icon: const Icon(
                  Icons.check,
                  size: 24,
                  color: Colors.lightGreen,
                ),
                label: const Text("Continue")),
          ]),
    ));
  }
}
