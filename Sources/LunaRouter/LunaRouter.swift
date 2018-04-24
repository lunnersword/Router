import UIKit
import Foundation
import LunaPresentationTransition

public typealias  RouterOpenCallback = ([String: Any]) -> Void


public class Router: NSObject {
	public struct ViewControllerDescription {
		public var fullName: String
		public var packageName: SubString? {
			let names = fullName.split(separator: ".")
			guard names.first != nil else {
				return nil
			}
			return names.first
			
		}
		public var name: Substring? {
			let names = fullName.split(separator: ".")
			if names.count >= 2 {
				return names[1]
			} else {
				return nil
			}
		}
		public var storyboard: String?
		public var nib: String?
		public var bundle: String?
	}
	
	public enum OpenStyle {
		case AsRoot
		case Modal
		case CustomPresentation
		case CustomTransition
		case Show
	}

	public struct RouterOptions {
		public var presentationStyle: UIModalPresentationStyle = UIModalPresentationStyle.none
		public var transitionStyle: UIModalTransitionStyle = UIModalTransitionStyle.coverVertical
		public var defaultsParams: [String: Any] = [:]
		public var shouldPresentedAlongWithNavigationController: Bool = true
		public var callback: RouterOpenCallback?
		public var openCompletion: (() -> Void)? = nil
		public var controllerDescription: ViewControllerDescription
		public var openStyle: OpenStyle = .Show
		public var presentationConfiguration: LunaPresentationTransition.CustomPresentationConfiguration?
		public var presentTransitionConfiguration: LunaPresentationTransition.CustomTransitionConfiguration?
		public var dismissTransitionConfiguration: LunaPresentationTransition.CustomTransitionConfiguration?
		public init() {
			controllerDescription = ViewControllerDescription(fullName: "", storyboard: nil, nib: nil, bundle: nil)
		}
	}
	public static let shared = Router()
	public var navigationController: UINavigationController?
	var routerTable: [String: RouterOptions] = [:]
	public let identifier: String
	public init(_ identifier: String, navigationController: UINavigationController) {
		self.identifier = identifier
		self.navigationController = navigationController
	}
	public override init() {
		self.identifier=""
	}
	
	// MARK: map
	public func map(url: String, toCallback callback: @escaping RouterOpenCallback, withOptions options:RouterOptions? = nil) {
		if !url.isEmpty {
			var options = options ?? RouterOptions()
			options.callback = callback
			routerTable[url] = options
		}
	}
	
	public func map(url: String, toViewController controller: String, withOptions options: RouterOptions? = nil) {
		if !url.isEmpty {
			var options = options ?? RouterOptions()
			options.controllerDescription.fullName = controller
			routerTable[url] = options
		}
	}
	
	public func open(external url: String, options: [String: Any], completionHandler:((Bool) -> Void)? = nil) {
		
		if let url = URL(string: url), UIApplication.shared.canOpenURL(url) {
			UIApplication.shared.open(url, options: options, completionHandler: completionHandler)
		}
	}
	
	public func open(url: String, animated: Bool = true, extraParams: [String: Any]?) {
		if let options = routerTable[url] {
			guard navigationController != nil else {
				return
			}
			var queryParams = options.defaultsParams
			queryParams.merge(Router.queryParams(of: url)) { (_, new) in new}
			if let extra = extraParams {
				queryParams.merge(extra) { (_, new)  in new }
			}
			if var viewController = Router.viewController(from: options) {
				Router.initialize(viewController: viewController, params: queryParams)
				viewController.modalPresentationStyle = options.presentationStyle
				viewController.modalTransitionStyle = options.transitionStyle
				switch options.openStyle {
				case .AsRoot:
					if navigationController != nil {
							navigationController!.setViewControllers([viewController], animated: animated)
					}
				case .CustomPresentation, .CustomTransition:
					if options.shouldPresentedAlongWithNavigationController {
						viewController = Router.alongWithNavigationController(viewController: viewController)
					}
					viewController.transitioningDelegate = ViewControllerTransitioningDelegate(presentTransitionConfiguration: options.presentTransitionConfiguration, dismissTransitionConfiguration: options.dismissTransitionConfiguration, presentationConfiguration: options.presentationConfiguration)
					Router.currentViewController()?.present(viewController, animated: animated, completion: options.openCompletion)

				case .Modal:
					if options.shouldPresentedAlongWithNavigationController {
						viewController = Router.alongWithNavigationController(viewController: viewController)
					}
					Router.currentViewController()?.present(viewController, animated: animated, completion: options.openCompletion)
				default:
					if options.shouldPresentedAlongWithNavigationController {
						viewController = Router.alongWithNavigationController(viewController: viewController)
					}
					Router.currentViewController()?.show(viewController, sender: Router.currentViewController())
				}
			}
		}
	}
	
	static func alongWithNavigationController(viewController: UIViewController) -> UIViewController {
		let navigationController = UINavigationController(rootViewController: viewController)
		navigationController.modalTransitionStyle = viewController.modalTransitionStyle
		navigationController.modalPresentationStyle = viewController.modalPresentationStyle
		return navigationController
	}
	
	static func queryParams(of url: String) -> [String: Any] {
		return [:]
	}
	static func viewController(from options: RouterOptions) -> UIViewController? {
		var bundle: Bundle?
		if let bundleStr = options.controllerDescription.bundle {
			bundle = Bundle(path: bundleStr)
		}
		var fromNib: Bool = false
		if let nib = options.controllerDescription.nib, !nib.isEmpty {
			fromNib = true
		}
		return Router.viewController(name: options.controllerDescription.fullName, storyboard: options.controllerDescription.storyboard, bundle: bundle, fromNib: fromNib)
	}
	
	// name: "appName.viewControllerName"
	static func viewController(name: String, storyboard: String?, bundle:Bundle? = nil, fromNib: Bool = false) -> UIViewController? {
		var viewController: UIViewController?
		if let storyboard = storyboard {
			viewController  = UIStoryboard(name: storyboard, bundle: bundle).instantiateViewController(withIdentifier: name)
		} else{
			let viewContollerClass = NSClassFromString(name) as! UIViewController.Type
			if let className = name.components(separatedBy: ".").last, fromNib {
				viewController = viewContollerClass.init(nibName: className, bundle: bundle)
			} else {
				viewController = viewContollerClass.init()
			}
		}
		return viewController
	}
	
	static func initialize(viewController: UIViewController, params: [String: Any]) {
		for (key, value) in params {
			viewController.setValue(value, forKey: key)
		}
	}
	
	public static func mainWindow() -> UIWindow? {
		if let appDelegate = UIApplication.shared.delegate, let window = appDelegate.window, let realWin = window{
			return realWin
		}
	 	let windows = UIApplication.shared.windows
		if windows.count == 1 {
			return windows.first!
		} else {
			for window in windows {
				if window.windowLevel == UIWindowLevelNormal {
					return window
				}
			}
		}
		return nil
	}
	
	public static func currentViewController() -> UIViewController? {
		var rootViewController = Router.mainWindow()?.rootViewController
		guard rootViewController != nil else {
			return nil
		}
		var temp: UIViewController?
		while true {
			temp = nil
			if (rootViewController!.isKind(of: UINavigationController.self)) {
				let navigationController = rootViewController as! UINavigationController
				temp = navigationController.visibleViewController
			} else if (rootViewController!.isKind(of: UITabBarController.self)) {
				let tabBarController = rootViewController as! UITabBarController
				temp = tabBarController.selectedViewController
			} else if rootViewController?.presentedViewController != nil {
				temp = rootViewController?.presentedViewController
			}
			if temp != nil {
				rootViewController = temp!
			} else {
				break;
			}
		}
		return rootViewController
	}
	
	
}
