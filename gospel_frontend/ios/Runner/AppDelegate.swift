import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GospelTablePrint")
    else { return }

    let channel = FlutterMethodChannel(
      name: "gospel_topics/print", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "printTable" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let values = call.arguments as? [String: String],
            let title = values["title"], let html = values["html"],
            let view = registrar.viewController?.view,
            UIPrintInteractionController.isPrintingAvailable else {
        result(FlutterError(code: "print_unavailable", message: nil, details: nil))
        return
      }

      let info = UIPrintInfo(dictionary: nil)
      info.jobName = title
      info.outputType = .general
      info.orientation = .landscape
      let controller = UIPrintInteractionController.shared
      controller.printInfo = info
      controller.printFormatter = UIMarkupTextPrintFormatter(markupText: html)
      let completion: UIPrintInteractionController.CompletionHandler = { _, _, error in
        if let error {
          result(FlutterError(code: "print_failed", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
      let presented: Bool
      if view.traitCollection.userInterfaceIdiom == .pad {
        let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        presented = controller.present(from: anchor, in: view, animated: true, completionHandler: completion)
      } else {
        presented = controller.present(animated: true, completionHandler: completion)
      }
      if !presented {
        result(FlutterError(code: "print_unavailable", message: nil, details: nil))
      }
    }
  }
}
