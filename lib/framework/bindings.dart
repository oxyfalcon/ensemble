

import 'package:ensemble/framework/data_context.dart';
import 'package:ensemble/framework/scope.dart';
import 'package:ensemble/util/utils.dart';
import 'package:ensemble_ts_interpreter/invokables/invokable.dart';

/// Binding source represents the binding expression
/// ${myText.text}
/// ${myAPI.body.result.status}
/// ${ensemble.storage.cart}
abstract class BindingSource {
  BindingSource(this.modelId, {this.property, this.type});

  String modelId;
  String? property;   // property can be empty for custom widget inputs
  String? type;       // an additional type to match regardless of modelId

  /// convert an expression ${..} into a BindingSource
  /// TODO: use AST to get all bindable sources
  static BindingSource? from(String expression, DataContext dataContext) {
    if (Utils.isExpression(expression)) {
      String variable = expression.substring(2, expression.length - 1).trim();

      RegExp variableNameRegex = RegExp('^[0-9a-z_]+', caseSensitive: false);

      // storage bindable
      String storageExpr = 'ensemble.storage.';
      if (variable.startsWith(storageExpr)) {
        RegExpMatch? match = variableNameRegex.firstMatch(variable.substring(storageExpr.length));
        if (match != null) {
          String storageKey = match.group(0)!;
          return StorageBindingSource(storageKey);
        }
      } else {

        // if syntax is ${model.property}
        int dotIndex = variable.indexOf('.');
        if (dotIndex != -1) {
          String modelId = variable.substring(0, dotIndex);
          String property = variable.substring(dotIndex + 1);

          // we don't know how to handle complex binding (e.g. myWidget.length > 0 ? "hi" : there"),
          // so for now just grab the property (i.e. .length > 0 ? "hi" : there) until we reach a space
          int spaceIndex = property.indexOf(" ");
          if (spaceIndex != -1) {
            property = property.substring(0, spaceIndex);
          }

          dynamic model = dataContext.getContextById(modelId);
          if (model is APIResponse) {
            return APIBindingSource(modelId);
          } else if (model is Invokable) {
            // for now we only know how to bind to widget's direct property (e.g. myText.text)
            if (model is HasController && !property.contains('.')) {
              return WidgetBindingSource(modelId, property: property);
            }
          }
        }
        // else try to see if it's simply ${model} or ${model == 4....} e.g. custom widget's inputs
        else {
          // just try to find the first variable
          RegExpMatch? match = variableNameRegex.firstMatch(variable);
          if (match != null) {
            String firstVariable = match.group(0)!;
            dynamic model = dataContext.getContextById(firstVariable);
            if (model is Invokable) {
              return SimpleBindingSource(firstVariable);
            }
          }


        }
      }
    }
    return null;
  }




}

/// a bindable source backed by Storage
class StorageBindingSource extends BindingSource {
  StorageBindingSource(super.modelId);
}
/// bindable source backed by API
class APIBindingSource extends BindingSource {
  APIBindingSource(super.modelId);
}
/// simple binding (e.g. custom widget's input variable ${myVar} )
class SimpleBindingSource extends BindingSource {
  SimpleBindingSource(super.modelId);
}
class WidgetBindingSource extends BindingSource {
  WidgetBindingSource(super.modelId, {super.property});
}



/// Binding Destination represents the left predicate of a binding expression
/// myText.text: $(myTextInput.value)
/// myText.text: $(myAPI.body.result.status)
class BindingDestination {
  BindingDestination(this.widget, this.setterProperty);

  Invokable widget;
  String setterProperty;
}

/// dispatching changes for a BindingSource
class ModelChangeEvent {
  ModelChangeEvent(this.source, this.payload, {this.bindingScope});

  BindingSource source;
  dynamic payload;
  ScopeManager? bindingScope;


  @override
  String toString() {
    return "ModelChangeEvent(${source.modelId}, ${source.property}, scope: $bindingScope)";
  }
}