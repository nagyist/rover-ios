//
//  NotificationHandlerService.swift
//  RoverUI
//
//  Created by Sean Rucker on 2018-06-19.
//  Copyright © 2018 Rover Labs Inc. All rights reserved.
//

import UserNotifications
import UIKit
import os

class NotificationHandlerService: NotificationHandler {
    let influenceTracker: InfluenceTracker
    
    public typealias WebsiteViewControllerProvider = (URL) -> UIViewController?
    public let websiteViewControllerProvider: WebsiteViewControllerProvider
    
    let notificationStore: NotificationStore
    let eventPipeline: EventPipeline
    
    init(influenceTracker: InfluenceTracker, notificationStore: NotificationStore, eventPipeline: EventPipeline, websiteViewControllerProvider: @escaping WebsiteViewControllerProvider) {
        self.influenceTracker = influenceTracker
        self.notificationStore = notificationStore
        self.eventPipeline = eventPipeline
        self.websiteViewControllerProvider = websiteViewControllerProvider
    }
    
    func handle(_ response: UNNotificationResponse) -> Bool {
        // The app was opened directly from a push notification. Clear the last received
        // notification from the influence tracker so we don't erroneously track an influenced open.
        influenceTracker.clearLastReceivedNotification()
        
        guard let notification = response.roverNotification else {
            return false
        }
        
        notificationStore.addNotification(notification)
        
        if !notification.isRead {
            notificationStore.markNotificationRead(notification.id)
        }
        
        switch notification.tapBehavior {
        case .openApp:
            break
        case .openURL(let url):
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        case .presentWebsite(let url):
            if let websiteViewController = websiteViewControllerProvider(url) {
                UIApplication.shared.present(websiteViewController, animated: false)
            }
        }
        
        let eventInfo = notification.openedEvent(source: .pushNotification)
        eventPipeline.addEvent(eventInfo)
        
        return true
    }
}
