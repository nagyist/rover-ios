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


import SwiftUI
import Combine
import RoverFoundation

class ScreenViewController: UIViewController, UIScrollViewDelegate {
    let experience: ExperienceModel
    let screen: Screen
    let data: Any?
    let urlParameters: [String: String]
    let userInfo: [String: Any]
    let deviceContext: [String: Any] = Rover.shared.deviceContext
    let authorizers: Authorizers
    let carouselState: CarouselState
    let experienceManager: ExperienceManager

    init(experience: ExperienceModel, screen: Screen, data: Any? = nil, urlParameters: [String: String], userInfo: [String: Any], authorizers: Authorizers) {
        self.experience = experience
        self.screen = screen
        self.data = data
        self.urlParameters = urlParameters
        self.userInfo = userInfo
        self.authorizers = authorizers
        self.carouselState = CarouselState(experienceUrl: experience.sourceUrl?.absoluteString)
        self.experienceManager = Rover.shared.resolve(ExperienceManager.self)!
        super.init(nibName: nil, bundle: nil)
        super.restorationIdentifier = screen.id
    }

    required init?(coder: NSCoder) {
        fatalError("Rover's ScreenViewController is not supported in Interface Builder or Storyboards.")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        switch screen.statusBarStyle {
        case .default:
            return .default
        case .light:
            return .lightContent
        case .dark:
            return .darkContent
        case .inverted:
            return traitCollection.userInterfaceStyle == .dark
            ? .darkContent
            : .lightContent
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Back Button Style
        switch screen.backButtonStyle {
        case .default(let title):
            if #available(iOS 14.0, *) {
                navigationItem.backButtonDisplayMode = .default
            }

            navigationItem.backButtonTitle = experience.localization.resolve(key: title)
        case .generic:
            if #available(iOS 14.0, *) {
                navigationItem.backButtonDisplayMode = .generic
            }
        case .minimal:
            if #available(iOS 14.0, *) {
                navigationItem.backButtonDisplayMode = .minimal
            }
        }

        // Background Color
        view.backgroundColor = screen.backgroundColor.uikitUIColor(
            colorScheme: traitCollection.colorScheme,
            colorSchemeContrast: traitCollection.colorSchemeContrast
        )

        showOrHideNavBarIfNeeded()

        self.configureNavBar()
        NotificationCenter.default.addObserver(self, selector: #selector(self.configureNavBar), name: ExperienceManager.didRegisterCustomFontNotification, object: nil)
        addChildren()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        showOrHideNavBarIfNeeded()

        if let navBar = navBar {
            navigationController?.navigationBar.adjustTintColor(
                navBar: navBar,
                traits: traitCollection
            )
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        NotificationCenter.default.post(
            name: ExperienceManager.screenViewedNotification,
            object: nil,
            userInfo: [
                "experience": experience,
                "screen": screen,
                "campaignID": self.urlParameters["campaignID"] as Any,
                "data": data as Any
            ]
        )
    }

    @objc private func configureNavBar() {
        if let navBar = navBar {
            navigationItem.configure(
                navBar: navBar,
                experience: experience,
                data: data,
                urlParameters: urlParameters,
                userInfo: userInfo,
                deviceContext: deviceContext,
                traits: traitCollection,
                buttonHandler: { [weak self] navBarButton in self?.navBarButtonTapped(navBarButton) }
            )
        }
    }

    private var experienceViewController: RenderExperienceViewController? {
        func findExperienceViewController(from viewController: UIViewController?) -> RenderExperienceViewController? {
            guard let viewController = viewController else {
                return nil
            }
            return viewController.parent as? RenderExperienceViewController ??
                viewController.parent?.parent as? RenderExperienceViewController ?? // get through NavBarController to the containing ExperienceViewController
                viewController.presentingViewController as? RenderExperienceViewController ??
                viewController.presentingViewController?.children.compactMap { $0 as? RenderExperienceViewController }.first ??
                findExperienceViewController(from: viewController.presentingViewController)
        }

        guard let experienceViewController = findExperienceViewController(from: self) else {
            rover_log(.error, "Unable to obtain containing ExperienceViewController, actions may not work.")
            return nil
        }
        return experienceViewController
    }

    private var experienceViewControllerHolder: ExperienceViewControllerHolder {
        get { return ExperienceViewControllerHolder(experienceViewController) }
    }

    private var screenViewControllerHolder: ScreenViewControllerHolder {
        get { return ScreenViewControllerHolder(self) }
    }

    // MARK: - Nav Bar

    var navBar: NavBar? {
        screen.children.first { $0 is NavBar } as? NavBar
    }

    private func showOrHideNavBarIfNeeded() {
        navigationController?.isNavigationBarHidden = navBar == nil
    }

    private func navBarButtonTapped(_ navBarButton: NavBarButton) {
        guard let experienceViewController = experienceViewController else {
            return
        }

        switch navBarButton.style {
        case .close, .done:
            dismiss(animated: true)
        case .custom:
            navBarButton.action?.handle(
                experience: self.experience,
                node: navBarButton,
                screen: screen,
                data: data,
                urlParameters: urlParameters,
                userInfo: userInfo,
                deviceContext: deviceContext,
                authorizers: authorizers,
                experienceViewController: experienceViewController,
                screenViewController: self
            )
        }
    }

    open func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let navBar = navBar, navBar.titleDisplayMode == .inline else {
            return
        }

        let isScrolling = scrollView.contentOffset.y + scrollView.adjustedContentInset.top > 0
            navigationItem.configureInlineAppearance(
                navBar: navBar,
                traits: traitCollection,
                isScrolling: isScrolling,
                experience: experience
            )

            navigationController?.navigationBar.adjustTintColor(
                navBar: navBar,
                traits: traitCollection,
                isScrolling: isScrolling
            )
    }

    // MARK: - Children

    private func addChildren() {
        screen.children.compactMap { $0 as? Layer }.reversed().forEach { [unowned self] layer in
            addLayer(layer)
        }
    }

    private func addLayer(_ layer: Layer) {
        let rootView = viewForLayer(layer).environment(\.data, data)

        let hostingController = UIHostingController(
            rootView: rootView,
            ignoreSafeArea: true
        )

        addChild(hostingController)

        let view = hostingController.view!
        view.backgroundColor = .clear

        self.view.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false

        let safeAreaLayoutGuide = self.view.safeAreaLayoutGuide

        if layer.ignoresSafeArea?.contains(.top) == true {
            view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        } else {
            view.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor).isActive = true
        }

        if layer.ignoresSafeArea?.contains(.leading) == true {
            view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        } else {
            view.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor).isActive = true
        }

        if layer.ignoresSafeArea?.contains(.bottom) == true {
            view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        } else {
            view.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor).isActive = true
        }

        if layer.ignoresSafeArea?.contains(.trailing) == true {
            view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        } else {
            view.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor).isActive = true
        }

        hostingController.didMove(toParent: self)
    }

    @ViewBuilder
    private func viewForLayer(_ layer: Layer) -> some View {
        if isRootScrollContainer(layer) {
            _viewForLayer(layer)
                .introspectScrollView { [weak self] scrollView in
                    scrollView.delegate = self
                }
        } else {
            _viewForLayer(layer)
        }
    }


    private func _viewForLayer(_ layer: Layer) -> some View {
        SwiftUI.ZStack {
            LayerView(layer: layer)
                .environmentObject(carouselState)
                .environment(\.presentAction, { [weak self] viewController in
                    self?.present(viewController, animated: true)
                })
                .environment(\.showAction, { [weak self] viewController in
                    self?.show(viewController, sender: self)
                })
                .environment(\.screenViewController, screenViewControllerHolder)
                .environment(\.experienceViewController, experienceViewControllerHolder)
                .environment(\.experienceManager, experienceManager)
                .environment(\.experience, experience)
                .environment(\.screen, screen)
                .environment(\.stringTable, experience.localization)
                .environment(\.urlParameters, urlParameters)
                .environment(\.userInfo, userInfo)
                .environment(\.deviceContext, deviceContext)
                .environment(\.authorizers, authorizers)
        }
    }

    private func isRootScrollContainer(_ node: Node) -> Bool {
        guard let scrollContainer = node as? ScrollContainer else {
            return false
        }

        return scrollContainer.axis == .vertical
            && scrollContainer.aspectRatio == nil
            && scrollContainer.padding == nil
            && scrollContainer.frame == nil
            && scrollContainer.layoutPriority == nil
            && scrollContainer.offset == nil
    }
}
