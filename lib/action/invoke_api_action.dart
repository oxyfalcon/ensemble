import 'dart:developer';

import 'package:ensemble/framework/action.dart';
import 'package:ensemble/framework/bindings.dart';
import 'package:ensemble/framework/data_context.dart';
import 'package:ensemble/framework/error_handling.dart';
import 'package:ensemble/framework/scope.dart';
import 'package:ensemble/screen_controller.dart';
import 'package:ensemble/util/http_utils.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';
import 'package:flutter/cupertino.dart';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;

class InvokeAPIAction extends EnsembleAction {
  InvokeAPIAction(
      {Invokable? initiator,
      required this.apiName,
      this.id,
      Map<String, dynamic>? inputs,
      this.onResponse,
      this.onError})
      : super(initiator: initiator, inputs: inputs);

  String? id;
  final String apiName;
  EnsembleAction? onResponse;
  EnsembleAction? onError;

  factory InvokeAPIAction.fromYaml({Invokable? initiator, Map? payload}) {
    if (payload == null || payload['name'] == null) {
      throw LanguageError(
          "${ActionType.invokeAPI.name} requires the 'name' of the API.");
    }

    return InvokeAPIAction(
        initiator: initiator,
        apiName: payload['name'],
        id: Utils.optionalString(payload['id']),
        inputs: Utils.getMap(payload['inputs']),
        onResponse: EnsembleAction.fromYaml(payload['onResponse'],
            initiator: initiator),
        onError:
            EnsembleAction.fromYaml(payload['onError'], initiator: initiator));
  }

  @override
  Future execute(BuildContext context, ScopeManager scopeManager,
      {DataContext? dataContext}) {
    DataContext realDataContext = dataContext ?? scopeManager.dataContext;
    var evalApiName = realDataContext.eval(apiName);
    var cloneAction = InvokeAPIAction(
        apiName: evalApiName,
        initiator: initiator,
        id: id,
        inputs: inputs,
        onResponse: onResponse,
        onError: onError);
    return InvokeAPIController().execute(cloneAction, context, realDataContext,
        scopeManager, scopeManager.pageData.apiMap);
  }
}

class InvokeAPIController {
  Future<Response?> executeWithContext(
      BuildContext context, InvokeAPIAction action,
      {Map<String, dynamic>? additionalInputs}) {
    ScopeManager? scopeManager = ScreenController().getScopeManager(context);
    if (scopeManager != null) {
      // add additional data if specified
      DataContext dataContext = scopeManager.dataContext;
      if (additionalInputs != null) {
        dataContext.addDataContext(additionalInputs);
      }

      return execute(action, context, dataContext, scopeManager,
          scopeManager.pageData.apiMap);
    }
    throw Exception('Unable to execute API from context');
  }

  Future<Response?> execute(
      InvokeAPIAction action,
      BuildContext context,
      DataContext dataContext,
      ScopeManager? scopeManager,
      Map<String, YamlMap>? apiMap) async {
    YamlMap? apiDefinition = apiMap?[action.apiName];
    if (apiDefinition != null) {
      // evaluate input arguments and add them to context
      if (apiDefinition['inputs'] is YamlList && action.inputs != null) {
        for (var input in apiDefinition['inputs']) {
          dynamic value = dataContext.eval(action.inputs![input]);
          if (value != null) {
            dataContext.addDataContextById(input, value);
          }
        }
      }

      // if invokeAPI has an ID, add it to context so we can bind to it
      // This is useful when the API is called in a loop, so binding to its API name won't work properly
      if (action.id != null && !dataContext.hasContext(action.id!)) {
        scopeManager!.dataContext
            .addInvokableContext(action.id!, APIResponse());
      }

      try {
        final APIResponse? oldResponse =
            dataContext.getContextById(action.apiName);
        final Response? responseObj = oldResponse?.getAPIResponse();
        responseObj?.apiState = APIState.loading;

        final isSameAPIRequest = action.apiName == responseObj?.apiName;
        final responseToDispatch = (isSameAPIRequest && responseObj != null)
            ? responseObj
            : Response.updateState(apiState: APIState.loading);
        dispatchAPIChanges(
          scopeManager,
          action,
          APIResponse(response: responseToDispatch),
        );

        Response response = await HttpUtils.invokeApi(
            context, apiDefinition, dataContext, action.apiName);
        if (response.isOkay) {
          _onAPIComplete(context, dataContext, action, apiDefinition, response,
              apiMap, scopeManager);
        } else {
          processAPIError(context, dataContext, action, apiDefinition, response,
              apiMap, scopeManager);
        }
        return response;
      } catch (error) {
        processAPIError(context, dataContext, action, apiDefinition, error,
            apiMap, scopeManager);
      }
    } else {
      throw RuntimeError("Unable to find api definition for ${action.apiName}");
    }
  }

  /// e.g upon return of API result
  void _onAPIComplete(
      BuildContext context,
      DataContext dataContext,
      InvokeAPIAction action,
      YamlMap apiDefinition,
      Response response,
      Map<String, YamlMap>? apiMap,
      ScopeManager? scopeManager) {
    // first execute API's onResponse code block
    EnsembleAction? onResponse = EnsembleAction.fromYaml(
        apiDefinition['onResponse'],
        initiator: action.initiator);
    if (onResponse != null) {
      response.apiState = APIState.success;
      processAPIResponse(
          context, dataContext, onResponse, response, apiMap, scopeManager,
          apiChangeHandler: dispatchAPIChanges,
          action: action,
          modifiableAPIResponse: true);
    }
    // dispatch changes even if we don't have onResponse
    else {
      response.apiState = APIState.success;
      dispatchAPIChanges(scopeManager, action, APIResponse(response: response));
    }

    // if our Action has onResponse, invoke that next
    if (action.onResponse != null) {
      response.apiState = APIState.success;
      processAPIResponse(context, dataContext, action.onResponse!, response,
          apiMap, scopeManager);
    }
  }

  /// Executing the onResponse action. Note that this can be
  /// the API's onResponse or a caller's onResponse (e.g. onPageLoad's onResponse)
  void processAPIResponse(
      BuildContext context,
      DataContext dataContext,
      EnsembleAction onResponseAction,
      Response response,
      Map<String, YamlMap>? apiMap,
      ScopeManager? scopeManager,
      {Function? apiChangeHandler,
      InvokeAPIAction? action,
      bool? modifiableAPIResponse}) {
    // execute the onResponse on the API definition
    APIResponse apiResponse = modifiableAPIResponse == true
        ? ModifiableAPIResponse(response: response)
        : APIResponse(response: response);

    DataContext localizedContext = dataContext.clone();
    localizedContext.addInvokableContext('response', apiResponse);
    ScreenController().nowExecuteAction(
        context, localizedContext, onResponseAction, apiMap, scopeManager);

    if (modifiableAPIResponse == true) {
      // should be on Action's callback instead
      apiChangeHandler?.call(scopeManager, action, apiResponse);
    }
  }

  /// executing the onError action
  void processAPIError(
      BuildContext context,
      DataContext dataContext,
      InvokeAPIAction action,
      YamlMap apiDefinition,
      dynamic errorResponse,
      Map<String, YamlMap>? apiMap,
      ScopeManager? scopeManager) {
    //log("Error: $error");

    DataContext localizedContext = dataContext.clone();
    if (errorResponse is Response) {
      errorResponse.apiState = APIState.error;
      localizedContext.addInvokableContext(
          'response', APIResponse(response: errorResponse));
      // dispatch the changes to the response
      dispatchAPIChanges(
          scopeManager, action, APIResponse(response: errorResponse));
    } else {
      // exception, how do we want to expose to the user?
      dispatchAPIChanges(
        scopeManager,
        action,
        APIResponse(
            response: Response(errorResponse, APIState.error,
                apiName: action.apiName)),
      );
    }

    EnsembleAction? onErrorAction =
        EnsembleAction.fromYaml(apiDefinition['onError']);
    if (onErrorAction != null) {
      // probably want to include the error?
      ScreenController().nowExecuteAction(
          context, localizedContext, onErrorAction, apiMap, scopeManager);
    }

    // if our Action has onError, invoke that next
    if (action.onError != null) {
      ScreenController().nowExecuteAction(
          context, localizedContext, action.onError!, apiMap, scopeManager);
    }

    // silently fail if error handle is not defined? or should we alert user?
  }

  void dispatchAPIChanges(ScopeManager? scopeManager, InvokeAPIAction action,
      APIResponse apiResponse) {
    // update the API response in our DataContext and fire changes to all listeners.
    // Make sure we don't override the key here, as all the scopes referenced the same API
    if (scopeManager != null) {
      dynamic api = scopeManager.dataContext.getContextById(action.apiName);
      if (api == null || api is! Invokable) {
        throw RuntimeException(
            "Unable to update API Binding as it doesn't exists");
      }
      Response? _response = apiResponse.getAPIResponse();
      if (_response != null) {
        _response.apiName = action.apiName;
        // for convenience, the result of the API contain the API response
        // so it can be referenced from anywhere.
        // Here we set the response and dispatch changes
        if (api is APIResponse) {
          api.setAPIResponse(_response);
          scopeManager.dispatch(
              ModelChangeEvent(APIBindingSource(action.apiName), api));
        }

        // if the API has an ID, update its reference and se
        if (action.id != null) {
          dynamic apiById = scopeManager.dataContext.getContextById(action.id!);
          if (apiById is APIResponse) {
            apiById.setAPIResponse(_response);
            scopeManager.dispatch(
                ModelChangeEvent(APIBindingSource(action.id!), apiById));
          }
        }
      }
    }
  }
}
