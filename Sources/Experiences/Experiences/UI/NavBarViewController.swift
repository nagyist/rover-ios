// Copyright (c) 2020-present, Rover Labs, Inc. All rights reserved.
// You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
// copy, modify, and distribute this software in source code or binary form for use
// in connection with the web services and APIs provided by Rover.
//
// This copyright notice shall be included in all copies or substantial portions of 
// the software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Combine
import RoverFoundation
import UIKit

class NavBarViewController: UINavigationController, UIScrollViewDelegate {

    // This is a work around for holding onto the LargeTitleDisplayObserver
    // as it requires iOS 13 when the SDK supports a minimum of iOS 11
    private var titleDisplayObserver: AnyObject?

    init(experience: ExperienceModel, screen: Screen, data: Any? = nil, urlParameters: [String: String], userInfo: [String: Any], authorizers: Authorizers) {
        let experienceManager = Rover.shared.resolve(ExperienceManager.self)!
        
        let screenVC = experienceManager.screenViewController(experience, screen, data, urlParameters, userInfo, authorizers)
        super.init(rootViewController: screenVC)
        restorationIdentifier = screen.id

        if #available(iOS 13, *) {
            switch experience.appearance {
            case .light:
                overrideUserInterfaceStyle = .light
            case .dark:
                overrideUserInterfaceStyle = .dark
            case .auto:
                break
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Rover's NavBarViewController is not supported in Interface Builder or Storyboards.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13, *) {
            observeLargeTitleDisplay()
        }
    }

    // MARK: Status Bar

    override var childForStatusBarStyle: UIViewController? {
        visibleViewController
    }

    override var childForStatusBarHidden: UIViewController? {
        visibleViewController
    }

    // MARK: Navigation Bar

    // The `setNavigationBarHidden(_:animated:)` method is called automatically
    // by `UIHostingController` when it is added to the controller hierarchy.
    // The locking mechanism below allows us to no-op the calls made by
    // `UIHostingController` while allowing our own calls to function normally.

    private var isNavigationBarLocked = true

    override var isNavigationBarHidden: Bool {
        set {
            isNavigationBarLocked = false
            setNavigationBarHidden(newValue, animated: false)

            if newValue {
                navigationBar.prefersLargeTitles = false
            } else {
                navigationBar.prefersLargeTitles = true
            }

            isNavigationBarLocked = true
        }

        get {
            super.isNavigationBarHidden
        }
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        guard !isNavigationBarLocked else {
            return
        }

        super.setNavigationBarHidden(hidden, animated: animated)
    }

    @available(iOS 13, *)
    private func observeLargeTitleDisplay() {
       titleDisplayObserver = LargeTitleDisplayObserver(navigationBar: navigationBar, parent: parent) {  [unowned self] isDisplayingLargeTitle in
            largeTitleDisplayDidChange(isDisplayingLargeTitle)
        }
    }

    @available(iOS 13, *)
    private func largeTitleDisplayDidChange(_ isDisplayingLargeTitle: Bool) {
        guard let screenVC = visibleViewController as? ScreenViewController,
              let navBar = screenVC.navBar else {
            return
        }

        navigationBar.adjustTintColor(
            navBar: navBar,
            traits: traitCollection,
            isScrolling: !isDisplayingLargeTitle
        )
    }
}


private class LargeTitleDisplayObserver {

    private var cancellables: Set<AnyCancellable> = []

    private weak var parent: UIViewController?

    init(navigationBar: UINavigationBar, parent: UIViewController?, largeTitleDisplayDidChange: @escaping (Bool) -> Void) {
        self.parent = parent

        navigationBar.publisher(for: \.frame)
            .map { [unowned self] frame in
                frame.height >= largeTitleBreakPoint
            }
            .removeDuplicates()
            .sink { isDisplayingLargeTitle in
                largeTitleDisplayDidChange(isDisplayingLargeTitle)
            }
            .store(in: &cancellables)
    }

    private var largeTitleBreakPoint: CGFloat {
        parent?.modalPresentationStyle == .fullScreen ? 60 : 72
    }
}
