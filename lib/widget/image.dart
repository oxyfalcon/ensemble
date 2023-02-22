
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:ensemble/framework/action.dart';
import 'package:ensemble/framework/event.dart';
import 'package:ensemble/framework/widget/widget.dart';
import 'package:ensemble/screen_controller.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble/widget/helpers/controllers.dart';
import 'package:ensemble/widget/helpers/widgets.dart';
import 'package:ensemble/widget/widget_util.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class EnsembleImage extends StatefulWidget with Invokable, HasController<ImageController, ImageState> {
  static const type = 'Image';
  EnsembleImage({Key? key}) : super(key: key);

  final ImageController _controller = ImageController();
  @override
  get controller => _controller;

  @override
  State<StatefulWidget> createState() => ImageState();

  @override
  Map<String, Function> getters() {
    return {};
  }

  @override
  Map<String, Function> methods() {
    return {};
  }

  @override
  Map<String, Function> setters() {
    return {
      'source': (value) => _controller.source = Utils.getString(value, fallback: ''),
      'fit': (value) => _controller.fit = Utils.optionalString(value),
      'placeholderColor': (value) => _controller.placeholderColor = Utils.getColor(value),
      'onTap': (funcDefinition) => _controller.onTap = Utils.getAction(funcDefinition, initiator: this),
      'cache': (value) => _controller.cache = Utils.optionalBool(value) ?? _controller.cache,
    };
  }

}

class ImageController extends BoxController {
  String source = '';
  String? fit;
  Color? placeholderColor;
  EnsembleAction? onTap;
  bool cache=true;
}

class ImageState extends WidgetState<EnsembleImage> {

  @override
  Widget buildWidget(BuildContext context) {

    BoxFit? fit = WidgetUtils.getBoxFit(widget._controller.fit);
    Widget image;
    if (isSvg()) {
      image = buildSvgImage(fit);
    } else {
      image = buildNonSvgImage(fit);
    }

    Widget rtn = BoxWrapper(
        widget: image,
        boxController: widget._controller,
        ignoresMargin: true,      // make sure the gesture don't include the margin
        ignoresDimension: true    // we apply width/height in the image already
    );
    if (widget._controller.onTap != null) {
      rtn = GestureDetector(
        child: rtn,
        onTap: () => ScreenController().executeAction(context, widget._controller.onTap!,event: EnsembleEvent(widget))
      );
    }
    if (widget._controller.margin != null) {
      rtn = Padding(
          padding: widget._controller.margin!,
          child: rtn);
    }
    return rtn;
  }

  Widget buildNonSvgImage(BoxFit? fit) {
    String source = widget._controller.source.trim();
    if (source.isNotEmpty) {
      // if is URL
      if (source.startsWith('https://') || source.startsWith('http://')) {
        // image binding is tricky. When the URL has not been resolved
        // the image will throw exception. We have to use a permanent placeholder
        // until the binding engages
        if (widget._controller.cache) {
          return CachedNetworkImage(
            width: widget._controller.width?.toDouble(),
            height: widget._controller.height?.toDouble(),
            fit: fit,
            errorWidget: (context, error, stacktrace) => errorFallback(),
            placeholder: (context, url) => placeholder(),
            imageUrl: widget.controller.source,
          );
        } else {
          return Image.network(widget._controller.source,
              width: widget._controller.width?.toDouble(),
              height: widget._controller.height?.toDouble(),
              fit: fit,
              errorBuilder: (context, error, stacktrace) => errorFallback(),
              loadingBuilder: (BuildContext context, Widget child,
                  ImageChunkEvent? loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return placeholder();
              });
        }
      }
      // else attempt local asset
      else {
        // user might use env variables to switch between remote and local images.
        // Assets might have additional token e.g. my-image.png?x=2343
        // so we need to strip them out
        return Image.asset(
            Utils.getLocalAssetFullPath(widget._controller.source),
            width: widget._controller.width?.toDouble(),
            height: widget._controller.height?.toDouble(),
            fit: fit,
            errorBuilder: (context, error, stacktrace) => errorFallback());
      }
    }
    return errorFallback();
  }

  Widget buildSvgImage(BoxFit? fit) {
    // if is URL
    if (widget._controller.source.startsWith('https://') || widget._controller.source.startsWith('http://')) {
      return SvgPicture.network(
          widget._controller.source,
          width: widget._controller.width?.toDouble(),
          height: widget._controller.height?.toDouble(),
          fit: fit ?? BoxFit.contain,
          placeholderBuilder: (_) => placeholder()
      );
    }
    // attempt local assets
    return SvgPicture.asset(
        Utils.getLocalAssetFullPath(widget._controller.source),
        width: widget._controller.width?.toDouble(),
        height: widget._controller.height?.toDouble(),
        fit: fit ?? BoxFit.contain,
        placeholderBuilder: (_) => placeholder()
    );
  }

  bool isSvg() {
    return widget._controller.source.endsWith('svg');
  }

  /// display if the image cannot be loaded
  Widget errorFallback() {
    return Image.asset(
      'assets/images/img_placeholder.png',
      package: 'ensemble',
      fit: BoxFit.cover);
  }

  // use modern colors as background placeholder while images are being loaded
  final placeholderColors = [0xffD9E3E5, 0xffBBCBD2, 0xffA79490, 0xffD7BFA8, 0xffEAD9C9, 0xffEEEAE7];
  Widget placeholder() {
    return ColoredBox(
        color: widget._controller.placeholderColor ??
            Color(
                placeholderColors[Random().nextInt(placeholderColors.length)]));
  }




}