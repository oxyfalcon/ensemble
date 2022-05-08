import 'package:ensemble_ts_interpreter/invokables/invokable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:yaml/yaml.dart';
import 'package:ensemble/framework/action.dart';

class Utils {

  /// return an Integer if it is, or null if not
  static int? optionalInt(dynamic value) {
    return value is int ? value : null;
  }
  static bool? optionalBool(dynamic value) {
    return value is bool ? value : null;
  }
  /// return anything as a string if exists, or null if not
  static String? optionalString(dynamic value) {
    return value?.toString();
  }
  static double? optionalDouble(dynamic value) {
    return
      value is double ? value :
      value is int ? value.toDouble() :
      value is String ? double.tryParse(value) :
      null;
  }

  static EnsembleAction? getAction(dynamic payload, Invokable initiator) {
    if (payload is YamlMap) {
      if (payload['action'] != null) {
        ActionType? type;
        if (payload['action'] == ActionType.navigateScreen.name) {
          type = ActionType.navigateScreen;
        } else if (payload['action'] == ActionType.invokeAPI.name) {
          type = ActionType.invokeAPI;
        }

        if (type != null) {
          Map<String, String>? inputs;
          if (payload['inputs'] is YamlMap) {
            inputs = {};
            (payload['inputs'] as YamlMap).forEach((key, value) {
              inputs![key] = value;
            });
          }
          return EnsembleAction(type, actionName: payload['name'], inputs: inputs);
        }
      }
    } else if (payload is String) {
      return EnsembleAction(ActionType.executeCode, codeBlock: payload, initiator: initiator);
    }
    return null;
  }

  static String getString(dynamic value, {required String fallback}) {
    return value?.toString() ?? fallback;
  }

  static bool getBool(dynamic value, {required bool fallback}) {
    return value is bool ? value : fallback;
  }

  static int getInt(dynamic value, {required int fallback}) {
    return value is int ? value : fallback;
  }

  static double getDouble(dynamic value, {required double fallback}) {
    return
      value is double ? value :
          value is int ? value.toDouble() :
              value is String ? double.tryParse(value) ?? fallback :
                fallback;
  }

  static final onlyExpression = RegExp(r'''^\$\(([a-z_-\d."'\(\)\[\]]+)\)$''', caseSensitive: false);
  static final containExpression = RegExp(r'''\$\(([a-z_-\d."'\(\)\[\]]+)\)''', caseSensitive: false);
  static final i18nExpression = RegExp(r'@[a-zA-Z0-9.-]+',caseSensitive: false);

  //expect @mystring or @myapp.myscreen.mystring as long as @ is there. If @ is not there, returns the string as-is
  static String? translate(String? val,BuildContext context) {
    String? rtn = val;
    if ( val != null && val.trim().isNotEmpty ) {
      rtn = val.replaceAllMapped(i18nExpression, (match) {
        String str = match.input.substring(match.start,match.end);//get rid of the @
        if ( str.length > 1 ) {
          str = str.substring(1);
          str = FlutterI18n.translate(context, str);
        }
        return str;
      });
    }
    return rtn;
  }
  /// is it $(....)
  static bool isExpression(String expression) {
    return onlyExpression.hasMatch(expression);
  }

  /// contains one or more expression e.g Hello $(firstname) $(lastname)
  static bool hasExpression(String expression) {
    return containExpression.hasMatch(expression);
  }

  /// get the list of expression from the raw string
  /// [input]: Hello $(firstname) $(lastname)
  /// @return [ $(firstname), $(lastname) ]
  static List<String> getExpressionsFromString(String input) {
    return containExpression.allMatches(input)
        .map((e) => e.group(0)!)
        .toList();
  }


}