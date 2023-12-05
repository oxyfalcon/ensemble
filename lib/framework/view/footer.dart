import 'package:ensemble/framework/widget/has_children.dart';
import 'package:ensemble/framework/widget/widget.dart';
import 'package:ensemble/layout/templated.dart';
import 'package:ensemble/page_model.dart';
import 'package:ensemble/screen_controller.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble/widget/helpers/controllers.dart';
import 'package:ensemble/widget/helpers/widgets.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';
import 'package:flutter/material.dart';
import 'package:ensemble/framework/action.dart' as action;
import 'package:yaml/yaml.dart';
import '../../layout/list_view.dart' as ensemblelistview;
import '../../layout/grid_view.dart' as ensemblegridview;
import '../../layout/box/box_layout.dart' as ensemblecolumn;

class Footer extends StatefulWidget
    with
        UpdatableContainer,
        Invokable,
        HasController<FooterController, _FooterState> {
  Footer({super.key});

  static const String type = "footer";

  @override
  State<Footer> createState() => _FooterState();

  @override
  FooterController get controller => _controller;

  final FooterController _controller = FooterController();

  @override
  Map<String, Function> getters() {
    return {"scrollBehaviour": () => controller.scrollBehavior};
  }

  @override
  Map<String, Function> methods() {
    return {};
  }

  @override
  Map<String, Function> setters() {
    return {
      "children": (value) =>
          _controller.dragableChildrenMap = Utils.getYamlMap(value),
      "dragOptions": (value) => _controller.dragOptions =
          DragOptions.fromYaml(Utils.getYamlMap(value) ?? YamlMap(), this)
    };
  }

  @override
  void initChildren({List<WidgetModel>? children, ItemTemplate? itemTemplate}) {
    _controller.children = children;
  }
}

class _FooterState extends WidgetState<Footer>
    with HasChildren<Footer>, TemplatedWidgetState {
  DragOptions? _dragOptions;
  late DraggableScrollableController _dragController;
  @override
  void initState() {
    super.initState();
    _dragController = widget._controller.dragController;
    _dragOptions = widget.controller.dragOptions;
    if (_dragOptions != null) {
      _dragOptions = widget._controller.dragOptions!;
      _dragController.addListener(
        () {
          if (_dragController.size == _dragOptions?.maxSize &&
              _dragOptions?.onMaxSize != null) {
            ScreenController().executeAction(context, _dragOptions!.onMaxSize!);
          }
          if (_dragController.size == _dragOptions?.minSize &&
              _dragOptions?.onMinSize != null) {
            ScreenController().executeAction(context, _dragOptions!.onMinSize!);
          }
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant Footer oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget._controller.dragController = oldWidget._controller.dragController;
  }

  @override
  void dispose() {
    super.dispose();
    _dragController.dispose();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 250),
      child: (_dragOptions != null &&
              widget.controller.dragOptions!.isDraggable)
          ? DraggableScrollableSheet(
              controller: _dragController,
              initialChildSize: _dragOptions!.initialSize,
              minChildSize: _dragOptions!.minSize,
              maxChildSize: _dragOptions!.maxSize,
              expand: _dragOptions!.expand,
              snap: _dragOptions!.snap,
              snapSizes: _dragOptions!.snapSizes,
              builder:
                  (BuildContext context, ScrollController scrollController) {
                widget.controller.scrollBehavior = scrollController;
                Widget child = (widget.controller.children != null)
                    ? FooterScope(
                        dragOptions: _dragOptions!,
                        scrollController: scrollController,
                        child: buildChildren(widget.controller.children!).first,
                      )
                    : const SizedBox.shrink();
                return BoxWrapper(
                  boxController: widget.controller,
                  widget: child,
                );
              },
            )
          : BoxWrapper(
              boxController: widget.controller,
              widget: (widget.controller.children != null)
                  ? buildChildren(widget.controller.children!).first
                  : const SizedBox.shrink(),
            ),
    );
  }
}

class FooterController extends BoxController {
  YamlMap? dragableChildrenMap;
  List<WidgetModel>? dragableChildren;
  List<WidgetModel>? children;

  ScrollController? scrollBehavior;
  DragOptions? dragOptions;
  DraggableScrollableController dragController =
      DraggableScrollableController();
}

class DragOptions {
  action.EnsembleAction? onMaxSize;
  action.EnsembleAction? onMinSize;
  double maxSize;
  double minSize;
  bool isDraggable; // enable
  double initialSize;
  bool expand;
  bool snap;
  List<double>? snapSizes;

  DragOptions(
      {required this.onMaxSize,
      required this.onMinSize,
      required this.maxSize,
      required this.minSize,
      required this.isDraggable,
      required this.initialSize,
      required this.expand,
      required this.snap,
      required this.snapSizes});

  factory DragOptions.fromYaml(
          YamlMap yamlMap, Invokable invokable) =>
      DragOptions(
          onMaxSize:
              action.EnsembleAction.fromYaml(yamlMap['onMaxSize'],
                  initiator: invokable),
          onMinSize: action.EnsembleAction.fromYaml(yamlMap['onMinSize'],
              initiator: invokable),
          minSize: Utils.getDouble(yamlMap['minSize'], fallback: 0.25),
          maxSize: Utils.getDouble(yamlMap['maxSize'], fallback: 1.0),
          isDraggable: Utils.getBool(yamlMap['enable'], fallback: false),
          initialSize: Utils.getDouble(yamlMap['initialSize'], fallback: 0.5),
          expand: Utils.getBool(yamlMap['expand'], fallback: false),
          snap: Utils.getBool(yamlMap, fallback: false),
          snapSizes: Utils.getList(yamlMap['snapSize']));
}

class FooterScope extends InheritedWidget {
  FooterScope(
      {super.key,
      required super.child,
      this.scrollController,
      this.rootWithinFooterFound = false,
      this.isColumnScrollable = false,
      required this.dragOptions});

  final ScrollController? scrollController;
  final DragOptions dragOptions;
  bool rootWithinFooterFound;
  bool isColumnScrollable;

  static FooterScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FooterScope>();

  bool isRootWithinFooter(BuildContext context) {
    if (rootWithinFooterFound) {
      return false;
    } else {
      if (FooterScope.of(context) != null &&
          FooterScope.of(context)!.dragOptions.isDraggable &&
          context.findAncestorWidgetOfExactType<ensemblecolumn.Column>() ==
              null &&
          context.findAncestorWidgetOfExactType<ensemblegridview.GridView>() ==
              null &&
          context.findAncestorWidgetOfExactType<ensemblelistview.ListView>() ==
              null) {
        rootWithinFooterFound = true;
        return true;
      } else {
        return false;
      }
    }
  }

  bool isColumnScrollableAndRoot(BuildContext context) =>
      context.findAncestorWidgetOfExactType<ensemblecolumn.Column>() != null &&
      isColumnScrollable;

  @override
  bool updateShouldNotify(covariant FooterScope oldWidget) =>
      oldWidget.scrollController == scrollController;
}
