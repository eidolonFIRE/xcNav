import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:custom_image_crop/custom_image_crop.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:screenshot/screenshot.dart';

import 'package:xcnav/providers/profile.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({Key? key}) : super(key: key);

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  Color? inputColor;
  Uint8List? inputImage;

  String? avatarErrorText;

  final TextEditingController nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final cropController = CustomImageCropController();
  final cropperFocus = FocusNode();

  String? currentName;
  bool isOptional = false;

  late GlobalKey<FormState> formKey;
  final colorAvatarSS = ScreenshotController();

  bool isProcessing = false;

  @override
  _ProfileEditorState();

  @override
  void initState() {
    super.initState();
    formKey = GlobalKey<FormState>();

    cropperFocus.addListener(() {
      setState(() {});
    });

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
            infile.readAsBytes().then((value) {
              setState(() {
                inputImage = value;
              });
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
      if (value != null) selectImage(value);
    });
  }

  void pickCamera() {
    _picker.pickImage(source: ImageSource.camera).then((value) {
      if (value != null) selectImage(value);
    });
  }

  void pickColor(BuildContext context) {
    showDialog<Color?>(
      context: context,
      builder: (context) {
        HSVColor color = HSVColor.fromAHSV(1, Random().nextDouble(), 1, 1);
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            content: Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: MediaQuery.of(context).size.width / 2 + 20,
                height: MediaQuery.of(context).size.width / 2 + 20,
                child: Stack(
                  // fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                        width: MediaQuery.of(context).size.width / 2,
                        height: MediaQuery.of(context).size.width / 2,
                        child: ColorPickerHueRing(
                          color,
                          (newColor) {
                            setState(() {
                              color = newColor;
                            });
                          },
                          strokeWidth: 40,
                        )),
                    Center(
                      child: Card(
                        color: color.toColor(),
                        child: IconButton(
                            color: Colors.black,
                            iconSize: 40,
                            onPressed: () {
                              Navigator.pop(context, color.toColor());
                            },
                            icon: const Icon(
                              Icons.check,
                              // size: 40,
                            )),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        });
      },
    ).then((selectedColor) {
      if (selectedColor != null) {
        setState(() {
          avatarErrorText = null;
          inputColor = selectedColor;
          inputImage = null;
        });
      }
    });
  }

  void selectImage(XFile file) {
    file.readAsBytes().then((value) {
      setState(() {
        avatarErrorText = null;
        inputImage = value;
        cropController.reset();
      });
    });
  }

  void acceptBytes(BuildContext context, Uint8List bytes) {
    FlutterImageCompress.compressWithList(bytes, minHeight: 128, minWidth: 128, quality: 90).then((compressedImage) {
      Provider.of<Profile>(context, listen: false).updateNameAvatar(nameController.text, compressedImage);
      setState(() {
        isProcessing = false;
      });

      if (isOptional) {
        Navigator.pop(context);
      } else {
        Navigator.popAndPushNamed(context, "/home");
      }
    });
  }

  void accept(BuildContext context, bool isOptional) async {
    if (formKey.currentState?.validate() ?? false) {
      if (inputImage != null) {
        // --- Image avatar
        setState(() {
          isProcessing = true;
        });
        cropController.onCropImage().then((MemoryImage? croppedImage) {
          if (croppedImage != null) {
            acceptBytes(context, croppedImage.bytes);
          } else {
            debugPrint("Error cropping image!");
            setState(() {
              isProcessing = false;
            });
          }
        });
      } else if (inputColor != null) {
        // --- Color avatar
        colorAvatarSS.capture(pixelRatio: 1).then((value) {
          if (value != null) {
            acceptBytes(context, value);
          } else {
            setState(() {
              isProcessing = false;
            });
          }
        });
      } else {
        // --- No avatar set!
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Build /profileEditor");
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: isOptional,
        title: const Text("Edit Profile"),
        actions: [
          isProcessing
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(10.0),
                  child: AspectRatio(aspectRatio: 1, child: CircularProgressIndicator.adaptive()),
                ))
              : IconButton(
                  iconSize: 40,
                  disabledColor: Colors.grey,
                  color: Colors.lightGreen,
                  onPressed: () {
                    if ((formKey.currentState?.validate() ?? false) && (inputImage != null || inputColor != null)) {
                      accept(context, isOptional);
                    } else if (inputImage == null) {
                      setState(() {
                        avatarErrorText = "Required";
                      });
                    }
                  },
                  icon: const Icon(
                    Icons.check,
                    // color: Colors.lightGreen,
                  ),
                )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- Text Input
              Form(
                key: formKey,
                child: TextFormField(
                  controller: nameController,
                  autofocus: isOptional,
                  maxLength: 20,
                  style: Theme.of(context).textTheme.headlineSmall,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9_ ]"))],
                  validator: Profile.nameValidator,
                  decoration: const InputDecoration(
                    label: Text("Display Name *"),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() {
                    formKey.currentState?.validate();
                  }),
                ),
              ),

              // --- Image Cropper Window
              Focus(
                focusNode: cropperFocus,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Listener(
                    onPointerDown: (event) {
                      cropperFocus.requestFocus();
                    },
                    child: InputDecorator(
                      baseStyle: Theme.of(context).textTheme.headlineSmall,
                      isFocused: cropperFocus.hasFocus,
                      decoration: InputDecoration(
                        errorText: avatarErrorText,
                        label: const Text("Avatar *"),
                        border: const OutlineInputBorder(),
                      ),
                      child: ClipRect(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(fit: StackFit.expand, children: [
                            // --- Image cropper
                            if (inputImage != null)
                              CustomImageCrop(
                                  backgroundColor: Colors.grey.shade700,
                                  shape: CustomCropShape.Circle,
                                  cropPercentage: 0.7,
                                  image: MemoryImage(inputImage!),
                                  cropController: cropController),

                            // --- Color preview
                            if (inputColor != null)
                              Center(
                                  child: Screenshot(
                                controller: colorAvatarSS,
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width / 2,
                                  height: MediaQuery.of(context).size.width / 2,
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: inputColor!,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Center(
                                        child: Text(
                                          nameController.value.text.isNotEmpty ? nameController.value.text[0] : "",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.black, fontSize: MediaQuery.of(context).size.width / 3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),

                            // --- buttons
                            if (inputImage == null && inputColor == null)
                              Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(),
                                    ElevatedButton.icon(
                                        label: const Text("Import"),
                                        onPressed: pickGallery,
                                        icon: const Icon(Icons.collections)),
                                    ElevatedButton.icon(
                                        label: const Text("Camera"),
                                        onPressed: pickCamera,
                                        icon: const Icon(Icons.photo_camera)),
                                    ElevatedButton.icon(
                                        label: const Text("Color"),
                                        onPressed: () => pickColor(context),
                                        icon: const Icon(Icons.palette)),
                                    Container(),
                                  ]),

                            // --- Reset avatar button
                            if (inputImage != null || inputColor != null)
                              Align(
                                alignment: Alignment.topRight,
                                child: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        inputImage = null;
                                        inputColor = null;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.delete_forever,
                                      size: 30,
                                    )),
                              )
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            ]),
      ),
    );
  }
}
