//
//  HKTAccessoryAccess.swift
//  HomeKitTester
//
//  Created by Wai Man Chan on 3/21/17.
//  Copyright © 2017 Wai Man Chan. All rights reserved.
//

import HomeKit

let HKTAccessoryTestProgressName = Notification.Name.init("HKTAccessoryTestProgressStr")
enum HKTAccessoryTestProgress: String {
    case start = "Test Starting";
    case bonjour = "Looking for Bonjour";
    case pairing = "Pairing";
    case unpairing = "Unpairing";
    case ioTesting = "Testing I/O";
    case identify = "Identifying"
    case notify = "Test Notify";
    case stop = "Done";
    case fail = "Test fail";
    case child = "Testing bridged child";
    case offReachability = "Turn it off to Test Reachability"
    case onReachability = "Turn it on to Test Reachability"
    case save = "Saved"
}

func accessCharacteristic(accessory: HMAccessory, serviceType: String, characteristicType: String)->[HMCharacteristic] {
    let services = accessory.services.filter({ $0.serviceType == serviceType })
    if services.count > 0 {
        return services.flatMap({$0.characteristics}).filter({$0.characteristicType == characteristicType})
    } else { return [] }
}

func accessFirstCharacteristic(accessory: HMAccessory, serviceType: String, characteristicType: String)->HMCharacteristic? {
    let services = accessory.services.filter({ $0.serviceType == serviceType })
    if services.count > 0 {
        return services.flatMap({$0.characteristics}).filter({$0.characteristicType == characteristicType}).first
    } else { return nil }
}

func accessAllCharacteristic(accessory: HMAccessory)->[HMCharacteristic] {
    return accessory.services.flatMap({$0.characteristics})
}

extension String {
    func capLen(maxLength: Int)->String {
        let length = (self as NSString).length
        let len = (length > maxLength) ? maxLength: length
        return (self as NSString).substring(to: len-1)
    }
}

func generateRandomValue(charType: HMCharacteristicMetadata?)->Any {
    switch charType!.format! {
    case HMCharacteristicMetadataFormatBool:
        return arc4random()%2>0
    case HMCharacteristicMetadataFormatInt, HMCharacteristicMetadataFormatFloat, HMCharacteristicMetadataFormatUInt16, HMCharacteristicMetadataFormatUInt32, HMCharacteristicMetadataFormatUInt64:
        let maxStep = UInt32((charType!.maximumValue!.doubleValue - charType!.minimumValue!.doubleValue)/(charType!.stepValue!.doubleValue))
        let targetStep = arc4random()%maxStep
        let value = charType!.minimumValue!.doubleValue + charType!.stepValue!.doubleValue * Double(targetStep)
        return value
    case HMCharacteristicMetadataFormatString:
        return Date().debugDescription.capLen(maxLength: charType!.maxLength!.intValue)
        break
    default:
        return 0
    }
}

let HKTNotificationChange = Notification.Name("NotificationChange")
let testQueue = OperationQueue.init()

func valueTest(valA: Any, valB: Any)->Bool {
    if let objA = valA as? AnyObject, let objB = valB as? AnyObject, objA === objB {
        return true
    } else { return false }
}
func testCharacteristic(characteristic: HMCharacteristic, record: HKTRecorderManager) {
    let readable = characteristic.properties.contains(HMCharacteristicPropertyReadable)
    let writable = characteristic.properties.contains(HMCharacteristicPropertyWritable)
    let notifyable = characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification)
    var notificating = false
    
    var lastOpTime: Date = Date()
    
    let charStr = characteristic.debugDescription
    
    let seamphore = DispatchSemaphore(value: 1)
    
    let charUUID = characteristic.uniqueIdentifier.uuidString
    
    //Wait for 10 seconds for notification
    let maxTimeout = DispatchTimeInterval.seconds(10)
    
    var noNotifyBeforeFail = 0
    
    //Read old value
    var oldValue = 0 as Any
    if (readable) { characteristic.readValue { (error: Error?) in
        if let error = error {
            submitError(errorMsg: "Read error: "+error.localizedDescription)
        }
        seamphore.signal()
        } }
    
    if (notifyable && writable) {
        seamphore.wait()
        characteristic.enableNotification(true, completionHandler: { (error: Error?) in
            if let error = error {
                submitError(errorMsg: "Setup notification error: "+error.localizedDescription)
            } else {
                notificating = true
                submitSummary(summaryMsg: "Setup notification "+charUUID)
            }
            seamphore.signal()
        })
        seamphore.wait()
        /*if (notificating) {
            //Await the dispatch to send the notification
            NotificationCenter.default.addObserver(forName: HKTNotificationChange, object: characteristic, queue: testQueue, using: { (notify: Notification) in
                if (notificating) {
                    //We are still testing notification
                    //Calculate the time different
                    let timeDiff = lastOpTime.timeIntervalSinceNow
                    noNotifyBeforeFail += 1
                    //Release
                    seamphore.signal()
                    submitBenchmark(objUUID: characteristic.uniqueIdentifier, type: "Notify-RoundTrip", value: timeDiff, recorder: record)
                    if valueTest(valA: oldValue, valB: characteristic.value!) {
                        submitError(errorMsg: charUUID+": Notification return wrong value")
                    }
                }
            })
        }*/
    }
    
    for i in 0 ..< 1000 {
        let newValue = generateRandomValue(charType: characteristic.metadata)
        if (writable) {
            seamphore.wait()
            lastOpTime = Date()
            characteristic.writeValue(newValue, completionHandler: { (error: Error?) in
                if let error = error {
                    submitError(errorMsg: "Write error: "+error.localizedDescription)
                } else {
                    oldValue = newValue
                    //Report the time used
                    let timeDiff = lastOpTime.timeIntervalSinceNow * -1.0
                    submitBenchmark(objUUID: characteristic.uniqueIdentifier, type: "Write-RoundTrip", value: timeDiff, recorder: record)
                }
                //if (!notificating) {
                    seamphore.signal()
                //}
            }) }
        if (readable) {
            
            /*if (notificating && writable ) {
                if seamphore.wait(timeout: DispatchTime.now() + maxTimeout) == .timedOut {
                    //We are doing notification, so we should move on if the notification failed
                    //Waited too long for notification, so stop
                    notificating = false
                    //Report the fault
                    submitError(errorMsg: charUUID+": Notification Stop working at "+noNotifyBeforeFail.description)
                }
            } else {
                //We are not doing notification, so wait till the write is in*/
                seamphore.wait()
            
            lastOpTime = Date()
            characteristic.readValue { (error: Error?) in
                if let error = error {
                    submitError(errorMsg: "Read error: "+error.localizedDescription)
                } else {
                    //Report the time used
                    let timeDiff = lastOpTime.timeIntervalSinceNow * -1.0
                    submitBenchmark(objUUID: characteristic.uniqueIdentifier, type: "Read-RoundTrip", value: timeDiff, recorder: record)
                }
                seamphore.signal()
            }
        }
    }
    if (notifyable) {
        submitSummary(summaryMsg: charUUID+": Notification Round "+noNotifyBeforeFail.description)
    }
}

class HTKAccessoryTest: NSObject, HMAccessoryDelegate {
    var lastReachabilityChange: Date!
    let waitForReachability = DispatchSemaphore(value: 0)
    
    let record = HKTRecorderManager()
    
    var bonjour: HKTBonjourSeek? = nil
    
    var modelAgainst: HKTAccessoryModel!
    
    var currentHome: HMHome!
    
    func testAccessory(accessory: HMAccessory, home: HMHome) {
        currentHome = home
        
        NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.start)
        
        setRecorder(recorder: record)
        //Setup model
        modelAgainst = HKTAccessoryModel(accessory: accessory)
        //Seek IP
        NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.bonjour)
        bonjour = HKTBonjourSeek(targetStr: accessory.name) { (test: HKTBonjourTest) in
            test.setModel(targetModel: self.modelAgainst)
            
            NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.identify)
            accessory.identify(completionHandler: { (error: Error?) in
                if error == nil {
                    submitSummary(summaryMsg: "Identify Success without pairing")
                } else {
                    submitError(errorMsg: "Identify Fail without pairing")
                }
                NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.pairing)
                home.addAccessory(accessory) { (error: Error?) in
                    if error == nil {
                        
                        //Report the setting
                        for service in accessory.services {
                            submitSummary(summaryMsg: "Service "+service.serviceType+" "+service.uniqueIdentifier.uuidString)
                            for chara in service.characteristics {
                                submitSummary(summaryMsg: "Characteristic "+chara.characteristicType+" "+chara.uniqueIdentifier.uuidString)
                            }
                        }
                        
                        NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.identify)
                        accessory.identify(completionHandler: { (error: Error?) in
                            if error == nil {
                                submitSummary(summaryMsg: "Identify Success with pairing")
                            } else {
                                submitError(errorMsg: "Identify Fail with pairing")
                            }
                        })
                        
                        self.modelAgainst.paired = true
                        testQueue.addOperation {
                            sleep(1)
                            NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.ioTesting)
                            self._testAccessory(accessory: accessory, complete: {
                                //Afterward, clean up
                                NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.unpairing)
                                home.removeAccessory(accessory, completionHandler: { _ in
                                    if error != nil {
                                        submitError(errorMsg: "Unpair fail")
                                    } else {
                                        self.modelAgainst.paired = false
                                        NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.identify)
                                        accessory.identify(completionHandler: { (error: Error?) in
                                            if error == nil {
                                                submitSummary(summaryMsg: "Identify Success after unpairing")
                                            } else {
                                                submitError(errorMsg: "Identify Fail after unpairing")
                                            }
                                        })
                                    }
                                    
                                })
                                NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.stop)
                                self.record.save()
                            })
                        }
                        
                    } else {
                        self.modelAgainst.paired = false
                        NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.fail)
                    }
                }
            })
            
        }
        
    }
    func _testAccessory(accessory: HMAccessory, child: Bool = false, complete:@escaping ()->Void) {
        //Setup notification
        accessory.delegate = self
        //Get a snapshot of characteristic
        let characteristic = accessAllCharacteristic(accessory: accessory)
        //Test the first draft
        let testOperations: [BlockOperation]
        testOperations = characteristic.map { (char: HMCharacteristic) in
            return BlockOperation.init(block: { testCharacteristic(characteristic: char, record: self.record) })
        }
        testQueue.addOperations(testOperations, waitUntilFinished: child)
        
        let followupBlock = {
            //If bridge, ask to change configuration
            if (!child) { promptManualInteraction(title: "Bridge?", detail: "If this is a bridge accessory, please setup the test scenairo before pressing oksy")
                if let childUUID = accessory.uniqueIdentifiersForBridgedAccessories, childUUID.count > 0 {
                    NotificationCenter.default.post(name: HKTAccessoryTestProgressName, object: HKTAccessoryTestProgress.child)
                    //Bridged, so test child
                    let accessories = self.currentHome.accessories
                    for tUUID in childUUID {
                        //Get home
                        if let acc = accessories.filter({ $0.uniqueIdentifier == tUUID }).first {
                            //Test the child
                            self._testAccessory(accessory: acc, child: true, complete: {})
                        } else {
                            submitError(errorMsg: "Accessory "+tUUID.uuidString+" missing")
                        }
                    }
                }
            }
            complete()
        }
        if !child {
            let followupBlockOP = BlockOperation.init(block: followupBlock)
            for op in testOperations {
                followupBlockOP.addDependency(op)
            }
            testQueue.addOperation(followupBlockOP)
        } else {
            followupBlock()
        }
        
    }
    func accessoryDidUpdateServices(_ accessory: HMAccessory) {
        
    }
    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        waitForReachability.signal()
    }
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        submitSummary(summaryMsg: "Got notification "+characteristic.uniqueIdentifier.uuidString)
    }
}
