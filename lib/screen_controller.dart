// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:isolate';
import 'dart:math' show Random;
import 'dart:ui';

import 'package:app_settings/app_settings.dart';
import 'package:ensemble/action/InvokeAPIController.dart';
import 'package:ensemble/ensemble.dart';
import 'package:ensemble/ensemble_app.dart';
import 'package:ensemble/framework/action.dart';
import 'package:ensemble/framework/bindings.dart';
import 'package:ensemble/framework/data_context.dart';
import 'package:ensemble/framework/device.dart';
import 'package:ensemble/framework/error_handling.dart';
import 'package:ensemble/framework/event.dart';
import 'package:ensemble/framework/permissions_manager.dart';
import 'package:ensemble/framework/stub/camera_manager.dart';
import 'package:ensemble/framework/stub/contacts_manager.dart';
import 'package:ensemble/framework/stub/file_manager.dart';
import 'package:ensemble/framework/scope.dart';
import 'package:ensemble/framework/stub/plaid_link_manager.dart';
import 'package:ensemble/framework/view/page.dart' as ensemble;
import 'package:ensemble/framework/theme/theme_loader.dart';
import 'package:ensemble/framework/view/page_group.dart';
import 'package:ensemble/framework/widget/modal_screen.dart';
import 'package:ensemble/framework/widget/screen.dart';
import 'package:ensemble/framework/widget/toast.dart';
import 'package:ensemble/layout/ensemble_page_route.dart';
import 'package:ensemble/page_model.dart';
import 'package:ensemble/util/extensions.dart';
import 'package:ensemble/util/http_utils.dart';
import 'package:ensemble/util/notification_utils.dart';
import 'package:ensemble/util/upload_utils.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble/widget/widget_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:workmanager/workmanager.dart';
import 'package:yaml/yaml.dart';
import 'package:get_it/get_it.dart';

import 'framework/widget/wallet_connect_modal.dart';

/// Singleton that holds the page model definition
/// and operations for the current screen
class ScreenController {
  final WidgetRegistry registry = WidgetRegistry.instance;

  // Singleton
  static final ScreenController _instance = ScreenController._internal();
  ScreenController._internal();
  factory ScreenController() {
    return _instance;
  }

  /// get the ScopeManager given the context
  ScopeManager? getScopeManager(BuildContext context) {
    // get the current scope of the widget that invoked this. It gives us
    // the data context to evaluate expression
    ScopeManager? scopeManager = ensemble.DataScopeWidget.getScope(context);

    // when context is at the root View, we can't reach the DataScopeWidget which is
    // actually a child of View. Let's just get the scopeManager directly.
    // TODO: find a better more consistent way of getting ScopeManager
    if (scopeManager == null && context.widget is ensemble.Page) {
      scopeManager = (context.widget as ensemble.Page).rootScopeManager;
    }

    // If we still can't find a ScopeManager, look into the PageGroupWidget
    // which extends the DataScopeWidget. We have to do this again since
    // Unfortunately look up only works by exact type (and not inherited type)
    scopeManager ??= PageGroupWidget.getScope(context);

    return scopeManager;
  }

  /// handle Action e.g invokeAPI
  Future<void> executeAction(BuildContext context, EnsembleAction action,
      {EnsembleEvent? event}) {
    ScopeManager? scopeManager = getScopeManager(context);
    if (scopeManager != null) {
      return executeActionWithScope(context, scopeManager, action, event: event);
    } else {
      throw Exception('Cannot find ScopeManager to execute action');
    }
  }

  Future<void> executeActionWithScope(
      BuildContext context, ScopeManager scopeManager, EnsembleAction action,
      {EnsembleEvent? event}) {
    return nowExecuteAction(context, scopeManager.dataContext, action,
        scopeManager.pageData.apiMap, scopeManager,
        event: event);
  }

  /// internally execute an Action
  Future<void> nowExecuteAction(
      BuildContext context,
      DataContext providedDataContext,
      EnsembleAction action,
      Map<String, YamlMap>? apiMap,
      ScopeManager? scopeManager,
      {EnsembleEvent? event}) async {
    /// Actions are short-live so we don't need a childScope, simply create a localized context from the given context
    /// Note that scopeManager may starts out without Invokable IDs (as widgets may yet to render), but at the time
    /// of API returns, they will be populated. For this reason, always rebuild data context from scope manager.
    /// For now we are OK as we don't send off the API until the screen has rendered.
    DataContext dataContext =
        providedDataContext.clone(newBuildContext: context);
    /*DataContext dataContext;
    if (scopeManager != null) {
      // start with data context from scope manager but overwrite with provided data context
      dataContext = scopeManager.dataContext.clone(newBuildContext: context);
      dataContext.copy(providedDataContext, replaced: true);
    } else {
      dataContext = providedDataContext.clone(newBuildContext: context);
    }*/

    // scope the initiator to *this* variable
    if (action.initiator != null) {
      dataContext.addInvokableContext('this', action.initiator!);
    }
    if (event != null) {
      dataContext.addInvokableContext('event', event);
    }

    if (action is InvokeAPIAction) {
      InvokeAPIController()
          .execute(action, context, dataContext, scopeManager, apiMap);
    } else if (action is BaseNavigateScreenAction) {
      // process input parameters
      Map<String, dynamic>? nextArgs = {};
      action.inputs?.forEach((key, value) {
        nextArgs[key] = dataContext.eval(value);
      });

      RouteOption? routeOption;
      if (action is NavigateScreenAction) {
        if (action.options?['clearAllScreens'] == true) {
          routeOption = RouteOption.clearAllScreens;
        } else if (action.options?['replaceCurrentScreen'] == true) {
          routeOption = RouteOption.replaceCurrentScreen;
        }
      }

      PageRouteBuilder routeBuilder = navigateToScreen(
          providedDataContext.buildContext,
          screenName: dataContext.eval(action.screenName),
          asModal: action.asModal,
          routeOption: routeOption,
          pageArgs: nextArgs,
          transition: action.transition);

      // listen for data returned on popped
      if (scopeManager == null) {
        return;
      }
      if (action is NavigateScreenAction && action.onNavigateBack != null) {
        routeBuilder.popped.then((data) => executeActionWithScope(
            context, scopeManager, action.onNavigateBack!,
            event: EnsembleEvent(null, data: data)));
      } else if (action is NavigateModalScreenAction &&
          action.onModalDismiss != null &&
          routeBuilder.fullscreenDialog) {
        // callback on modal pop
        routeBuilder.popped.whenComplete(() {
          executeActionWithScope(context, scopeManager, action.onModalDismiss!);
        });
      }
    } else if (action is ShowBottomModalAction) {
      Widget? widget;
      if (scopeManager != null && action.widget != null) {
        widget = scopeManager.buildWidgetFromDefinition(action.widget);
      }

      if (widget != null) {
        showModalBottomSheet(
          context: context,
          backgroundColor: action.backgroundColor(dataContext),
          barrierColor: action.barrierColor(dataContext),
          isScrollControlled: true,
          enableDrag: action.enableDrag(dataContext),
          showDragHandle: action.enableDragHandler(dataContext),
          builder: (context) {
            return widget!;
          },
        );
      }
    } else if (action is PlaidLinkAction) {
      final linkToken = action.getLinkToken(dataContext).trim();
      if (linkToken.isNotEmpty) {
        GetIt.I<PlaidLinkManager>().openPlaidLink(
          linkToken,
          (linkSuccess) {
            if (action.onSuccess != null) {
              executeActionWithScope(
                context,
                scopeManager!,
                action.onSuccess!,
                event: EnsembleEvent(
                  action.initiator!,
                  data: linkSuccess,
                ),
              );
            }
          },
          (linkEvent) {
            if (action.onEvent != null) {
              executeActionWithScope(
                context,
                scopeManager!,
                action.onEvent!,
                event: EnsembleEvent(
                  action.initiator!,
                  data: linkEvent,
                ),
              );
            }
          },
          (linkExit) {
            if (action.onExit != null) {
              executeActionWithScope(
                context,
                scopeManager!,
                action.onExit!,
                event: EnsembleEvent(
                  action.initiator!,
                  data: linkExit,
                ),
              );
            }
          },
        );
      } else {
        throw RuntimeError(
            "openPlaidLink action requires the plaid's link_token.");
      }
    } else if (action is AppSettingAction) {
      final settingType = action.getTarget(dataContext);
      AppSettings.openAppSettings(type: settingType);
    } else if (action is PhoneContactAction) {
      GetIt.I<ContactManager>().getPhoneContacts((contacts) {
        if (action.getOnSuccess(dataContext) != null) {
          final contactsData =
              contacts.map((contact) => contact.toJson()).toList();

          executeActionWithScope(
            context,
            scopeManager!,
            action.getOnSuccess(dataContext)!,
            event: EnsembleEvent(
              action.initiator,
              data: {'contacts': contactsData},
            ),
          );
        }
      }, (error) {
        if (action.getOnError(dataContext) != null) {
          executeActionWithScope(
            context,
            scopeManager!,
            action.getOnError(dataContext)!,
            event: EnsembleEvent(action.initiator!, data: {'error': error}),
          );
        }
      });
    } else if (action is ShowCameraAction) {
      GetIt.I<CameraManager>().openCamera(context, action, scopeManager);
    } else if (action is ShowDialogAction) {
      if (scopeManager != null) {
        Widget widget = scopeManager.buildWidgetFromDefinition(action.widget);

        // get styles. TODO: make bindable
        Map<String, dynamic> dialogStyles = {};
        action.options?.forEach((key, value) {
          dialogStyles[key] = dataContext.eval(value);
        });

        bool useDefaultStyle = dialogStyles['style'] != 'none';
        BuildContext? dialogContext;

        showGeneralDialog(
            useRootNavigator:
                false, // use inner-most MaterialApp (our App) as root so theming is ours
            context: context,
            barrierDismissible: true,
            barrierLabel: "Barrier",
            barrierColor: Colors
                .black54, // this has some transparency so the bottom shown through

            pageBuilder: (context, animation, secondaryAnimation) {
              // save a reference to the builder's context so we can close it programmatically
              dialogContext = context;
              scopeManager.openedDialogs.add(dialogContext!);

              return Align(
                  alignment: Alignment(
                      Utils.getDouble(dialogStyles['horizontalOffset'],
                          min: -1, max: 1, fallback: 0),
                      Utils.getDouble(dialogStyles['verticalOffset'],
                          min: -1, max: 1, fallback: 0)),
                  child: Material(
                      color: Colors.transparent,
                      child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minWidth: Utils.getDouble(
                                  dialogStyles['minWidth'],
                                  fallback: 0),
                              maxWidth: Utils.getDouble(
                                  dialogStyles['maxWidth'],
                                  fallback: double.infinity),
                              minHeight: Utils.getDouble(
                                  dialogStyles['minHeight'],
                                  fallback: 0),
                              maxHeight: Utils.getDouble(
                                  dialogStyles['maxHeight'],
                                  fallback: double.infinity)),
                          child: Container(
                              decoration: useDefaultStyle
                                  ? const BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(5)),
                                      boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: Colors.white38,
                                            blurRadius: 5,
                                            offset: Offset(0, 0),
                                          )
                                        ])
                                  : null,
                              margin: useDefaultStyle
                                  ? const EdgeInsets.all(20)
                                  : null,
                              padding: useDefaultStyle
                                  ? const EdgeInsets.all(20)
                                  : null,
                              child: SingleChildScrollView(
                                child: widget,
                              )))));
            }).then((value) {
          // remove the dialog context since we are closing them
          scopeManager.openedDialogs.remove(dialogContext);

          // callback when dialog is dismissed
          if (action.onDialogDismiss != null) {
            executeActionWithScope(
                context, scopeManager, action.onDialogDismiss!);
          }
        });
      }
    } else if (action is CloseAllDialogsAction) {
      if (scopeManager != null) {
        for (var dialogContext in scopeManager.openedDialogs) {
          Navigator.pop(dialogContext);
        }
        scopeManager.openedDialogs.clear();
      }
    } else if (action is StartTimerAction) {
      // what happened if ScopeManager is null?
      if (scopeManager != null) {
        // validate
        bool isRepeat = action.isRepeat(dataContext);
        int? repeatInterval = action.getRepeatInterval(dataContext);
        if (isRepeat && repeatInterval == null) {
          throw LanguageError(
              "${ActionType.startTimer.name}'s repeatInterval needs a value when repeat is on");
        }

        int delay = action.getStartAfter(dataContext) ??
            (isRepeat ? repeatInterval! : 0);

        // we always execute at least once, delayed by startAfter and fallback to repeatInterval (or immediate if startAfter is 0)
        Timer(Duration(seconds: delay), () {
          // execute the action
          executeActionWithScope(context, scopeManager, action.onTimer);

          // if no repeat, execute onTimerComplete
          if (!isRepeat) {
            if (action.onTimerComplete != null) {
              executeActionWithScope(
                  context, scopeManager, action.onTimerComplete!);
            }
          }
          // else repeating timer
          else if (repeatInterval != null) {
            int? maxTimes = action.getMaxTimes(dataContext);

            /// repeatCount value of null means forever by default
            int? repeatCount = maxTimes != null ? maxTimes - 1 : null;
            if (repeatCount != 0) {
              int counter = 0;
              final timer =
                  Timer.periodic(Duration(seconds: repeatInterval), (timer) {
                // execute the action
                executeActionWithScope(context, scopeManager, action.onTimer);

                // automatically cancel timer when repeatCount is reached
                if (repeatCount != null && ++counter == repeatCount) {
                  timer.cancel();

                  // timer terminates, call onTimerComplete
                  if (action.onTimerComplete != null) {
                    executeActionWithScope(
                        context, scopeManager, action.onTimerComplete!);
                  }
                }
              });

              // save our timer to our PageData since user may want to cancel at anytime
              // and also when we navigate away from the page
              scopeManager.addTimer(action, timer);
            }
          }
        });
      }
    } else if (action is StopTimerAction) {
      if (scopeManager != null) {
        try {
          scopeManager.removeTimer(action.id);
        } catch (e) {
          debugPrint(
              'error when trying to stop timer with name ${action.id}. Error: ${e.toString()}');
        }
      }
    } else if (action is GetLocationAction) {
      executeGetLocationAction(scopeManager!, dataContext, context, action);
    } else if (action is ExecuteCodeAction) {
      action.inputs?.forEach((key, value) {
        dynamic val = dataContext.eval(value);
        if (val != null) {
          dataContext.addDataContextById(key, val);
        }
      });
      dataContext.evalCode(action.codeBlock, action.codeBlockSpan);

      if (action.onComplete != null && scopeManager != null) {
        executeActionWithScope(context, scopeManager, action.onComplete!);
      }
    } else if (action is ShowToastAction) {
      Widget? customToastBody;
      if (scopeManager != null && action.widget != null) {
        customToastBody = scopeManager.buildWidgetFromDefinition(action.widget);
      }
      ToastController().showToast(context, action, customToastBody, dataContext: dataContext);
    } else if (action is OpenUrlAction) {
      dynamic value = dataContext.eval(action.url);
      value ??= '';
      launchUrl(Uri.parse(value),
          mode: (action.openInExternalApp)
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault);
    } else if (action is FileUploadAction) {
      await uploadFiles(
          action: action,
          context: context,
          dataContext: dataContext,
          apiMap: apiMap,
          scopeManager: scopeManager);
    } else if (action is FilePickerAction) {
      GetIt.I<FileManager>().pickFiles(context, action, scopeManager);
    } else if (action is NavigateBack) {
      if (scopeManager != null) {
        Navigator.of(context).maybePop(action.getData(dataContext));
      }
    } else if (action is CopyToClipboardAction) {
      if (action.value != null) {
        String? clipboardValue = action.getValue(dataContext);
        if (clipboardValue != null) {
          Clipboard.setData(ClipboardData(text: clipboardValue)).then((value) {
            if (action.onSuccess != null) {
              executeAction(context, action.onSuccess!);
            }
          }).catchError((_) {
            if (action.onFailure != null) {
              executeAction(context, action.onFailure!);
            }
          });
        }
      } else {
        if (action.onFailure != null) executeAction(context, action.onFailure!);
      }
    } else if (action is WalletConnectAction) {
      //  TODO store session:  WalletConnectSession? session = await sessionStorage.getSession();

      BuildContext? dialogContext;

      final WalletConnect walletConnect = WalletConnect(
        bridge: 'https://bridge.walletconnect.org',
        clientMeta: PeerMeta(
          name: action.appName,
          description: action.appDescription,
          url: action.appUrl,
          icons:
              action.appIconUrl != null ? <String>[action.appIconUrl!] : null,
        ),
      );

      if (action.id != null && scopeManager != null) {
        scopeManager.dataContext
            .addDataContextById(action.id!, WalletData(walletConnect));
      }

      if (walletConnect.connected) {
        // TODO works when session is stored
        return;
      }

      walletConnect.on('connect', (SessionStatus? session) {
        if (dialogContext != null) {
          Navigator.pop(dialogContext!);
        }
        updateWalletData(action, scopeManager, context);
      });
      walletConnect.on('session_update', (Object? session) {
        if (dialogContext != null) {
          Navigator.pop(dialogContext!);
        }
        updateWalletData(action, scopeManager, context);
      });
      walletConnect.on('disconnect', (Object? session) {
        updateWalletData(action, scopeManager, context);
      });

      try {
        walletConnect.createSession(onDisplayUri: (String uri) async {
          if (kIsWeb) {
            showDialog(
              context: context,
              builder: (context) {
                dialogContext = context;
                return WalletConnectModal(qrData: uri);
              },
            );
            return;
          }
          launchUrlString(uri, mode: LaunchMode.externalApplication);
        });
      } on Exception catch (_) {
        if (action.onError != null) executeAction(context, action.onError!);
        throw LanguageError('Unable to create wallet connect session');
      }
    } else if (action is NotificationAction) {
      notificationUtils.context = context;
      notificationUtils.onRemoteNotification = action.onReceive;
      notificationUtils.onRemoteNotificationOpened = action.onTap;
    } else if (action is ShowNotificationAction) {
      dataContext.addDataContext(Ensemble.externalDataContext);
      notificationUtils.showNotification(
        dataContext.eval(action.title),
        dataContext.eval(action.body),
      );
    } else if (action is RequestNotificationAction) {
      final isEnabled = await notificationUtils.initNotifications() ?? false;

      if (isEnabled && action.onAccept != null) {
        executeAction(context, action.onAccept!);
      }

      if (!isEnabled && action.onReject != null) {
        executeAction(context, action.onReject!);
      }
    } else if (action is AuthorizeOAuthAction) {
      // TODO
    } else if (action is CheckPermission) {
      Permission? type = action.getType(dataContext);
      if (type == null) {
        throw RuntimeError('checkPermission requires a type.');
      }
      bool? result = await PermissionsManager().hasPermission(type);
      if (result == true) {
        if (action.onAuthorized != null) {
          executeAction(context, action.onAuthorized!);
        }
      } else if (result == false) {
        if (action.onDenied != null) {
          executeAction(context, action.onDenied!);
        }
      } else {
        if (action.onNotDetermined != null) {
          executeAction(context, action.onNotDetermined!);
        }
      }
    }
  }

  void updateWalletData(WalletConnectAction action, ScopeManager? scopeManager,
      BuildContext context) {
    if (action.id != null && scopeManager != null) {
      final walletData = scopeManager.dataContext.getContextById(action.id!);
      scopeManager.dispatch(
          ModelChangeEvent(SimpleBindingSource(action.id!), walletData));
      if (action.onComplete != null) executeAction(context, action.onComplete!);
    }
  }

  /// executing a code block
  /// also scope the Initiator to *this* variable
  /*void executeCodeBlock(DataContext dataContext, Invokable initiator, String codeBlock) {
    // scope the initiator to *this* variable
    DataContext localizedContext = dataContext.clone();
    localizedContext.addInvokableContext('this', initiator);
    localizedContext.evalCode(codeBlock);
  }*/

  Future<void> uploadFiles({
    required BuildContext context,
    required FileUploadAction action,
    required DataContext dataContext,
    ScopeManager? scopeManager,
    Map<String, YamlMap>? apiMap,
  }) async {
    List<File>? selectedFiles;

    final rawFiles = _getRawFiles(action.files, dataContext);

    if (rawFiles is! List<dynamic>) {
      if (action.onError != null) executeAction(context, action.onError!);
      return;
    }

    selectedFiles =
        rawFiles.map((data) => File.fromJson(data)).toList().cast<File>();

    if (isFileSizeOverLimit(context, dataContext, selectedFiles, action)) {
      if (action.onError != null) executeAction(context, action.onError!);
      return;
    }

    if (action.id != null && scopeManager != null) {
      final uploadFilesResponse =
          scopeManager.dataContext.getContextById(action.id!);
      scopeManager.dataContext.addInvokableContext(
          action.id!,
          (uploadFilesResponse is UploadFilesResponse)
              ? uploadFilesResponse
              : UploadFilesResponse());
    }

    final apiDefinition = apiMap?[action.uploadApi];
    if (apiDefinition == null) {
      throw LanguageError(
          'Unable to find api definition for ${action.uploadApi}');
    }

    if (apiDefinition['inputs'] is YamlList && action.inputs != null) {
      for (var input in apiDefinition['inputs']) {
        final value = dataContext.eval(action.inputs![input]);
        if (value != null) {
          dataContext.addDataContextById(input, value);
        }
      }
    }

    Map<String, String> headers = {};
    if (apiDefinition['headers'] is YamlMap) {
      (apiDefinition['headers'] as YamlMap).forEach((key, value) {
        if (value != null) {
          headers[key.toString()] = dataContext.eval(value).toString();
        }
      });
    }

    Map<String, String> fields = {};
    if (apiDefinition['body'] is YamlMap) {
      (apiDefinition['body'] as YamlMap).forEach((key, value) {
        if (value != null) {
          fields[key.toString()] = dataContext.eval(value).toString();
        }
      });
    }

    String url = HttpUtils.resolveUrl(
        dataContext, apiDefinition['uri'].toString().trim());
    String method = apiDefinition['method']?.toString().toUpperCase() ?? 'POST';
    final fileResponse = action.id == null
        ? null
        : scopeManager?.dataContext.getContextById(action.id!)
            as UploadFilesResponse;

    if (action.isBackgroundTask) {
      if (kIsWeb) {
        throw LanguageError('Background Upload is not supported on web');
      }
      await _setBackgroundUploadTask(
        context: context,
        action: action,
        selectedFiles: selectedFiles,
        headers: headers,
        fields: fields,
        method: method,
        url: url,
        fileResponse: fileResponse,
        scopeManager: scopeManager,
      );

      return;
    }
    final taskId = generateRandomId(8);
    fileResponse?.addTask(UploadTask(id: taskId));

    final response = await UploadUtils.uploadFiles(
      headers: headers,
      fields: fields,
      method: method,
      url: url,
      files: selectedFiles,
      fieldName: action.fieldName,
      showNotification: action.showNotification,
      onError: action.onError == null
          ? null
          : (error) => executeAction(context, action.onError!),
      progressCallback: (progress) {
        fileResponse?.setProgress(taskId, progress);
        scopeManager?.dispatch(
            ModelChangeEvent(APIBindingSource(action.id!), fileResponse));
      },
      taskId: taskId,
    );

    if (response == null) {
      fileResponse?.setStatus(taskId, UploadStatus.failed);
      return;
    }
    fileResponse?.setHeaders(taskId, response.headers);
    fileResponse?.setBody(taskId, response.body);
    fileResponse?.setStatus(taskId, UploadStatus.completed);
    scopeManager?.dispatch(
        ModelChangeEvent(APIBindingSource(action.id!), fileResponse));

    if (action.onComplete != null) executeAction(context, action.onComplete!);
  }

  List<dynamic>? _getRawFiles(dynamic files, DataContext dataContext) {
    if (files is YamlList) {
      return files
          .map((element) => Map<String, dynamic>.from(element))
          .toList();
    }

    if (files is Map && files.containsKey('path')) {
      return [Map<String, dynamic>.from(files)];
    }

    if (files is String) {
      var rawFiles = dataContext.eval(files);
      if (rawFiles is Map && rawFiles.containsKey('path')) {
        rawFiles = [rawFiles];
      }
      return rawFiles;
    }

    return null;
  }

  bool isFileSizeOverLimit(
      BuildContext context, DataContext dataContext, List<File> selectedFiles, FileUploadAction action) {
    final defaultMaxFileSize = 100.mb;
    const defaultOverMaxFileSizeMessage =
        'The size of is which is larger than the maximum allowed';

    final totalSize = selectedFiles.fold<double>(
        0, (previousValue, element) => previousValue + element.size);
    final maxFileSize = action.maxFileSize?.kb ?? defaultMaxFileSize;

    final message = Utils.translateWithFallback(
      'ensemble.input.overMaxFileSizeMessage',
      action.overMaxFileSizeMessage ?? defaultOverMaxFileSizeMessage,
    );

    if (totalSize > maxFileSize) {
      ToastController().showToast(
          context,
          ShowToastAction(
              type: ToastType.error,
              message: message,
              alignment: Alignment.bottomCenter,
              duration: 3),
          null,
          dataContext: dataContext);
      if (action.onError != null) executeAction(context, action.onError!);
      return true;
    }
    return false;
  }

  Future<void> _setBackgroundUploadTask({
    required BuildContext context,
    required FileUploadAction action,
    required List<File> selectedFiles,
    required Map<String, String> headers,
    required Map<String, String> fields,
    required String method,
    required String url,
    UploadFilesResponse? fileResponse,
    ScopeManager? scopeManager,
  }) async {
    final taskId = generateRandomId(8);
    fileResponse?.addTask(UploadTask(id: taskId, isBackground: true));

    await Workmanager().registerOneOffTask(
      'uploadTask',
      backgroundUploadTask,
      tag: taskId,
      inputData: {
        'fieldName': action.fieldName,
        'files': selectedFiles.map((e) => json.encode(e.toJson())).toList(),
        'headers': json.encode(headers),
        'fields': json.encode(fields),
        'method': method,
        'url': url,
        'taskId': taskId,
        'showNotification': action.showNotification,
      },
      constraints: Constraints(
        networkType: NetworkTypeExtension.fromString(action.networkType),
        requiresBatteryNotLow: action.requiresBatteryNotLow,
      ),
    );

    var port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, taskId);
    StreamSubscription<dynamic>? subscription;
    subscription = port.listen((dynamic data) async {
      if (data is! Map) return;
      if (data.containsKey('progress')) {
        final taskId = data['taskId'];
        fileResponse?.setStatus(taskId, UploadStatus.running);
        fileResponse?.setProgress(taskId, data['progress']);
        if (action.id != null) {
          scopeManager?.dispatch(
              ModelChangeEvent(APIBindingSource(action.id!), fileResponse));
        }
      }

      if (data.containsKey('cancel')) {
        if (action.id != null) {
          scopeManager?.dispatch(
              ModelChangeEvent(APIBindingSource(action.id!), fileResponse));
        }
        subscription?.cancel();
      }

      if (data.containsKey('error')) {
        final taskId = data['taskId'];
        fileResponse?.setStatus(taskId, UploadStatus.failed);
        if (action.id != null) {
          scopeManager?.dispatch(
              ModelChangeEvent(APIBindingSource(action.id!), fileResponse));
        }
        if (action.onError != null) {
          executeAction(context, action.onError!);
        }
        subscription?.cancel();
      }
      if (data.containsKey('responseBody')) {
        final taskId = data['taskId'];
        final response =
            Response.fromBody(data['responseBody'], data['responseHeaders']);
        fileResponse?.setBody(taskId, response.body);
        fileResponse?.setHeaders(taskId, response.headers);
        fileResponse?.setStatus(taskId, UploadStatus.completed);

        if (action.id != null) {
          scopeManager?.dispatch(
              ModelChangeEvent(APIBindingSource(action.id!), fileResponse));
        }

        if (action.onComplete != null) {
          executeAction(context, action.onComplete!);
        }
        subscription?.cancel();
      }
    });
  }

  void dispatchStorageChanges(BuildContext context, String key, dynamic value) {
    ScopeManager? scopeManager = getScopeManager(context);
    if (scopeManager != null) {
      scopeManager.dispatch(ModelChangeEvent(StorageBindingSource(key), value));
    }
  }

  void dispatchSystemStorageChanges(
      BuildContext context, String key, dynamic value,
      {required String storagePrefix}) {
    getScopeManager(context)?.dispatch(ModelChangeEvent(
        SystemStorageBindingSource(key, storagePrefix: storagePrefix), value));
  }

  /// Navigate to another screen
  /// [screenName] - navigate to the screen if specified, otherwise to appHome
  /// [asModal] - shows the App in a regular or modal screen
  /// [replace] - whether to replace the current route on the stack, such that
  /// navigating back will skip the current route.
  /// [pageArgs] - Key/Value pairs to send to the screen if it takes input parameters
  PageRouteBuilder navigateToScreen(
    BuildContext context, {
    String? screenName,
    bool? asModal,
    RouteOption? routeOption,
    Map<String, dynamic>? pageArgs,
    Map<String, dynamic>? transition,
  }) {
    PageType pageType = asModal == true ? PageType.modal : PageType.regular;

    Widget screenWidget =
        getScreen(screenName: screenName, asModal: asModal, pageArgs: pageArgs);

    Map<String, dynamic>? defaultTransitionOptions =
        Theme.of(context).extension<EnsembleThemeExtension>()?.transitions ??
            {};

    final _pageType = pageType == PageType.modal ? 'modal' : 'page';

    final transitionType = PageTransitionTypeX.fromString(
        transition?['type'] ?? defaultTransitionOptions[_pageType]?['type']);
    final alignment = Utils.getAlignment(transition?['alignment'] ??
        defaultTransitionOptions[_pageType]?['alignment']);
    final duration = Utils.getInt(
        transition?['duration'] ??
            defaultTransitionOptions[_pageType]?['duration'],
        fallback: 250);

    PageRouteBuilder route = getScreenBuilder(
      screenWidget,
      pageType: pageType,
      transitionType: transitionType,
      alignment: alignment,
      duration: duration,
    );
    // push the new route and remove all existing screens. This is suitable for logging out.
    if (routeOption == RouteOption.clearAllScreens) {
      Navigator.pushAndRemoveUntil(context, route, (route) => false);
    } else if (routeOption == RouteOption.replaceCurrentScreen) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
    return route;
  }

  /// get the screen widget. If screen is not specified, return the home screen
  Widget getScreen({
    Key? key,
    String? screenName,
    bool? asModal,
    Map<String, dynamic>? pageArgs,
  }) {
    PageType pageType = asModal == true ? PageType.modal : PageType.regular;
    return Screen(
      key: key,
      appProvider: AppProvider(
          definitionProvider: Ensemble().getConfig()!.definitionProvider),
      screenPayload: ScreenPayload(
        screenName: screenName,
        pageType: pageType,
        arguments: pageArgs,
      ),
    );
  }

  void executeGetLocationAction(ScopeManager scopeManager,
      DataContext dataContext, BuildContext context, GetLocationAction action) {
    if (action.onLocationReceived != null) {
      Device().getLocationStatus().then((LocationStatus status) async {
        if (status == LocationStatus.ready) {
          // if recurring
          if (action.recurring == true) {
            StreamSubscription<Position> streamSubscription =
                Geolocator.getPositionStream(
                        locationSettings: LocationSettings(
                            accuracy: LocationAccuracy.high,
                            distanceFilter:
                                action.recurringDistanceFilter ?? 1000))
                    .listen((Position? location) {
              if (location != null) {
                // update last location. TODO: consolidate this
                Device().updateLastLocation(location);

                _onLocationReceived(scopeManager, dataContext, context,
                    action.onLocationReceived!, location);
              } else if (action.onError != null) {
                DataContext localizedContext = dataContext.clone();
                localizedContext.addDataContextById('reason', 'unknown');
                nowExecuteAction(context, localizedContext, action.onError!,
                    scopeManager.pageData.apiMap, scopeManager);
              }
            });
            scopeManager.addLocationListener(streamSubscription);
          }
          // one-time get location
          else {
            _onLocationReceived(scopeManager, dataContext, context,
                action.onLocationReceived!, await Device().simplyGetLocation());
          }
        } else if (action.onError != null) {
          DataContext localizedContext = dataContext.clone();
          localizedContext.addDataContextById('reason', status.name);
          nowExecuteAction(context, localizedContext, action.onError!,
              scopeManager.pageData.apiMap, scopeManager);
        }
      });
    }
  }

  void _onLocationReceived(
      ScopeManager scopeManager,
      DataContext dataContext,
      BuildContext context,
      EnsembleAction onLocationReceived,
      Position location) {
    DataContext localizedContext = dataContext.clone();
    localizedContext.addDataContextById('latitude', location.latitude);
    localizedContext.addDataContextById('longitude', location.longitude);
    nowExecuteAction(context, localizedContext, onLocationReceived,
        scopeManager.pageData.apiMap, scopeManager);
  }

  /// return a wrapper for the screen widget
  /// with custom animation for different pageType
  PageRouteBuilder getScreenBuilder(
    Widget screenWidget, {
    PageType? pageType,
    PageTransitionType? transitionType,
    Alignment? alignment,
    int? duration,
  }) {
    const enableTransition =
        bool.fromEnvironment('transitions', defaultValue: true);

    if (!enableTransition) {
      return EnsemblePageRouteNoTransitionBuilder(screenWidget: screenWidget);
    }

    if (pageType == PageType.modal) {
      return EnsemblePageRouteBuilder(
        child: ModalScreen(screenWidget: screenWidget),
        transitionType: transitionType ?? PageTransitionType.bottomToTop,
        alignment: alignment ?? Alignment.center,
        fullscreenDialog: true,
        opaque: false,
        duration: Duration(milliseconds: duration ?? 250),
        barrierDismissible: true,
        barrierColor: Colors.black54,
      );
    } else {
      return EnsemblePageRouteBuilder(
        child: screenWidget,
        transitionType: transitionType ?? PageTransitionType.fade,
        alignment: alignment ?? Alignment.center,
        duration: Duration(milliseconds: duration ?? 250),
      );
    }
  }
}

enum RouteOption { replaceCurrentScreen, clearAllScreens }

String generateRandomId(int length) {
  var rand = Random();
  var codeUnits = List.generate(length, (index) {
    return rand.nextInt(26) + 97; // ASCII code for lowercase a-z
  });

  return String.fromCharCodes(codeUnits);
}

extension NetworkTypeExtension on NetworkType {
  static NetworkType fromString(String? str) {
    if (str == null) return NetworkType.connected;
    switch (str.toLowerCase()) {
      case 'connected':
        return NetworkType.connected;
      case 'metered':
        return NetworkType.metered;
      case 'not_required':
        return NetworkType.not_required;
      case 'not_roaming':
        return NetworkType.not_roaming;
      case 'unmetered':
        return NetworkType.unmetered;
      case 'temporarily_unmetered':
        return NetworkType.temporarily_unmetered;
      default:
        return NetworkType.connected;
    }
  }
}
