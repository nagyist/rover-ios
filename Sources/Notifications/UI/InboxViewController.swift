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

import RoverFoundation
import RoverData
import RoverUI
import UIKit

open class InboxViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UINavigationBarDelegate, UIViewControllerTransitioningDelegate {
    public let dispatcher: Dispatcher
    public let eventQueue: EventQueue
    public let imageStore: ImageStore
    public let notificationStore: NotificationStore
    public let router: Router
    public let sessionController: SessionController
    public let syncCoordinator: SyncCoordinator
    let conversionsTracker: ConversionsTrackerService
    
    public typealias ActionProvider = (URL) -> Action?
    public let presentWebsiteActionProvider: ActionProvider
    
    public private(set) var navigationBar: UINavigationBar?
    public private(set) var refreshControl = UIRefreshControl()
    public private(set) var tableView = UITableView()
    
    private var cache: [Notification]?
    private var notificationsObservation: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    
    public var notifications: [Notification] {
        if let cache = cache {
            return cache
        }
        
        let notifications = filterNotifications()
        cache = notifications
        return notifications
    }
    
    /**
     Returns a filtered list of notifications from dataStore.notifications. The default implementation filters out notifications that aren't inbox enabled, are deleted or have expired. This method is called automatically by the NotificationCenterTableView and the results are cached for performance.
     
     You can override this method if you wish to modify the rules used to filter notifications. For example if you wish to include expired notifications in the table view and instead show their expired status with a visual indicator.
     */
    open func filterNotifications() -> [Notification] {
        return notificationStore.notifications.filter { notification in
            guard notification.isNotificationCenterEnabled, !notification.isDeleted else {
                return false
            }
            
            if let expiresAt = notification.expiresAt {
                return expiresAt > Date()
            }
            
            return true
        }
    }
    
    public init(
        dispatcher: Dispatcher,
        eventQueue: EventQueue,
        imageStore: ImageStore,
        notificationStore: NotificationStore,
        router: Router,
        sessionController: SessionController,
        syncCoordinator: SyncCoordinator,
        conversionsTracker: ConversionsTrackerService,
        presentWebsiteActionProvider: @escaping ActionProvider
    ) {
        self.dispatcher = dispatcher
        self.eventQueue = eventQueue
        self.imageStore = imageStore
        self.notificationStore = notificationStore
        self.router = router
        self.sessionController = sessionController
        self.syncCoordinator = syncCoordinator
        self.conversionsTracker = conversionsTracker
        self.presentWebsiteActionProvider = presentWebsiteActionProvider
        
        super.init(nibName: nil, bundle: nil)
        
        notificationsObservation = notificationStore.addObserver { [weak self] _ in
            DispatchQueue.main.async {
                self?.reloadData()
            }
        }
    }
    
    /// You may override this to inject behaviour into the UITableView reload process.  Be sure you call super() first.
    open func reloadData() {
        self.cache = nil
        self.tableView.reloadData()
    }
    
    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let didBecomeActiveObserver = self.didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.white
        title = "Inbox"
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.addSubview(refreshControl)
        
        tableView.delegate = self
        tableView.dataSource = self
        
        registerReusableViews()
        
        self.didBecomeActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: OperationQueue.main) { [weak self] _ in
            if self?.viewIfLoaded?.window != nil {
                self?.resetApplicationIconBadgeNumber()
            }
        }
    }
    
    /// Unused; the classic Inbox can no longer update the app badge number.
    open func resetApplicationIconBadgeNumber() {
        // Removed
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        makeNavigationBar()
        configureConstraints()
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let event = EventInfo(name: "Notification Center Presented", namespace: "rover")
        eventQueue.addEvent(event)
        
        sessionController.registerSession(identifier: "inbox") { duration in
            let attributes: Attributes = ["duration": duration]
            return EventInfo(name: "Notification Center Viewed", namespace: "rover", attributes: attributes)
        }
    }
    
    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        let event = EventInfo(name: "Notification Center Dismissed", namespace: "rover")
        eventQueue.addEvent(event)
        
        sessionController.unregisterSession(identifier: "inbox")
    }
    
    // MARK: Layout
    
    open func makeNavigationBar() {
        if let existingNavigationBar = self.navigationBar {
            existingNavigationBar.removeFromSuperview()
        }
        
        if navigationController != nil {
            self.navigationBar = nil
            return
        }
        
        let navigationBar = UINavigationBar()
        navigationBar.delegate = self
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        
        let navigationItem = makeNavigationItem()
        navigationBar.items = [navigationItem]
        
        view.addSubview(navigationBar)
        self.navigationBar = navigationBar
    }
    
    open func makeNavigationItem() -> UINavigationItem {
        let navigationItem = UINavigationItem()
        navigationItem.title = title
        
        if presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done(_:)))
        }
        
        return navigationItem
    }
        
    open func configureConstraints() {
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        if let navigationBar = navigationBar {
            NSLayoutConstraint.activate([
                navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
        
        if #available(iOS 11, *) {
            let layoutGuide = view.safeAreaLayoutGuide
            tableView.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor).isActive = true
            
            if let navigationBar = navigationBar {
                NSLayoutConstraint.activate([
                    navigationBar.topAnchor.constraint(equalTo: layoutGuide.topAnchor),
                    tableView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor)
                ])
            } else {
                tableView.topAnchor.constraint(equalTo: layoutGuide.topAnchor).isActive = true
            }
        } else {
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            
            if let navigationBar = navigationBar {
                NSLayoutConstraint.activate([
                    navigationBar.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor),
                    tableView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor)
                ])
            } else {
                tableView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor).isActive = true
            }
        }
    }
    
    // MARK: Actions
    
    @objc
    func done(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    @objc
    func refresh(_ sender: Any) {
        self.syncCoordinator.sync { _ in
            DispatchQueue.main.async {
                self.refreshControl.endRefreshing()
            }
        }
    }
    
    // MARK: Reuseable Views
    
    open func registerReusableViews() {
        tableView.register(InboxCell.self, forCellReuseIdentifier: "inboxCell")
    }
    
    open func cellReuseIdentifier(at indexPath: IndexPath) -> String {
        return "inboxCell"
    }

    // MARK: UITableViewDataSource

    open func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return notifications.count
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = cellReuseIdentifier(at: indexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier, for: indexPath)
        
        guard let notificationCell = cell as? InboxCell else {
            return cell
        }
        
        let notification = notifications[indexPath.row]
        notificationCell.configure(with: notification, imageStore: imageStore)
        return notificationCell
    }

    // MARK: UITableViewDelegate

    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        openNotification(at: indexPath)
        
        // Prevents the highlighted state from persisting
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    open func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return UISwipeActionsConfiguration(actions: [
            UIContextualAction(style: .destructive, title: "Delete") { _, _, _ in
                self.deleteNotification(at: indexPath)
            }
        ])
    }
    
    open func openNotification(at indexPath: IndexPath) {
        let notification = notifications[indexPath.row]
        
        if !notification.isRead {
            tableView.beginUpdates()
            notificationStore.markNotificationRead(notification.id)
            tableView.endUpdates()
        }
        
        switch notification.tapBehavior {
        case .openApp:
            break
        case .openURL(let url):
            if let action = router.action(for: url) as? PresentViewAction {
                action.viewControllerToPresent.transitioningDelegate = self
                action.viewControllerToPresent.modalPresentationStyle = .fullScreen
                dispatcher.dispatch(action, completionHandler: nil)
            } else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        case .presentWebsite(let url):
            if let action = presentWebsiteActionProvider(url) {
                if let presentViewAction = action as? PresentViewAction {
                    presentViewAction.viewControllerToPresent.transitioningDelegate = self
                }
                
                dispatcher.dispatch(action, completionHandler: nil)
            }
        }
        
        conversionsTracker.track(notification.conversionTags)
        
        let eventInfo = notification.openedEvent(source: .notificationCenter)
        eventQueue.addEvent(eventInfo)
    }
    
    open func deleteNotification(at indexPath: IndexPath) {
        let notification = notifications[indexPath.row]
        if notification.isDeleted {
            return
        }
        
        tableView.beginUpdates()
        notificationStore.markNotificationDeleted(notification.id)
        cache = nil
        tableView.deleteRows(at: [indexPath], with: .automatic)
        tableView.endUpdates()
    }

    // MARK: UINavigationBarDelegate

    open func position(for bar: UIBarPositioning) -> UIBarPosition {
        return .topAttached
    }

    // MARK: UIViewControllerTransitioningDelegate

    class SlideLeftAnimator: NSObject, UIViewControllerAnimatedTransitioning {
        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            guard let toViewController = transitionContext.viewController(forKey: .to) else {
                return
            }
            
            transitionContext.containerView.addSubview(toViewController.view)
            
            let finalFrame = transitionContext.finalFrame(for: toViewController)
            toViewController.view.frame = finalFrame.offsetBy(dx: finalFrame.width, dy: 0)
            
            let duration = transitionDuration(using: transitionContext)
            
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: .curveEaseInOut,
                animations: {
                    toViewController.view.frame = finalFrame
                },
                completion: { finished in
                    transitionContext.completeTransition(finished)
                }
            )
        }
        
        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            return 0.35
        }
    }
    
    class SlideRightAnimator: NSObject, UIViewControllerAnimatedTransitioning {
        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            guard let toViewController = transitionContext.viewController(forKey: .to), let fromViewController = transitionContext.viewController(forKey: .from) else {
                return
            }
            
            transitionContext.containerView.insertSubview(toViewController.view, at: 0)
            
            let finalFrame = transitionContext.finalFrame(for: toViewController)
            let duration = transitionDuration(using: transitionContext)
            
            UIView.animate(
                withDuration: duration,
                animations: {
                    fromViewController.view.frame = finalFrame.offsetBy(dx: finalFrame.width, dy: 0)
                },
                completion: { finished in
                    transitionContext.completeTransition(finished)
                }
            )
        }
        
        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            return 0.35
        }
    }
    
    open func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return SlideLeftAnimator()
    }
    
    open func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return SlideRightAnimator()
    }
}
