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

import CoreData
import CoreLocation
import os.log
import RoverFoundation
import RoverData

class LocationManager: NSObject {
    let maxGeofenceRegionsToMonitor: Int
    let maxBeaconRegionsToMonitor: Int
    
    let context: NSManagedObjectContext
    let eventQueue: EventQueue
    let geocoder = CLGeocoder()
    let privacyService: PrivacyService
    
    var location: Context.Location?
    
    // Used to avoid tracking redundant location change events
    var lastReportedLocation: CLLocation?
    
    private var currentAuthorizationStatus: CLAuthorizationStatus?
    private var locationManager = CLLocationManager()
    
    typealias RegionIdentifier = String
    
    var currentGeofences = Set<Geofence>()
    var geofenceObservers = ObserverSet<Set<Geofence>>()
    
    var beaconMap = [CLBeaconRegion: Set<Beacon>]()
    var currentBeacons: Set<Beacon> {
        return self.beaconMap.reduce(Set<Beacon>()) { result, element in
            result.union(element.value)
        }
    }
    
    var beaconObservers = ObserverSet<Set<Beacon>>()
    
    init(
        context: NSManagedObjectContext,
        privacyService: PrivacyService,
        eventQueue: EventQueue,
        maxGeofenceRegionsToMonitor: Int,
        maxBeaconRegionsToMonitor: Int
    ) {
        self.privacyService = privacyService
        self.maxGeofenceRegionsToMonitor = maxGeofenceRegionsToMonitor
        self.maxBeaconRegionsToMonitor = maxBeaconRegionsToMonitor
        let theoreticalMaximumGeofences = 20
        if maxGeofenceRegionsToMonitor > theoreticalMaximumGeofences {
            fatalError("You may only specify that Rover can monitor up to \(theoreticalMaximumGeofences) geofences at a time.")
        }
        if maxBeaconRegionsToMonitor >= maxGeofenceRegionsToMonitor {
            fatalError("Rover uses the same region slots for monitoring beacons as it does for monitoring geofences, so therefore you may only specify that Rover can monitor up to the same max number of beacons as geofence regions, currently \(maxGeofenceRegionsToMonitor).")
        }
        self.context = context
        self.eventQueue = eventQueue
        super.init()
        self.locationManager.delegate = self
    }
}

// MARK: CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        self.currentAuthorizationStatus = status
    }
}

// MARK: LocationContextProvider

extension LocationManager: LocationContextProvider {
    var locationAuthorization: String {
        guard privacyService.trackingMode  == .default,
              let authorizationStatus = self.currentAuthorizationStatus else {
            return "denied"
        }
        
        let result: String
        
        switch authorizationStatus {
        case .authorizedAlways:
            result = "authorizedAlways"
        case .authorizedWhenInUse:
            result = "authorizedWhenInUse"
        case .denied:
            result = "denied"
        case .notDetermined:
            result = "notDetermined"
        case .restricted:
            result = "restricted"
        @unknown default:
            result = "notDetermined"
        }
        
        return result
    }
    
    var isLocationServicesEnabled: Bool {
        guard privacyService.trackingMode == .default,
              let authorizationStatus = self.currentAuthorizationStatus else {
            return false
        }
        
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
            
        default:
            return false
        }
    }
}

// MARK: RegionManager

extension LocationManager: RegionManager {
    func updateLocation(manager: CLLocationManager) {
        guard privacyService.trackingMode == .default else {
            self.updateMonitoredRegions(manager: manager)
            return
        }
        
        if manager.location?.coordinate.latitude == lastReportedLocation?.coordinate.latitude,
            manager.location?.coordinate.longitude == lastReportedLocation?.coordinate.longitude,
            manager.location?.altitude == lastReportedLocation?.altitude,
            manager.location?.horizontalAccuracy == lastReportedLocation?.horizontalAccuracy,
            manager.location?.verticalAccuracy == lastReportedLocation?.verticalAccuracy {
            os_log("Location is the same as last known location, skipping", log: .location, type: .debug)
            return
        }
        
        lastReportedLocation = manager.location
        
        if let location = manager.location {
            self.trackLocationUpdate(location: location)
        } else {
            os_log("Current location is unknown", log: .location, type: .debug)
        }
        
        self.updateMonitoredRegions(manager: manager)
    }
    
    func trackLocationUpdate(location: CLLocation) {
        if self.geocoder.isGeocoding {
            os_log("Cancelling in-progress geocode", log: .location, type: .debug)
            self.geocoder.cancelGeocode()
        }
        
        guard privacyService.trackingMode == .default else {
           return
        }
        
        os_log("Geocoding location...", log: .location, type: .debug)
        self.geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let _self = self else {
                return
            }
            
            guard error == nil else {
                os_log("Error geocoding location: %@", log: .location, type: .error, error!.logDescription)
                return
            }
            
            if let placemark = placemarks?.first {
                if let name = placemark.name {
                    os_log("Successfully geocoded location: %@", log: .location, type: .debug, name)
                } else {
                    os_log("Successfully geocoded location", log: .location, type: .debug)
                }
                
                _self.location = placemark.context
            } else {
                os_log("No placemark found for location %@", log: .location, type: .default, location)
                _self.location = location.context(placemark: nil)
            }
            
            _self.eventQueue.addEvent(EventInfo.locationUpdate)
        }
    }
    
    func updateMonitoredRegions(manager: CLLocationManager) {
        let beaconRegions: Set<CLRegion> = Beacon.fetchAll(in: self.context).wildCardRegions(maxLength: self.maxBeaconRegionsToMonitor)
        os_log("Monitoring for %d wildcard (UUID-only) beacon regions", log: .location, type: .debug, beaconRegions.count)
        
        let circularRegions: Set<CLRegion> = Geofence.fetchAll(in: self.context).regions(closestTo: manager.location?.coordinate, maxLength: self.maxGeofenceRegionsToMonitor - beaconRegions.count)
        os_log("Monitoring for %d circular (geofence) regions", log: .location, type: .debug, circularRegions.count)
        
        let regionsToMonitorFor = beaconRegions.union(circularRegions)
        
        // identify all existing regions that are managed by the Rover SDK, and remove them:
        let regionsToReplace = manager.monitoredRegions.filter { monitoredRegion in
            monitoredRegion.identifier.starts(with: "Rover") ||
            regionsToMonitorFor.contains { newRegion in newRegion.reportsSame(region: monitoredRegion )
            }
        }

        for region in regionsToReplace {
            manager.stopMonitoring(for: region)
        }
        
        guard privacyService.trackingMode == .default else {
           return
        }

        for region in regionsToMonitorFor {
            let taggedRegion = region.tagIdentifier(tag: "Rover")
            manager.startMonitoring(for: taggedRegion)
        }
    }
        
    func enterGeofence(region: CLCircularRegion) {
        guard privacyService.trackingMode == .default else {
            return
        }
        
        guard let geofence = Geofence.fetch(
            regionIdentifier: region.untaggedIdentifier(tag: "Rover"),
            in: self.context
        ) else {
            return
        }
        
        self.currentGeofences.insert(geofence)
        self.geofenceObservers.notify(parameters: self.currentGeofences)
        
        os_log("Entered geofence: %@", log: .location, type: .debug, geofence)
        eventQueue.addEvent(geofence.enterEvent)
    }
    
    func exitGeofence(region: CLCircularRegion) {
        guard privacyService.trackingMode == .default else {
            return
        }
        
        guard let geofence = Geofence.fetch(
            regionIdentifier: region.untaggedIdentifier(tag: "Rover"),
            in: self.context
        ) else {
            return
        }
        
        self.currentGeofences.remove(geofence)
        self.geofenceObservers.notify(parameters: self.currentGeofences)
        
        os_log("Exited geofence: %@", log: .location, type: .debug, geofence)
        eventQueue.addEvent(geofence.exitEvent)
    }
    
    func startRangingBeacons(in region: CLBeaconRegion, manager: CLLocationManager) {
        guard privacyService.trackingMode == .default else {
            return
        }
        
        os_log("Started ranging beacons in region: %@", log: .location, type: .debug, region)
        manager.startRangingBeacons(satisfying: region.beaconIdentityConstraint)
    }
    
    func stopRangingBeacons(in region: CLBeaconRegion, manager: CLLocationManager) {
        guard privacyService.trackingMode == .default else {
            return
        }
        
        os_log("Stopped ranging beacons in region: %@", log: .location, type: .debug, region)
        manager.stopRangingBeacons(satisfying: region.beaconIdentityConstraint)
        
        // If there are any lingering beacons when we stop ranging, track exit
        // events and clear them from `beaconMap`.
        
        self.beaconMap[region]?.forEach {
            os_log("Exited beacon: %@", log: .location, type: .debug, $0)
            eventQueue.addEvent($0.exitEvent)
        }
        
        self.beaconMap[region] = nil
    }
    
    func updateNearbyBeacons(_ beacons: [CLBeacon], in region: CLBeaconRegion, manager: CLLocationManager) {
        guard privacyService.trackingMode == .default else {
            return
        }
        
        os_log("Found %d nearby beacons in region: %@", log: .location, type: .debug, beacons.count, region)
        
        let previousBeacons = self.beaconMap[region] ?? Set<Beacon>()
        let identifiers = Set<RegionIdentifier>(beacons.map { $0.regionIdentifier })
        let nextBeacons = Beacon.fetchAll(matchingRegionIdentifiers: identifiers, in: self.context)
        
        guard previousBeacons != nextBeacons else {
            os_log("Nearby beacons already up to date", log: .location, type: .debug)
            return
        }
        
        self.beaconMap[region] = nextBeacons
        
        let enteredBeacons = nextBeacons.subtracting(previousBeacons)
        enteredBeacons.forEach {
            os_log("Entered beacon: %@", log: .location, type: .debug, $0)
            eventQueue.addEvent($0.enterEvent)
        }
        
        let exitedBeacons = previousBeacons.subtracting(nextBeacons)
        exitedBeacons.forEach {
            os_log("Exited beacon: %@", log: .location, type: .debug, $0)
            eventQueue.addEvent($0.exitEvent)
        }
        
        beaconObservers.notify(parameters: self.currentBeacons)
    }
}

// MARK: PrivacyListener

extension LocationManager: PrivacyListener {
    func trackingModeDidChange(_ trackingMode: PrivacyService.TrackingMode) {
        if trackingMode != .default {
            // Geofences and beacons cannot be cleared immediately, but will be on the next updateLocation() call.
            os_log("Tracking disabled, location cleared.")
            self.location = nil
        }
    }
}
