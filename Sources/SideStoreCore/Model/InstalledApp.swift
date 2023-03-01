//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import Foundation

import AltSign
import SemanticVersion

// Free developer accounts are limited to only 3 active sideloaded apps at a time as of iOS 13.3.1.
public let ALTActiveAppsLimit = 3

public protocol InstalledAppProtocol: Fetchable {
    var name: String { get }
    var bundleIdentifier: String { get }
    var resignedBundleIdentifier: String { get }
    var version: String { get }

    var refreshedDate: Date { get }
    var expirationDate: Date { get }
    var installedDate: Date { get }
}

@objc(InstalledApp)
public class InstalledApp: NSManagedObject, InstalledAppProtocol {
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var resignedBundleIdentifier: String
    @NSManaged public var version: String

    @NSManaged public var refreshedDate: Date
    @NSManaged public var expirationDate: Date
    @NSManaged public var installedDate: Date

    @NSManaged public var isActive: Bool
    @NSManaged public var needsResign: Bool
    @NSManaged public var hasAlternateIcon: Bool

    @NSManaged public var certificateSerialNumber: String?

    /* Transient */
    @NSManaged public var isRefreshing: Bool

    /* Relationships */
    @NSManaged public var storeApp: StoreApp?
    @NSManaged public var team: Team?
    @NSManaged public var appExtensions: Set<InstalledExtension>

    @NSManaged public private(set) var loggedErrors: NSSet /* Set<LoggedError> */ // Use NSSet to avoid eagerly fetching values.

    public var isSideloaded: Bool {
        storeApp == nil
    }

    @objc public var hasUpdate: Bool {
        if storeApp == nil { return false }
        if storeApp!.latestVersion == nil { return false }

        let currentVersion = SemanticVersion(version)
        let latestVersion = SemanticVersion(storeApp!.latestVersion!.version)

        if currentVersion == nil || latestVersion == nil {
            // One of the versions is not valid SemVer, fall back to comparing the version strings by character
            return version < storeApp!.latestVersion!.version
        }

        return currentVersion! < latestVersion!
    }

    public var appIDCount: Int {
        1 + appExtensions.count
    }

    public var requiredActiveSlots: Int {
        let requiredActiveSlots = UserDefaults.standard.activeAppLimitIncludesExtensions ? self.appIDCount : 1
        return requiredActiveSlots
    }

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public init(resignedApp: ALTApplication, originalBundleIdentifier: String, certificateSerialNumber: String?, context: NSManagedObjectContext) {
        super.init(entity: InstalledApp.entity(), insertInto: context)

        bundleIdentifier = originalBundleIdentifier

        print("InstalledApp `self.bundleIdentifier`: \(bundleIdentifier)")

        refreshedDate = Date()
        installedDate = Date()

        expirationDate = refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.

        update(resignedApp: resignedApp, certificateSerialNumber: certificateSerialNumber)
    }

    public func update(resignedApp: ALTApplication, certificateSerialNumber: String?) {
        name = resignedApp.name

        resignedBundleIdentifier = resignedApp.bundleIdentifier
        version = resignedApp.version

        self.certificateSerialNumber = certificateSerialNumber

        if let provisioningProfile = resignedApp.provisioningProfile {
            update(provisioningProfile: provisioningProfile)
        }
    }

    public func update(provisioningProfile: ALTProvisioningProfile) {
        refreshedDate = provisioningProfile.creationDate
        expirationDate = provisioningProfile.expirationDate
    }

    public func loadIcon(completion: @escaping (Result<UIImage?, Error>) -> Void) {
        let hasAlternateIcon = self.hasAlternateIcon
        let alternateIconURL = self.alternateIconURL
        let fileURL = self.fileURL

        DispatchQueue.global().async {
            do {
                if hasAlternateIcon,
                   case let data = try Data(contentsOf: alternateIconURL),
                   let icon = UIImage(data: data) {
                    return completion(.success(icon))
                }

                let application = ALTApplication(fileURL: fileURL)
                completion(.success(application?.icon))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

public extension InstalledApp {
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp> {
        NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
    }

    class func updatesFetchRequest() -> NSFetchRequest<InstalledApp> {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.predicate = NSPredicate(format: "%K == YES AND %K == YES",
                                             #keyPath(InstalledApp.isActive), #keyPath(InstalledApp.hasUpdate))
        return fetchRequest
    }

    class func activeAppsFetchRequest() -> NSFetchRequest<InstalledApp> {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.predicate = NSPredicate(format: "%K == YES", #keyPath(InstalledApp.isActive))
        print("Active Apps Fetch Request: \(String(describing: fetchRequest.predicate))")
        return fetchRequest
    }

    class func fetchAltStore(in context: NSManagedObjectContext) -> InstalledApp? {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        print("Fetch 'AltStore' Predicate: \(String(describing: predicate))")
        let altStore = InstalledApp.first(satisfying: predicate, in: context)
        return altStore
    }

    class func fetchActiveApps(in context: NSManagedObjectContext) -> [InstalledApp] {
        let activeApps = InstalledApp.fetch(InstalledApp.activeAppsFetchRequest(), in: context)
        return activeApps
    }

    class func fetchAppsForRefreshingAll(in context: NSManagedObjectContext) -> [InstalledApp] {
        var predicate = NSPredicate(format: "%K == YES AND %K != %@", #keyPath(InstalledApp.isActive), #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        print("Fetch Apps for Refreshing All 'AltStore' predicate: \(String(describing: predicate))")

//        if let patreonAccount = DatabaseManager.shared.patreonAccount(in: context), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
//        {
//            // No additional predicate
//        }
//        else
//        {
//            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate,
//                                                                            NSPredicate(format: "%K == nil OR %K == NO", #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.isBeta))])
//        }

        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)

        if let altStoreApp = InstalledApp.fetchAltStore(in: context) {
            // Refresh AltStore last since it causes app to quit.
            installedApps.append(altStoreApp)
        }

        return installedApps
    }

    class func fetchAppsForBackgroundRefresh(in context: NSManagedObjectContext) -> [InstalledApp] {
        // Date 6 hours before now.
        let date = Date().addingTimeInterval(-1 * 6 * 60 * 60)

        var predicate = NSPredicate(format: "(%K == YES) AND (%K < %@) AND (%K != %@)",
                                    #keyPath(InstalledApp.isActive),
                                    #keyPath(InstalledApp.refreshedDate), date as NSDate,
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        print("Active Apps For Background Refresh 'AltStore' predicate: \(String(describing: predicate))")

//        if let patreonAccount = DatabaseManager.shared.patreonAccount(in: context), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
//        {
//            // No additional predicate
//        }
//        else
//        {
//            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate,
//                                                                            NSPredicate(format: "%K == nil OR %K == NO", #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.isBeta))])
//        }

        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)

        if let altStoreApp = InstalledApp.fetchAltStore(in: context), altStoreApp.refreshedDate < date {
            // Refresh AltStore last since it may cause app to quit.
            installedApps.append(altStoreApp)
        }

        return installedApps
    }
}

public extension InstalledApp {
    var openAppURL: URL {
        let openAppURL = URL(string: "altstore-" + bundleIdentifier + "://")!
        return openAppURL
    }

    class func openAppURL(for app: AppProtocol) -> URL {
        let openAppURL = URL(string: "altstore-" + app.bundleIdentifier + "://")!
        return openAppURL
    }
}

public extension InstalledApp {
    class var appsDirectoryURL: URL {
        let baseDirectory = FileManager.default.altstoreSharedDirectory ?? FileManager.default.applicationSupportDirectory
        let appsDirectoryURL = baseDirectory.appendingPathComponent("Apps")

        do { try FileManager.default.createDirectory(at: appsDirectoryURL, withIntermediateDirectories: true, attributes: nil) } catch { print("Creating App Directory Error: \(error)") }
        print("`appsDirectoryURL` is set to: \(appsDirectoryURL.absoluteString)")
        return appsDirectoryURL
    }

    class var legacyAppsDirectoryURL: URL {
        let baseDirectory = FileManager.default.applicationSupportDirectory
        let appsDirectoryURL = baseDirectory.appendingPathComponent("Apps")
        print("legacy `appsDirectoryURL` is set to: \(appsDirectoryURL.absoluteString)")
        return appsDirectoryURL
    }

    class func fileURL(for app: AppProtocol) -> URL {
        let appURL = directoryURL(for: app).appendingPathComponent("App.app")
        return appURL
    }

    class func refreshedIPAURL(for app: AppProtocol) -> URL {
        let ipaURL = directoryURL(for: app).appendingPathComponent("Refreshed.ipa")
        print("`ipaURL`: \(ipaURL.absoluteString)")
        return ipaURL
    }

    class func directoryURL(for app: AppProtocol) -> URL {
        let directoryURL = InstalledApp.appsDirectoryURL.appendingPathComponent(app.bundleIdentifier)

        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil) } catch { print(error) }

        return directoryURL
    }

    class func installedAppUTI(forBundleIdentifier bundleIdentifier: String) -> String {
        let installedAppUTI = "io.altstore.Installed." + bundleIdentifier
        return installedAppUTI
    }

    class func installedBackupAppUTI(forBundleIdentifier bundleIdentifier: String) -> String {
        let installedBackupAppUTI = InstalledApp.installedAppUTI(forBundleIdentifier: bundleIdentifier) + ".backup"
        return installedBackupAppUTI
    }

    class func alternateIconURL(for app: AppProtocol) -> URL {
        let installedBackupAppUTI = directoryURL(for: app).appendingPathComponent("AltIcon.png")
        return installedBackupAppUTI
    }

    var directoryURL: URL {
        InstalledApp.directoryURL(for: self)
    }

    var fileURL: URL {
        InstalledApp.fileURL(for: self)
    }

    var refreshedIPAURL: URL {
        InstalledApp.refreshedIPAURL(for: self)
    }

    var installedAppUTI: String {
        InstalledApp.installedAppUTI(forBundleIdentifier: resignedBundleIdentifier)
    }

    var installedBackupAppUTI: String {
        InstalledApp.installedBackupAppUTI(forBundleIdentifier: resignedBundleIdentifier)
    }

    var alternateIconURL: URL {
        InstalledApp.alternateIconURL(for: self)
    }
}