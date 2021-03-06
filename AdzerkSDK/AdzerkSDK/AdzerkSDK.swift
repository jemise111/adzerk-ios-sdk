//
//  AdzerkSDK.swift
//  AdzerkSDK
//
//  Created by Ben Scheirman on 8/10/15.
//  Copyright (c) 2015 Adzerk. All rights reserved.
//

import Foundation
import UIKit

// Update this when making changes. Will be sent in the UserAgent to identify the version of the SDK used in host applications.
var AdzerkSDKVersion: String {
    Bundle(for: AdzerkSDK.self).infoDictionary!["CFBundleShortVersionString"] as! String
}

public typealias ADZResponseSuccessCallback = (ADZPlacementResponse) -> ()
public typealias ADZResponseFailureCallback = (Int?, String?, Error?) -> ()
public typealias ADZResponseCallback = (Bool, Error?) -> ()
public typealias ADZUserDBUserResponseCallback = (ADZUser?, Error?) -> ()

/** The primary class used to make requests against the API. */
@objcMembers public class AdzerkSDK : NSObject {
 
    /** The base URL template to use for API requests. {subdomain} must be replaced in this template string before use. */
    private static let AdzerkHostnameTemplate = "{subdomain}.adzerk.net"
    
    private enum Endpoint: String {
        case decisionAPI = "/api/v2"
        case userDB = "/udb"
        
        private var path: String { rawValue }
        
        func baseURL(withHost host: String = AdzerkSDK.host) -> URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = path
            return components.url!
        }
    }
    
    private var queue: DispatchQueue
    private var logger = ADZLogger()

    private static var _host: String?
    
    /** The host to use for outgoing API requests. If not set, a default adzerk hostname will be
        used that is based on the default network ID. This must be set prior to making requests.
     
        Failing to set defaultNetworkID or host explicitly will result in a `fatalError`.
     
        Note that the defaultNetworkID-based subdomain will not change if a different networkID is
        supplied for a specific request.
     */
    public class var host: String! {
        get {
            if let hostOverride = _host {
                return hostOverride
            }
            
            guard let networkId = defaultNetworkId else {
                fatalError("You must set the defaultNetworkId or set a specific subdomain on `AdzerkSDK`")
            }
            let subdomain = "e-\(networkId)"
            return AdzerkHostnameTemplate.replacingOccurrences(of: "{subdomain}", with: subdomain)
        }
        set { _host = newValue }
    }
    
    private static var _defaultNetworkId: Int?
    /** Provides storage for the default network ID to be used with all placement requests. If a value is present here,
        each placement request does not need to provide it.  Any value in the placement request will override this value.
        Useful for the common case where the network ID is contstant for your application. */
    public class var defaultNetworkId: Int? {
        get { return _defaultNetworkId }
        set { _defaultNetworkId = newValue }
    }
    
    private static var _defaultSiteId: Int?
    /** Provides storage for the default site ID to be used with all placement requests. If a value is present here,
        each placement request does not need to provide it.  Any value in the placement request will override this value.
        Useful for the common case where the network ID is contstant for your application.
        */
    public class var defaultSiteId: Int? {
        get { return _defaultSiteId }
        set { _defaultSiteId = newValue }
    }
    
    /** Setter for defaultNetworkId. Provided for Objective-C compatibility. */
    public class func setDefaultNetworkId(_ networkId: Int) {
        defaultNetworkId = networkId
    }
    
    /** Setter for defaultSiteId. Provided for Objective-C compatibility. */
    public class func setDefaultSiteId(_ siteId: Int) {
        defaultSiteId = siteId
    }
    
    /** The class used to save & retrieve the user DB key. */
    let keyStore: ADZUserKeyStore
    
    /** Initializes a new instance of `AdzerkSDK` with a keychain-based userKeyStore.
    */
    public convenience override init() {
        self.init(userKeyStore: ADZKeychainUserKeyStore(), queue: nil)
    }
    
    /** Initializes a new instance of `AdzerkSDK`.
        @param userKeyStore provide a value for this if you want to customize the way user keys are stored & retrieved. The default is `ADZKeychainUserKeyStore`.
    */
    public init(userKeyStore: ADZUserKeyStore, queue: DispatchQueue? = nil) {
        self.keyStore = userKeyStore
        self.queue = queue ?? DispatchQueue.main
    }
    
    /** Requests placements with explicit success and failure callbacks. Provided for Objective-C compatibility.
        See `requestPlacements:options:completion` for complete documentation.
    */
    public func requestPlacements(_ placements: [ADZPlacement], options: ADZPlacementRequestOptions? = nil,
        success: @escaping (ADZPlacementResponse) -> (),
        failure: @escaping (Int, String?, NSError?) -> ()) {
        
        requestPlacements(placements, options: options) { response in
            switch response {
            case .success(let placementResponse):
                success(placementResponse)
            case .badRequest(let statusCode, let body):
                failure(statusCode, body, nil)
            case .badResponse(let body):
                failure(0, body, nil)
            case .error(let error):
                failure(0, nil, error as NSError)
            }
        }
    }
    
    /** Requests a single placement using only required parameters. This method is a convenience over the other placement request methods.
        @param div the div name to request
        @param adTypes an array of integers representing the ad types to request. The full list can be found at https://github.com/adzerk/adzerk-api/wiki/Ad-Types .
        @completion a callback block that you provide to handle the response. The block will be given an `ADZResponse` object.
    */
    public func requestPlacementInDiv(_ div: String, adTypes: [Int], completion: @escaping (ADZResponse) -> ()) {
        if let placement = ADZPlacement(divName: div, adTypes: adTypes) {
            requestPlacement(placement, completion: completion)
        }
    }

    /** Requests a single placement.
        @param placement the placement details to request
        @param completion a callback block that you provide to handle the response. The block will be given an `ADZResponse` object.
    */
    public func requestPlacement(_ placement: ADZPlacement, completion: @escaping (ADZResponse) -> ()) {
       requestPlacements([placement], completion: completion)
    }

    /** Requests multiple placements.
        @param placements an array of placement details to request
        @param completion a callback block that you provide to handle the response. The block will be given an `ADZResponse` object.
    */
    public func requestPlacements(_ placements: [ADZPlacement], completion: @escaping (ADZResponse) -> ()) {
        requestPlacements(placements, options: nil, completion: completion)
    }
 
    /** Requests multiple placements with additional options. The options can provide well-known or arbitrary parameters to th eoverall request.
        @param placements an array of placement details to request
        @param options an optional instance of `ADZPlacementRequestOptions` that provide top-level attributes to the request
        @param completion a callback block that you provide to handle the response. The block will be given an `ADZResponse` object.
    */
    public func requestPlacements(_ placements: [ADZPlacement], options: ADZPlacementRequestOptions?, completion: @escaping (ADZResponse) -> ()) {
        if let request = buildPlacementRequest(placements, options: options) {
            let task = session.dataTask(with: request) {
                data, response, error in
                
                if let error = error {
                    self.queue.async {
                        completion(.error(error))
                    }
                } else {
                    let http = response as! HTTPURLResponse
                    guard let data = data else {
                        self.queue.async {
                            completion(.badResponse("<no response>"))
                        }
                        return
                    }
                    
                    if http.statusCode == 200 {
                        if let resp = self.buildPlacementResponse(data) {
                            self.logger.debug("Response: \(String(data: data, encoding: .utf8) ?? "<no response>"))")
                            self.queue.async {
                                completion(ADZResponse.success(resp))
                            }
                        } else {
                            let bodyString = (String(data: data, encoding: .utf8)) ?? "<no body>"
                            self.queue.async {
                                completion(ADZResponse.badResponse(bodyString))
                            }
                        }
                    } else {
                        let bodyString = (String(data: data, encoding: .utf8)) ?? "<no body>"
                        self.queue.async {
                            completion(.badRequest(http.statusCode, bodyString))
                        }
                    }
                }
                
            }
            task.resume()
        }
    }
    
    // MARK - UserDB endpoints
    
    /** Posts custom properties for a user.
        @param userKey a string identifying the user. If nil, the value will be fetched from the configured UserKeyStore.
        @param properties a JSON serializable dictionary of properties to send to the UserDB endpoint.
        @param callback a simple callback block indicating success or failure, along with an optional `NSError`.
    */
    public func postUserProperties(_ userKey: String?, properties: [String : Any], callback: @escaping ADZResponseCallback) {
        guard let networkId = AdzerkSDK.defaultNetworkId else {
            logger.warn("WARNING: No defaultNetworkId set.")
            callback(false, nil)
            return
        }
    
        guard let actualUserKey = userKey ?? keyStore.currentUserKey() else {
            logger.warn("WARNING: No userKey specified, and none can be found in the configured key store.")
            callback(false, nil)
            return
        }
        
        postUserProperties(networkId, userKey: actualUserKey, properties: properties, callback: callback)
    }
    
    /** Posts custom properties for a user.
    @param networkId the networkId for this request
    @param userKey a string identifying the user
    @param properties a JSON serializable dictionary of properties to send to the UserDB endpoint.
    @param callback a simple callback block indicating success or failure, along with an optional `NSError`.
    */
    public func postUserProperties(_ networkId: Int, userKey: String, properties: [String : Any], callback: @escaping ADZResponseCallback) {
        guard let url = Endpoint.userDB.baseURL().appending(pathComponent: "\(networkId)/custom", queryItems: [
            URLQueryItem(name: "userKey", value: userKey)
        ]) else {
            logger.warn("WARNING: Could not build URL with provided params. Network ID: \(networkId), userKey: \(userKey)")
            callback(false, nil)
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: properties, options: JSONSerialization.WritingOptions.prettyPrinted)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = data
            
            let task = session.dataTask(with: request) {
                (data, response, error) in
                if error == nil {
                    let http = response as! HTTPURLResponse
                    if http.statusCode == 200 {
                        callback(true, nil)
                    } else {
                        self.logger.debug("Received HTTP \(http.statusCode) from \(String(describing: request.url))")
                        callback(false, nil)
                    }
                } else {
                    callback(false, error)
                }
            }
            task.resume()
        }
        catch let exc as NSException {
            logger.warn("WARNING: Could not serialize the submitted properties into JSON: \(properties).")
            logger.warn("\(exc.name) -> \(exc.reason ?? "<no reason>")")
            callback(false, nil)
        }
        catch let error as NSError {
            callback(false, error)
        }
    }
    
    /** Returns the UserDB data for a given user.
    @param userKey a string identifying the user
    @param callback a simple callback block indicating success or failure, along with an optional `NSError`.
    */
    public func readUser(_ userKey: String?, callback: @escaping ADZUserDBUserResponseCallback) {
        guard let networkId = AdzerkSDK.defaultNetworkId else {
            logger.warn("WARNING: No defaultNetworkId set.")
            callback(nil, nil)
            return
        }
        
        guard let actualUserKey = userKey ?? keyStore.currentUserKey() else {
            logger.warn("WARNING: No userKey specified, and none can be found in the configured key store.")
            callback(nil, nil)
            return
        }
        
        readUser(networkId, userKey: actualUserKey, callback: callback)
    }
    
    /** Returns the UserDB data for a given user.
    @param networkId the networkId to use for this request
    @param userKey a string identifying the user
    @param callback a simple callback block indicating success or failure, along with an optional `NSError`.
    */
    public func readUser(_ networkId: Int, userKey: String, callback: @escaping ADZUserDBUserResponseCallback) {
        guard let url = Endpoint.userDB.baseURL().appending(pathComponent: "\(networkId)/read", queryItems: [
            URLQueryItem(name: "userKey", value: userKey)
        ]) else {
            logger.warn("WARNING: Could not build URL with provided params. Network ID: \(networkId), userKey: \(userKey)")
            callback(nil, nil)
            return
        }
        
        let request = URLRequest(url: url)
        let task = session.dataTask(with: request) {
            (data, response, error) in
            if error == nil {
                let http = response as! HTTPURLResponse
                if http.statusCode == 200 {
                    do {
                        if let userDictionary = try JSONSerialization.jsonObject(with: data!, options: [.allowFragments]) as? [String: AnyObject] {
                            if let user = ADZUser(dictionary: userDictionary) {
                                callback(user, nil)
                            } else {
                                self.logger.warn("WARNING: could not recognize json format: \(userDictionary)")
                                callback(nil, nil)
                            }
                        } else {
                            self.logger.warn("WARNING: response did not contain valid json.")
                            callback(nil, error)
                        }
                    } catch let exc as NSException {
                        self.logger.error("WARNING: error parsing JSON: \(exc.name) -> \(String(describing: exc.reason))")
                        callback(nil, nil)
                    } catch let e as NSError {
                        let body = String(data: data!, encoding: String.Encoding.utf8)
                        self.logger.error("response: \(String(describing: body))")
                        callback(nil, e)
                    }
                } else {
                    self.logger.debug("Received HTTP \(http.statusCode) from \(String(describing: request.url))")
                    let body = String(data: data!, encoding: String.Encoding.utf8)
                    self.logger.debug("response: \(String(describing: body))")
                    callback(nil, nil)
                }
            } else {
                callback(nil, error)
            }
        }
        task.resume()
    }
    
    /**
    Adds an interest for a user to UserDB.
    @param userKey the current user key. If nil, the saved userKey from the configured userKeyStore is used.
    @param callback a simple success/error callback to use when the response comes back
    */
    public func addUserInterest(_ interest: String, userKey: String?, callback: @escaping ADZResponseCallback) {
        guard let networkId = AdzerkSDK.defaultNetworkId else {
            logger.warn("WARNING: No defaultNetworkId set.")
            callback(false, nil)
            return
        }
        
        guard let actualUserKey = userKey ?? keyStore.currentUserKey() else {
            logger.warn("WARNING: No userKey specified, and none can be found in the configured key store.")
            callback(false, nil)
            return
        }
        
        addUserInterest(interest, networkId: networkId, userKey: actualUserKey, callback: callback)
    }

    /**
    Adds an interest for a user to UserDB.
    @param interest an interest keyword to add for this user
    @param networkId the network ID for this action
    @param userKey the user to add the interest for
    @param callback a simple success/error callback to use when the response comes back
    */
    public func addUserInterest(_ interest: String, networkId: Int, userKey: String, callback: @escaping ADZResponseCallback) {
        let params = [
            "userKey": userKey,
            "interest": interest
        ]
        pixelRequest(networkId, action: "interest", params: params, callback: callback)
    }

    /**
    Opt a user out of tracking. Uses the `defaultNetworkId` set on `AdzerkSDK`.
    @param userKey the user to opt out. If nil, the saved userKey from the configured userKeyStore is used.
    @param callback a simple success/error callback to use when the response comes back
    */
    public func optOut(_ userKey: String?, callback: @escaping ADZResponseCallback) {
        guard let networkId = AdzerkSDK.defaultNetworkId else {
            logger.warn("WARNING: No defaultNetworkId set.")
            callback(false, nil)
            return
        }
        
        guard let actualUserKey = userKey ?? keyStore.currentUserKey() else {
            logger.warn("WARNING: No userKey specified, and none can be found in the configured key store.")
            callback(false, nil)
            return
        }

        optOut(networkId, userKey: actualUserKey, callback: callback)
    }

    /**
    Opt a user out of tracking.
    @param networkId the network ID for this action
    @param userKey the user to opt out
    @param callback a simple success/error callback to use when the response comes back
    */
    public func optOut(_ networkId: Int, userKey: String, callback: @escaping ADZResponseCallback) {
        let params = [
            "userKey": userKey
        ]
        pixelRequest(networkId, action: "optout", params: params, callback: callback)
    }
    
    /** Retargets a user to a new segment.
    @param userKey the user to opt out
    @param brandId the brand this retargeting is for
    @param segmentId the segment the user is targeted to
    @param callback a simple success/error callback to use when the response comes back
    */
    public func retargetUser(_ userKey: String?, brandId: Int, segmentId: Int, callback: @escaping ADZResponseCallback) {
        guard let networkId = AdzerkSDK.defaultNetworkId else {
            logger.warn("WARNING: No defaultNetworkId set.")
            callback(false, nil)
            return
        }
        
        guard let actualUserKey = userKey ?? keyStore.currentUserKey() else {
            logger.warn("WARNING: No userKey specified, and none can be found in the configured key store.")
            callback(false, nil)
            return
        }

        retargetUser(networkId, userKey: actualUserKey, brandId: brandId, segmentId: segmentId, callback: callback)
    }

    /** Retargets a user to a new segment.
    @param networkId the network ID for this request
    @param userKey the user to opt out
    @param brandId the brand this retargeting is for
    @param segmentId the segment the user is targeted to
    @param callback a simple success/error callback to use when the response comes back
    */
    public func retargetUser(_ networkId: Int, userKey: String, brandId: Int, segmentId: Int, callback: @escaping ADZResponseCallback) {
        let params = [
            "userKey": userKey
        ]
        let action = "rt/\(brandId)/\(segmentId)"
        pixelRequest(networkId, action: action, params: params, callback: callback)
    }
    
    /**
        Sends a request to record an impression. This is a fire-and-forget request, the response is ignored.
        @param url a valid URL retrieved from an ADZPlacementDecision
    */
    public func recordImpression(_ url: URL) {
        
        let request = URLRequest(url: url)
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Error recording impression: \(error)")
            } else {
                // impression recorded
            }
        }
        task.resume()
    }

    // MARK - private
    
    /** 
        Makes a simple pixel request to perform an action. The response image is ignored.
        @param networkId the network ID for this action
        @param action the action to take, which becomes part of the path
        @param params the params for the action. Most of these require `userKey` at a minimum
        @param callback a simple success/error callback to use when the response comes back
    */
    func pixelRequest(_ networkId: Int, action: String, params: [String: String]?, callback: @escaping ADZResponseCallback) {
        let queryItems = params?.map { (k, v) in URLQueryItem.init(name: k, value: v) } ?? []
        guard let url = Endpoint.userDB.baseURL().appending(pathComponent: "\(networkId)/\(action)/i.gif", queryItems: queryItems) else {
            logger.warn("WARNING: Could not construct proper URL for params: \(params ?? [:])")
            callback(false, nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = [ "Content-Type": "" ] // image request, not json
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                callback(false, error)
            } else {
                let http = response as! HTTPURLResponse
                if http.statusCode == 200 {
                    callback(true, nil)
                } else {
                    self.logger.debug("Received HTTP \(http.statusCode) from \(request.url!)")
                    if let data = data, let body = String(data: data, encoding: String.Encoding.utf8) {
                        self.logger.debug("Response: \(body)")
                    }
                    callback(false, nil)
                }
            }
        }
        task.resume()
    }
    
    lazy var sessionConfiguration: URLSessionConfiguration = {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "User-Agent" : UserAgentProvider.instance.userAgent,
            "X-Adzerk-Sdk-Version": "adzerk-decision-sdk-ios:\(AdzerkSDKVersion)",
            "Content-Type" : "application/json",
            "Accept" : "application/json"
        ]
        return config
    }()
    
    lazy var session: URLSession = {
        return URLSession(configuration: self.sessionConfiguration)
    }()
    
    private let requestTimeout: TimeInterval = 15
    
    private func buildPlacementRequest(_ placements: [ADZPlacement], options: ADZPlacementRequestOptions?) -> URLRequest? {
        let url = Endpoint.decisionAPI.baseURL()
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        
        var body: [String: Any] = [
            "placements": placements.map { $0.serialize() },
            "time": Int(Date().timeIntervalSince1970)
        ]
        
        if let userKey = options?.userKey {
            body["user"] = ["key": userKey]
        } else if let savedUserKey = keyStore.currentUserKey() {
            body["user"] = ["key": savedUserKey]
        }
        
        if let blockedCreatives = options?.blockedCreatives {
            body["blockedCreatives"] = blockedCreatives
        }
        
        if let flighViewTimes = options?.flightViewTimes {
            body["flightViewTimes"] = flighViewTimes
        }
        
        if let keywords = options?.keywords {
            body["keywords"] = keywords
        }
        
        if let url = options?.url {
            body["url"] = url
        }
        
        if let consent = options?.consent {
            body["consent"] = consent.toJSONDictionary()
        }
        
        if let additionalOptions = options?.additionalOptions {
            for (key, val) in additionalOptions {
                body[key] = val
            }
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
            request.httpBody = data
            logger.debug("Posting JSON: \(NSString(data: data, encoding: String.Encoding.utf8.rawValue)!)")
            return request
        } catch let error as NSError {
            logger.error("Error building placement request: \(error)")
            return nil
        }
    }
    
    private func buildPlacementResponse(_ data: Data) -> ADZPlacementResponse? {
        do {
            let responseDictionary = try JSONSerialization.jsonObject(with: data, options: []) as! [String: AnyObject]
            saveUserKey(responseDictionary)
            return ADZPlacementResponse(dictionary: responseDictionary)
        } catch {
            logger.error("couldn't parse response as JSON")
            return nil
        }
    }
    
    private func saveUserKey(_ response: [String: AnyObject]) {
        if let userSection = response["user"] as? [String: AnyObject] {
            if let userKey = userSection["key"] as? String {
                keyStore.saveUserKey(userKey)
            }
        }
    }
}

fileprivate extension URL {
    func appending(pathComponent: String, queryItems: [URLQueryItem]?) -> URL? {
        guard var components = URLComponents(url: appendingPathComponent(pathComponent), resolvingAgainstBaseURL: true) else {
            return nil
        }
        
        components.queryItems = queryItems
        return components.url
    }
}

// This provider object constructs the user agent only once, and is used repeatedly.
fileprivate struct UserAgentProvider {
    static var instance = UserAgentProvider()
    
    private init() {
    }
    
    lazy var userAgent: String  = {
        var string = "AdzerkSDK/\(AdzerkSDKVersion)"
        let mainBundle = Bundle.main
        
        if let bundleName = mainBundle.object(forInfoDictionaryKey: "CFBundleName"),
            let bundleVersion = mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") {
            
            let deviceName = self.deviceModelName
            let osVersion = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
            string.append("  (\(bundleName)/\(bundleVersion) - \(deviceName)/\(osVersion)   )")
        }
        
        return string
    }()
    
    var deviceModelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    
        // Reference for future updates to this list: https://github.com/pluwen/Apple-Device-Model-list
        switch identifier {
        case "iPod5,1":                                 return "iPod Touch 5"
        case "iPod7,1":                                 return "iPod Touch 6"
        case "iPhone3,1", "iPhone3,2", "iPhone3,3":     return "iPhone 4"
        case "iPhone4,1":                               return "iPhone 4s"
        case "iPhone5,1", "iPhone5,2":                  return "iPhone 5"
        case "iPhone5,3", "iPhone5,4":                  return "iPhone 5c"
        case "iPhone6,1", "iPhone6,2":                  return "iPhone 5s"
        case "iPhone7,2":                               return "iPhone 6"
        case "iPhone7,1":                               return "iPhone 6 Plus"
        case "iPhone8,1":                               return "iPhone 6s"
        case "iPhone8,2":                               return "iPhone 6s Plus"
        case "iPhone9,1", "iPhone9,3":                  return "iPhone 7"
        case "iPhone9,2", "iPhone9,4":                  return "iPhone 7 Plus"
        case "iPhone8,4":                               return "iPhone SE"
        case "iPhone10,1", "iPhone10,4":                return "iPhone 8"
        case "iPhone10,2", "iPhone10,5":                return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6":                return "iPhone X"
        case "iPhone11,8":                              return "iPhone Xr"
        case "iPhone11,2":                              return "iPhone XS"
        case "iPhone11,4":                              return "iPhone XS Max"
        case "iPhone12,1":                              return "iPhone 11"
        case "iPhone12,3":                              return "iPhone 11 Pro"
        case "iPhone12,5":                              return "iPhone 11 Pro Max"
        case "iPhone12,8":                              return "iPhone SE 2"
            
        case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4":return "iPad 2"
        case "iPad3,1", "iPad3,2", "iPad3,3":           return "iPad 3"
        case "iPad3,4", "iPad3,5", "iPad3,6":           return "iPad 4"
        case "iPad4,1", "iPad4,2", "iPad4,3":           return "iPad Air"
        case "iPad5,3", "iPad5,4":                      return "iPad Air 2"
        case "iPad6,11", "iPad6,12":                    return "iPad 5"
        case "iPad2,5", "iPad2,6", "iPad2,7":           return "iPad Mini"
        case "iPad4,4", "iPad4,5", "iPad4,6":           return "iPad Mini 2"
        case "iPad4,7", "iPad4,8", "iPad4,9":           return "iPad Mini 3"
        case "iPad5,1", "iPad5,2":                      return "iPad Mini 4"
        case "iPad6,3", "iPad6,4":                      return "iPad Pro 9.7 Inch"
        case "iPad6,7", "iPad6,8":                      return "iPad Pro 12.9 Inch"
        case "iPad7,1", "iPad7,2":                      return "iPad Pro 12.9 Inch 2"
        case "iPad7,3", "iPad7,4":                      return "iPad Pro 10.5 Inch"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": return "iPad Pro 11-inch"
        case "iPad8,9", "iPad8,10":                      return "iPad Pro 11-inch 2"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": return "iPad Pro 12.9-inch 3"
        case "iPad8,11", "iPad8,12":                     return "iPad Pro 12.9-inch 4"

        case "AppleTV5,3":                              return "Apple TV"
        case "AppleTV6,2":                              return "Apple TV 4K"
        case "AudioAccessory1,1":                       return "HomePod"
        case "i386", "x86_64":                          return "Simulator"
        default:                                        return identifier
        }
    }
}
