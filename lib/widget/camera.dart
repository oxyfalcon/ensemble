import 'package:camera/camera.dart';
import 'package:ensemble/framework/extensions.dart';
import 'package:ensemble/framework/widget/camera_manager.dart';
import 'package:ensemble/framework/widget/widget.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;

class CameraScreen extends StatefulWidget with Invokable, HasController<MyCameraController, CameraScreenState>{
  static const type = 'Camera';
  CameraScreen({
    Key? key,
  }) : super(key: key);

  final MyCameraController _controller = MyCameraController();

  @override
  State<StatefulWidget> createState() => CameraScreenState();

  @override
  MyCameraController get controller => _controller;

  @override
  Map<String, Function> getters() {
    return {

    };
  }

  @override
  Map<String, Function> methods() {
    return {};
  }

  @override
  Map<String, Function> setters() {
    return {
      'mode': (type) =>
          _controller.mode = CameraMode.values.from(type) ?? CameraMode.both,
      'initialCamera': (type) => _controller.initialCamera =
          InitialCamera.values.from(type) ?? InitialCamera.back,
      'useGallery': (value) => _controller.useGallery =
          Utils.optionalBool(value) ?? _controller.useGallery,
      'maxCount': (value) => _controller.maxCount =
          Utils.optionalInt(value) ?? _controller.maxCount,
      'preview': (value) => _controller.preview =
          Utils.optionalBool(value) ?? _controller.preview,
    };
  }
}

class MyCameraController extends WidgetController{

  CameraController? cameracontroller;

  CameraMode mode = CameraMode.both;
  InitialCamera initialCamera = InitialCamera.back;
  bool useGallery = true;
  int maxCount = 1;
  bool preview = false;
}

class CameraScreenState extends WidgetState<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> cameras = [];
  late PageController pageController;

  var fullImage;

  final ImagePicker imagePicker = ImagePicker();
  List imageFileList = [];

  bool isFrontCamera = false;
  bool isImagePreview = false;
  bool isRecording = false;
  bool isPermission = false;
  String errorString = '';
  int index = 0;

  List cameraoptionsList = [];

  SizedBox space = const SizedBox(
    height: 10,
  );

  Color iconColor = const Color(0xff0086B8);
  double iconSize = 20.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    errorString = 'You just pick at least ${widget._controller.maxCount} image';
    initCamera().then((_) {
      ///initialize camera and choose the back camera as the initial camera in use.
      if (cameras.length >= 2) {
        if (widget._controller.initialCamera == InitialCamera.back) {
          final back = cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back);
          setCamera(cameraDescription: back);
        } else if (widget._controller.initialCamera == InitialCamera.front) {
          final front = cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.front);
          setCamera(cameraDescription: front);
          isFrontCamera = true;
          setState(() {});
        }
      } else {
        setCamera(isNotDefine: true);
      }
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            // Handle access errors here.
            break;
          default:
            // Handle other errors here.
            break;
        }
      }
    });
    pageController = PageController(viewportFraction: 0.25, initialPage: index);
    cameraoptionsList = [
      'PHOTO',
      'VIDEO'
    ];
    setState(() {});
  }

  Future initCamera() async {
    cameras = await availableCameras();
    setState(() {});
  }

  /// chooses the camera to use, where the front camera has index = 1, and the rear camera has index = 0
  void setCamera(
      {bool isNotDefine = false, CameraDescription? cameraDescription}) {
    // in web case if one camera exist than description is not define that why i added isWeb
    if (isNotDefine) {
      widget._controller.cameracontroller =
          CameraController(cameras[0], ResolutionPreset.max);
      widget._controller.cameracontroller!.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });
    } else {
      widget._controller.cameracontroller =
          CameraController(cameraDescription!, ResolutionPreset.max);
      widget._controller.cameracontroller!.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget._controller.cameracontroller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget._controller.cameracontroller!.resumePreview();
      print("State is ${state.toString()}");
    }
    if (state == AppLifecycleState.inactive) {
      widget._controller.cameracontroller!.pausePreview();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget buildWidget(BuildContext context) {
    if (isPermission || cameras.isEmpty) {
      return isImagePreview ? fullImagePreview() : permissionDeniedView();
    }
    if (widget._controller.cameracontroller == null || !widget._controller.cameracontroller!.value.isInitialized) {
      return Container();
    }
    return SafeArea(
      child: WillPopScope(
        onWillPop: () async{
          if(isImagePreview)
            {
              if (widget._controller.cameracontroller == null) {
                setState(() {
                  isImagePreview = false;
                });
              } else {
                setState(() {
                  widget._controller.cameracontroller!.resumePreview();
                  isImagePreview = false;
                });
              }
            }
          else
            {
              Navigator.pop(context, imageFileList);
            }
          return false;
        },
        child: Scaffold(
          body: SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: isImagePreview ? fullImagePreview() : cameraView(),
          ),
        ),
      ),
    );
  }

  Widget cameraView() {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: CameraPreview(
        widget._controller.cameracontroller!,
        child: Column(
          children: [
            imagePreviewButton(),
            const Spacer(),
            // <----- This is Created for Image Preview ------>
            imagesPreview(),
            // <----- This is Created for Camera Button ------>
            cameraButton(),
          ],
        ),
      ),
    );
  }

  //<------ This is Image Preview --------->
  Widget fullImagePreview() {
    return Column(
      children: [
        appbar(
          backArrowAction: () {
            if (widget._controller.cameracontroller == null) {
              setState(() {
                isImagePreview = false;
              });
            } else {
              setState(() {
                widget._controller.cameracontroller!.resumePreview();
                isImagePreview = false;
              });
            }
          },
          deleteButtonAction: () {
            deleteImages();
          },
        ),
        space,
        SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height / 1.4,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height / 1.7,
                  child: Image.memory(
                    fullImage,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: imagesPreview(
                  isImageOnTap: true,
                  isBorderView: true,
                ),
              )
            ],
          ),
        ),
        space,
        textbutton(
          onPressed: () {
            Navigator.pop(context, imageFileList);
          },
          title: 'Done',
        ),
      ],
    );
  }

  // this is permission denied view
  Widget permissionDeniedView() {
    return SizedBox(
      height: 500,
      width: 500,
      child: Column(
        children: [
          imagePreviewButton(),
          const Spacer(),
          const Text(
              'To capture photos and videos, allow access to your camera.'),
          textbutton(
              title: 'Allow access',
              onPressed: () {
                selectImage();
              }),
          const Spacer(),
          imagesPreview(),
          textbutton(
            title: 'Pick from gallery',
            onPressed: () {
              if (widget._controller.useGallery) {
                selectImage();
              } else {
                FlutterToast.showToast(title: 'You have not access of gallery');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget imagesPreview({bool isImageOnTap = false, bool isBorderView = false}) {
    return SizedBox(
      height: 72,
      width: MediaQuery.of(context).size.width,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: imageFileList.length,
        itemBuilder: (c, i) {
          return Padding(
            padding: const EdgeInsets.all(5.0),
            child: GestureDetector(
              onTap: isImageOnTap
                  ? () {
                      setState(() {
                        fullImage = imageFileList[i];
                      });
                    }
                  : null,
              child: Container(
                width: 72.0,
                height: 72.0,
                decoration: BoxDecoration(
                  border: isBorderView
                      ? fullImage == imageFileList[i]
                          ? Border.all(color: iconColor, width: 3.0)
                          : Border.all(color: Colors.transparent, width: 3.0)
                      : Border.all(color: Colors.transparent, width: 3.0),
                  borderRadius: const BorderRadius.all(Radius.circular(5.0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(isBorderView ? const Radius.circular(0.0) : const Radius.circular(5.0)),
                  child: Image.memory(
                    imageFileList[i],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget appbar(
      {required void Function()? backArrowAction,
      required void Function()? deleteButtonAction}) {
    return Padding(
      padding: const EdgeInsets.only(left: 10.0, right: 10.0, top: 10.0),
      child: Row(
        children: [
          buttons(
              onPressed: backArrowAction,
              icon: Icon(
                Icons.arrow_back,
                color: Colors.black,
                size: iconSize,
              ),
              backgroundColor: Colors.white,
              shadowColor: Colors.black54),
          const Spacer(),
          IconButton(
            onPressed: deleteButtonAction,
            icon: Icon(
              Icons.delete_sharp,
              color: iconColor,
              size: iconSize,
            ),
          )
        ],
      ),
    );
  }

  // <----- This Button is used for upload images to sever or firebase ------>
  Widget textbutton(
      {required void Function()? onPressed, required String title}) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        title,
      ),
    );
  }

  // this is a camera button to click image and pick image form gallery and rotate camera
  Widget cameraButton() {
    return Container(
      color: Colors.black.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          children: [
            silderView(),
            space,
            Row(
              children: [
                // <----- This button is used for pick image in gallery ------>
                widget._controller.useGallery
                    ? buttons(
                        icon: Icon(Icons.photo_size_select_actual_outlined,
                            size: iconSize, color: iconColor),
                        backgroundColor: Colors.white.withOpacity(0.3),
                        onPressed: () {
                          if (widget._controller.useGallery) {
                            selectImage();
                          } else {
                            FlutterToast.showToast(
                                title: 'You have not access of gallery');
                          }
                          // showImages(context);
                        },
                      )
                    : const SizedBox(
                        width: 60,
                      ),
                const Spacer(),
                // <----- This button is used for take image ------>
                GestureDetector(
                  onTap: () async {
                    if (imageFileList.length >= widget._controller.maxCount) {
                      FlutterToast.showToast(
                        title: errorString,
                      );
                    } else {
                      if (index == 1) {
                        if (isRecording) {
                          await widget._controller.cameracontroller!
                              .stopVideoRecording();
                          setState(() {
                            isRecording = false;
                          });
                        } else {
                          try {
                            await widget._controller.cameracontroller!
                                .prepareForVideoRecording();
                            await widget._controller.cameracontroller!
                                .startVideoRecording();
                            setState(() {
                              isRecording = true;
                            });
                          } catch (e) {
                            print("Check Recording Error ${e.toString()}");
                          }
                        }
                      } else {
                        widget._controller.cameracontroller!
                            .takePicture()
                            .then((value) async {
                          imageFileList.add(await value.readAsBytes());
                          if (widget._controller.maxCount == 1) {
                            Navigator.pop(context, imageFileList);
                          }
                          setState(() {});
                        });
                      }
                    }
                  },
                  child: Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        height: isRecording ? 25 : 46,
                        width: isRecording ? 25 : 46,
                        decoration: BoxDecoration(
                          color: index == 1 ? const Color(0xffFF453A) : Colors.white.withOpacity(0.5),
                          // shape: isRecording? BoxShape.rectangle : BoxShape.circle,
                          borderRadius: BorderRadius.all(isRecording ? const Radius.circular(5) : const Radius.circular(30)),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // <----- This button is used for rotate camera if camera is exist more than one camera ------>
                cameras.length == 1
                ?
                const SizedBox(
                      width: 60,
                ) :
                buttons(
                    icon: Icon(
                      Icons.flip_camera_ios_outlined,
                      size: iconSize,
                      color: iconColor,
                    ),
                    backgroundColor: Colors.white.withOpacity(0.3),
                    onPressed: () {
                      index = 0;
                      if (isFrontCamera) {
                        final back = cameras.firstWhere(
                          (camera) => camera.lensDirection == CameraLensDirection.back);
                        setCamera(cameraDescription: back);
                        isFrontCamera = false;
                      } else {
                        final front = cameras.firstWhere(
                          (camera) => camera.lensDirection == CameraLensDirection.front);
                        setCamera(cameraDescription: front);
                        isFrontCamera = true;
                      }
                      setState(() {});
                    }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget silderView()
  {
    return SizedBox(
      height: 20,
      child: PageView.builder(
        scrollDirection: Axis.horizontal,
        controller: pageController,
        onPageChanged: (i) {
          setState(() {
            index = i;
          });
          print('Check index $index');
        },
        itemCount: cameraoptionsList.length,
        itemBuilder: ((c, i) {
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: i == index ? 1 : 0.5,
            child: Center(
              child: Text(
                cameraoptionsList[i].toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'Roboto',
                  shadows: [
                    Shadow(
                      blurRadius: 4,
                      color: Colors.black,
                    )
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // this is a next button code for preview selected images
  Widget imagePreviewButton() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          buttons(
            icon: Icon(Icons.close, size: iconSize, color: iconColor),
            backgroundColor: Colors.white.withOpacity(0.3),
            onPressed: () {
              Navigator.pop(context, imageFileList);
            },
          ),
          const Spacer(),
          imageFileList.isNotEmpty
              ? nextButton(
                  buttontitle: widget._controller.preview ? 'Next' : 'Done',
                  imagelength: imageFileList.length.toString(),
                  onTap: () {
                    if (widget._controller.preview) {
                      if (widget._controller.cameracontroller != null) {
                        setState(() {
                          widget._controller.cameracontroller!.pausePreview();
                          isImagePreview = true;
                          fullImage = imageFileList[0];
                        });
                      } else {
                        setState(() {
                          isImagePreview = true;
                          fullImage = imageFileList[0];
                        });
                      }
                    } else {
                      Navigator.pop(context, imageFileList);
                    }
                  },
                )
              : const SizedBox(),
        ],
      ),
    );
  }

  // <----- This is used for preview all images ------>

  Widget nextButton(
      {String? buttontitle, String? imagelength, void Function()? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Text(
            buttontitle!,
            style: TextStyle(
              color: isPermission ? Colors.black : Colors.white,
              fontSize: 18.0,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(
            width: 5.0,
          ),
          Container(
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                color: Colors.white),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  '$imagelength',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  // <----- This is used for camera button i make this for common to reused code ------>

  Widget buttons(
      {required void Function()? onPressed,
      required Widget icon,
      Color? bordercolor,
      Color? backgroundColor,
      Color? shadowColor,
      }) {
    return ButtonTheme(
      height: 40,
      minWidth: 40,
      child: ElevatedButton(
        onPressed: onPressed,
        child: icon,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? Colors.transparent,
          shadowColor: shadowColor ?? Colors.transparent,
          shape: const CircleBorder(),
          side: BorderSide(color: bordercolor ?? Colors.white , width: 2.0),
          padding: const EdgeInsets.all(10),
        ),
      ),
    );
  }

  // this function is used to pick images from gallery
  void selectImage() async {
    final List<XFile> selectImage = await imagePicker.pickMultiImage();
    if (imageFileList.length >= widget._controller.maxCount) {
      FlutterToast.showToast(title: errorString);
      return;
    } else {
      if (selectImage.length > widget._controller.maxCount) {
        FlutterToast.showToast(
            title: 'You just pick ${widget._controller.maxCount} image');
        return;
      } else {
        if (selectImage.isNotEmpty) {
            for (var element in selectImage) {
              imageFileList.add(await element.readAsBytes());
              if(widget._controller.maxCount == 1)
              {
                Navigator.pop(context, imageFileList);
              }
            }
          setState(() {});
        }
      }
    }
  }

  //<------ This code is used for delete image and point next image to preview or delete image ---->

  void deleteImages() {
    int i = imageFileList.indexWhere((element) => element == fullImage);
    if (i == 0) {
      if (imageFileList.length > 1) {
        setState(() {
          imageFileList.removeWhere((element) => element == fullImage);
        });
        for (int j = 0; j < imageFileList.length; j++) {
          setState(() {
            fullImage = imageFileList[i];
          });
        }
      } else {
        setState(() {
          imageFileList.removeWhere((element) => element == fullImage);
          isImagePreview = false;
          if (widget._controller.cameracontroller != null) {
            widget._controller.cameracontroller!.resumePreview();
          }
        });
      }
    } else if (i + 1 == imageFileList.length) {
      if (imageFileList.length > 1) {
        imageFileList.removeWhere((element) => element == fullImage);
        for (int j = 0; j < imageFileList.length; j++) {
          setState(() {
            fullImage = imageFileList[i - 1];
          });
        }
      } else {
        setState(() {
          imageFileList.removeWhere((element) => element == fullImage);
          isImagePreview = false;
          if (widget._controller.cameracontroller != null) {
            widget._controller.cameracontroller!.resumePreview();
          }
        });
      }
    } else {
      imageFileList.removeWhere((element) => element == fullImage);
      for (int j = 0; j < imageFileList.length; j++) {
        setState(() {
          fullImage = imageFileList[i];
        });
      }
    }
  }
}

class FlutterToast {
  static void showToast({
    required String title,
  }) {
    Fluttertoast.showToast(
      msg: title,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
      timeInSecForIosWeb: 1,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }
}