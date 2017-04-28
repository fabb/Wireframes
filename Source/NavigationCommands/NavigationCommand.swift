import UIKit


public protocol NavigationCommand: NavigationCommandChain {}

public protocol NavigationCommandChain {

	func navigationCommandSequence() -> NavigationCommandSequence

}

public extension NavigationCommand {

	func navigationCommandSequence() -> NavigationCommandSequence {
		return NavigationCommandSequence([self])
	}

}

public typealias NavigationCommandSequence = AnySequence<NavigationCommand>

// TODO other presentation styles
public enum ModalPresentationStyle {
	case fullScreen
	case popoverFromBarButton(barButtonItem: UIBarButtonItem, permittedArrowDirections: UIPopoverArrowDirection, willRepositionPopoverToRectInViewBlock: PopoverWillRepositionPopoverToRectInViewBlock?)
	case popoverFromView(sourceView: UIView, sourceRect: CGRect, permittedArrowDirections: UIPopoverArrowDirection, willRepositionPopoverToRectInViewBlock: PopoverWillRepositionPopoverToRectInViewBlock?)

	func uiModalPresentationStyle() -> UIModalPresentationStyle {
		switch self {
			case .fullScreen:
				return .fullScreen
			case .popoverFromBarButton, .popoverFromView:
				return .popover
		}
	}
}

// TODO other transition styles
public enum ModalTransitionStyle {
	case coverVertical

	func uiModalTransitionStyle() -> UIModalTransitionStyle {
		switch self {
		case .coverVertical:
			return .coverVertical
		}
	}
}

// used as a workaround for navigation state changing actions by UIKit which are not initiated by dispatching NavigationCommands, e.g. back button/swipe or switching tabs
public enum UIKitNavigationCommand: NavigationCommand {
	case uikitDidChangeNavigationState(previousNavigationState: NavigationStateInterface)
}

public enum KeyboardDismissNavigationCommand: NavigationCommand {
	case dismissKeyboard
}

public enum PresentationControllerNavigationCommand: NavigationCommand {
	case present(wireframe: ViewControllerWireframeInterface, modalPresentationStyle: ModalPresentationStyle, modalTransitionStyle: ModalTransitionStyle, animated: Bool)
	case presentAlert(wireframe: AlertWireframeInterface)
	case dismiss(wireframe: ViewControllerWireframeInterface, animated: Bool)
	case popoverWasDismissedByUserTappingOutside(wireframe: ViewControllerWireframeInterface)
	case alertWasDismissed(wireframe: AlertWireframeInterface)
}

public enum GlobalPresentationControllerNavigationCommand: NavigationCommand {
	case dismissAnythingIfPresented(animated: Bool)
}

public enum NavigationControllerNavigationCommand: NavigationCommand {
	case push(wireframe: ViewControllerWireframeInterface, animated: Bool)
	case pushFromFirstChild(wireframe: ViewControllerWireframeInterface, animated: Bool)
	case pushWithReplacingCondition(condition: (ViewControllerWireframeInterface) -> Bool, findMode: WireframeFindMode, replaceMode: WireframeReplaceMode, wireframe: ViewControllerWireframeInterface, animated: Bool)
	case pushWithSimulatedPopAnimationWithReplacingCondition(condition: (ViewControllerWireframeInterface) -> Bool, findMode: WireframeFindMode, replaceMode: WireframeReplaceMode, wireframe: ViewControllerWireframeInterface, animated: Bool)
	case pop(wireframe: ViewControllerWireframeInterface, animated: Bool)
	case popTo(wireframe: ViewControllerWireframeInterface, animated: Bool)
	case popToFirstChild(animated: Bool)
	case replaceStack(wireframes: [ViewControllerWireframeInterface], animated: Bool)
	case findChild(condition: (ViewControllerWireframeInterface) -> Bool, findMode: WireframeFindMode, found: (ViewControllerWireframeInterface) -> NavigationControllerNavigationCommand?, notFound: () -> NavigationControllerNavigationCommand?)
}

public enum WireframeFindMode {
	case first
	case last
}

public enum WireframeReplaceMode {
	case keepFoundWireframe
	case replaceFoundWireframe
}

public enum TabBarControllerNavigationCommand: NavigationCommand {
	case switchTab(toWireframeWithTag: WireframeTag)
	case cycleTabs()
	case replaceTabs(wireframesAndTags: [(ViewControllerWireframeInterface, WireframeTag)], selectedTag: WireframeTag)
}

public struct TabBarAndNavigationControllerNavigationCommandChain: NavigationCommandChain {

	let tabBarControllerNavigationCommand: TabBarControllerNavigationCommand
	let navigationControllerNavigationCommand: NavigationControllerNavigationCommand

	public init(tabBarControllerNavigationCommand: TabBarControllerNavigationCommand, navigationControllerNavigationCommand: NavigationControllerNavigationCommand) {
		self.tabBarControllerNavigationCommand = tabBarControllerNavigationCommand
		self.navigationControllerNavigationCommand = navigationControllerNavigationCommand
	}

	public init(switchToTabWithTag tabTag: WireframeTag, andPushWireframeAnimated wireframeToPush: ViewControllerWireframeInterface) {
		self.init(
				tabBarControllerNavigationCommand: TabBarControllerNavigationCommand.switchTab(toWireframeWithTag: tabTag),
				navigationControllerNavigationCommand: NavigationControllerNavigationCommand.push(wireframe: wireframeToPush, animated: true)
		)
	}

	public func navigationCommandSequence() -> NavigationCommandSequence {
		let navigationCommands: [NavigationCommand] = [tabBarControllerNavigationCommand, navigationControllerNavigationCommand]
		return NavigationCommandSequence(navigationCommands)
	}

}
