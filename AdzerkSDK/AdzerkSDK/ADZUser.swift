//
//  ADZUser.swift
//  AdzerkSDK
//
//  Created by Ben Scheirman on 9/11/15.
//  Copyright © 2015 Adzerk. All rights reserved.
//

import Foundation

/** 
    Contains the information known about a user in UserDB. Returned
    by calling `readUser` on `AdzerSDK`.
*/
public class ADZUser : NSObject {
    @objc public let userKey: String!
    @objc public let blockedItems: [String: AnyObject]!
    @objc public let interests: [String]!
    @objc public let customProperties: [String: AnyObject]!
    @objc public let optOut: Bool
    
    init?(dictionary: [String: AnyObject]) {
        guard let
            key = dictionary["key"] as? String,
            let blockedItems = dictionary["blockedItems"] as? [String: AnyObject],
            let interests = dictionary["interests"] as? [String],
            let customProperties = dictionary["custom"] as? [String: AnyObject],
            let optOut = dictionary["optOut"] as? NSNumber
            else {
                self.userKey = ""
                self.blockedItems = [:]
                self.interests = []
                self.customProperties = [:]
                self.optOut = false
            super.init()
            return nil
        }
        
        self.userKey = key
        self.blockedItems = blockedItems
        self.interests = interests
        self.customProperties = customProperties
        self.optOut = optOut.boolValue
        super.init()
    }
}
