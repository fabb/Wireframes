import UIKit


open class NavigationControllerWireframe: ViewControllerWireframe, NavigationControllerWireframeInterface {

	override public var currentlyActiveChildWireframe: WireframeInterface? {
		if isPresenting {
			return super.currentlyActiveChildWireframe
		}
		return childWireframes.last
	}

	override public var viewController: UIViewController {
		return navigationController
	}

	fileprivate let navigationController: UINavigationController

	fileprivate var _childWireframes: [ViewControllerWireframeInterface] = []
	fileprivate var childWireframes: [ViewControllerWireframeInterface] {
		get {
			return _childWireframes
		}
		set(newValue) {
			setChildWireframes(newValue, animated: false, completion: {})
		}
	}

	func setChildWireframes(_ childWireframes: [ViewControllerWireframeInterface], animated: Bool, completion: @escaping () -> Void) {
		let oldChildWireframes = _childWireframes
		guard !oldChildWireframes.elementsEqual(childWireframes, by: { $0 === $1 }) else {
			// still need to call completion, so following commands get executed
			completion()
			return
		}

		assert(childWireframes.count > 0)
		assert({
			let removedWireframes = oldChildWireframes.filter({ oldChildWireframe in !childWireframes.contains(where: { newChildWireframe in oldChildWireframe === newChildWireframe }) })
			return !removedWireframes.contains(where: { $0.isPresenting })
		}(), "cannot pop wireframe that is currently presenting")
		// IMPORTANT: the childWireframes array needs to be set BEFORE setting the navigationController.setViewControllers
		_childWireframes = childWireframes
		childWireframes.forEach { wireframe in
			wireframe.parentWireframe = self
		}
		let newViewControllers = childWireframes.map({ wireframe in wireframe.viewController })
		navigationController.setViewControllers(newViewControllers, animated: animated)
		if let tc = navigationController.transitionCoordinator {
			assert(animated)
			assert(!tc.initiallyInteractive, "initiallyInteractive transitions not supported")
			tc.animate(alongsideTransition: nil, completion: { _ in
				completion()
			})
		}
		else {
			// cannot assert for !animated, as in some cases UIKit does not animate a push, even when we tell it to, e.g. when switching tabs and immediately pushing
//			assert(!animated)
			completion()
		}
	}

	/** IMPORTANT
		from this point on this Wireframe manages the UINavigationController instance
		* do not set its `delegate` property, as this Wireframe needs the delegate calls to track the correct state
		* do not modify its `viewControllers` property, rather use NavigationCommands for that
		* do not use any presenting or push/pop methods from it, rather use NavigationCommands for that
	 */
	public init(navigationController: UINavigationController, childWireframes: [ViewControllerWireframeInterface]) {
		self.navigationController = navigationController
		super.init(viewController: navigationController)

		self.navigationController.delegate = self
		self.childWireframes = childWireframes
	}

	override public func handle(_ navigationCommand: NavigationCommand) -> WireframeHandleNavigationCommandResult {
		if case .didHandle(let waiter) = super.handle(navigationCommand) {
			return .didHandle(completionWaiter: waiter)
		}

		if let navigationCommand = navigationCommand as? NavigationControllerNavigationCommand {
			let waiter = DumbWaiter()
			switch navigationCommand {
				case .push(let wireframe, let animated):
					assert(!(wireframe is NavigationControllerWireframeInterface))
					pushWireframe(wireframe, animated: animated, completion: {
						waiter.fulfil()
					})
				case .pushFromFirstChild(let wireframe, let animated):
					assert(!(wireframe is NavigationControllerWireframeInterface))
					guard let first = childWireframes.first else {
						assertionFailure()
						// no wireframes => consider handled
						return .didHandle(completionWaiter: DumbWaiter.fulfilledWaiter())
					}

					setChildWireframes([first, wireframe], animated: animated, completion: {
						waiter.fulfil()
					})
				case .pushWithReplacingCondition(let condition, let findMode, let replaceMode, let wireframe, let animated):
					assert(!(wireframe is NavigationControllerWireframeInterface))
					let prefix = childWireframes.prefix(until: condition, findMode: findMode, replaceMode: replaceMode)
					setChildWireframes(prefix + [wireframe], animated: animated, completion: {
						waiter.fulfil()
					})
				case .pushWithSimulatedPopAnimationWithReplacingCondition(let condition, let findMode, let replaceMode, let wireframe, let animated):
					assert(!(wireframe is NavigationControllerWireframeInterface))
					let prefix = childWireframes.prefix(until: condition, findMode: findMode, replaceMode: replaceMode)
					let remaining = childWireframes.suffix(childWireframes.count - prefix.count)
					// first insert the wireframe, then pop back animated
					// note that if the condition is never met, then remaining will be empty, and still a push animation happens
					setChildWireframes(prefix + [wireframe] + remaining, animated: false, completion: {
						self.setChildWireframes(prefix + [wireframe], animated: animated, completion: {
							waiter.fulfil()
						})
					})
				case .pop(let wireframe, let animated):
					assert(!(wireframe is NavigationControllerWireframeInterface))
					popWireframe(wireframe, animated: animated, completion: {
						waiter.fulfil()
					})
				case .popTo(let wireframe, let animated):
					assert(childWireframes.contains(where: { $0 === wireframe }))
					let prefix = childWireframes.prefix(until: { $0 === wireframe }, findMode: .first, replaceMode: .keepFoundWireframe)
					setChildWireframes(prefix, animated: animated, completion: {
						waiter.fulfil()
					})
				case .popToFirstChild(let animated):
					guard let first = childWireframes.first else {
						assertionFailure()
						// no wireframes => consider handled
						return .didHandle(completionWaiter: DumbWaiter.fulfilledWaiter())
					}

					setChildWireframes([first], animated: animated, completion: {
						waiter.fulfil()
					})
				case .replaceStack(let wireframes, let animated):
					assert(!wireframes.contains(where: { $0 is NavigationControllerWireframeInterface }))
					setChildWireframes(wireframes, animated: animated, completion: {
						waiter.fulfil()
					})
				case .findChild(let condition, let findMode, let found, let notFound):
					func find() -> ViewControllerWireframeInterface? {
						switch findMode {
							case .first:
								return childWireframes.first(where: condition)
							case .last:
								return childWireframes.reversed().first(where: condition)
						}
					}

					if let foundWireframe = find() {
						assert(childWireframes.contains(where: { $0 === foundWireframe }))
						if let command = found(foundWireframe) {
							return handle(command)
						}
						else {
							return .didHandle(completionWaiter: DumbWaiter.fulfilledWaiter())
						}
					}
					else {
						if let command = notFound() {
							return handle(command)
						}
						else {
							return .didHandle(completionWaiter: DumbWaiter.fulfilledWaiter())
						}
					}
			}
			return .didHandle(completionWaiter: waiter)
		}

		return .couldNotHandle
	}

	private func pushWireframe(_ wireframe: ViewControllerWireframeInterface, animated: Bool, completion: @escaping () -> Void) {
		var newWireframes = childWireframes
		newWireframes.append(wireframe)
		setChildWireframes(newWireframes, animated: animated, completion: completion)
	}

	private func popWireframe(_ wireframe: ViewControllerWireframeInterface, animated: Bool, completion: @escaping () -> Void) {
		guard let last = childWireframes.last, wireframe === last else {
			assertionFailure()
			// still need to call completion, as this method does not have any means to report an error
			completion()
			return
		}

		var newWireframes = childWireframes
		_ = newWireframes.popLast()
		setChildWireframes(newWireframes, animated: animated, completion: completion)
	}

}

extension NavigationControllerWireframe: UINavigationControllerDelegate {

	public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
		// navigationController.viewControllers already represents the stack AFTER showing the viewController
		// notice that this delegate method is called even when an interactive movement (back swipe) is started, and later aborted - should rather be called `mightShow viewController`
		if let transitionCoordinator = navigationController.transitionCoordinator, transitionCoordinator.initiallyInteractive {
			// interactive transition active => we need to wait until we are sure it's not cancelled
			var counter = 0
			transitionCoordinator.notifyWhenInteractionChanges({ [weak self] context in
				counter += 1
				assert(counter <= 1, "multiple calls to notifyWhenInteractionChanges not expected for UINavigationController animations, not yet supported")
				assert(!context.isInterruptible, "interruptible UINavigationController animations not yet supported")
				if context.isCancelled {
					// interaction cancelled => nothing to do
				}
				else {
					self?.repairChildWireframes(forViewControllerThatWillBeShown: viewController)
				}
			})
		}
		else {
			repairChildWireframes(forViewControllerThatWillBeShown: viewController)
		}

	}

	private func repairChildWireframes(forViewControllerThatWillBeShown viewController: UIViewController) {
		// NOTE: when the system back button/swipe is used, or an already active tab item is clicked, we need to correctly update childWireframes

		// we know that such a user action has happened when the navigationController.viewControllers array does not match the childWireframes array
		let childWireframesOutOfSync = navigationController.viewControllers != Array(childWireframes.map({ $0.viewController }))

		// the target viewController might have been shown already (when navigating back), but might also not: when starting the app with the first tab segment active, and then switching tab and pushing in one command chain, will/didShow is called for each viewcontroller on the stack separately, and the viewControllers array does not include the last pushed viewcontroller for the first call
		let wireframeToBeShownWasShownBeforeAlready = childWireframes.first(where: { $0.viewController === viewController })?.wasShown ?? false

		if childWireframesOutOfSync, wireframeToBeShownWasShownBeforeAlready {
			let lastNavigationState = currentNavigationState()
			// IMPORTANT: use _childWireframes setter, and NOT childWireframes setter, as we do not want setViewControllers to be called as a side effect
			_childWireframes = navigationController.viewControllers.flatMap({ viewController in
				if let existingWireframe = childWireframes.first(where: { $0.viewController === viewController }) {
					return existingWireframe
				} else {
					fatalError("childWireframes did not contain ViewController \(viewController) - childWireframes needs to be a superset of the viewControllers array - method pushWireframe(_:) needs to be used, or set childWireframes directly")
				}
			})
			dispatch(UIKitNavigationCommand.uikitDidChangeNavigationState(previousNavigationState: lastNavigationState))
		}

		assert(childWireframes.count >= navigationController.viewControllers.count, "always use NavigationCommands instead of directly pushing/popping")

		// mark ALL childWireframes with wasShown, as when showing several wireframes at once, the ones in between have already been correctly added to the childWireframes array
		childWireframes.forEach({ $0.wasShown = true })
	}

}

private extension Array {

	func prefix(until condition: (Element) -> Bool, findMode: WireframeFindMode, replaceMode: WireframeReplaceMode) -> [Element] {
		switch findMode {
			case .first:
				var result: [Element] = []
				for element in self {
					guard !condition(element) else {
						switch replaceMode {
							case .replaceFoundWireframe:
								return result
							case .keepFoundWireframe:
								result.append(element)
								return result
						}
					}
					result.append(element)
				}
				return result

			case .last:
				// if no elements matching condition found => return whole array
				var lastPrefix = self
				var result: [Element] = []
				for element in self {
					if condition(element) {
						switch replaceMode {
							case .replaceFoundWireframe:
								lastPrefix = result
							case .keepFoundWireframe:
								lastPrefix = result
								lastPrefix.append(element)
						}
					}
					result.append(element)
				}
				return lastPrefix
		}
	}

}
