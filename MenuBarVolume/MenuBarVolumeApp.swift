//
//  MenuBarVolumeApp.swift
//  MenuBarVolume
//
//  Created by Kevin on 9/21/22.
//

import SwiftUI
import CoreAudio
import AudioToolbox

var alreadyListening: Set<AudioObjectID> = Set()

@main
struct MenuBarVolumeApp: App {
    func addListener(onAudioObjectID: AudioObjectID, forPropertyAddress: AudioObjectPropertyAddress, fn: @escaping (AudioObjectPropertyAddress) -> Void) {
        var fp = forPropertyAddress
        let listener = listenerFor(selector: fp.mSelector, fn: fn)
        let result = AudioObjectAddPropertyListenerBlock(onAudioObjectID, &fp, nil, listener)
        if (result != kAudioHardwareNoError) {
            // TODO something better than that
            print("Error calling AudioObjectAddPropertyListenerBlock")
        }
    }

    func listenerFor(selector: AudioObjectPropertySelector, fn: @escaping (AudioObjectPropertyAddress) -> Void) -> AudioObjectPropertyListenerBlock {
        func propertyChangedListener(numberAddresses: UInt32, propertyAddresses: UnsafePointer<AudioObjectPropertyAddress>) {
            // print("listener: got \(numberAddresses) property addresses")
            var index: Int = 0
            
            while index < numberAddresses {
                let address: AudioObjectPropertyAddress = propertyAddresses[index]
                switch address.mSelector {
                case selector:
                    fn(address)
                default:
                    print("Unexpected AudioObjectPropertyAddress \(address.mSelector)")
                }
                index += 1
            }
        }
        return propertyChangedListener
    }

    func getDefaultAudioOutputDevice() -> AudioObjectID {
        var devicePropertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout.size(ofValue: deviceID))
        let systemObjectID = AudioObjectID(bitPattern: kAudioObjectSystemObject)
        let result = AudioObjectGetPropertyData(systemObjectID, &devicePropertyAddress, 0, nil, &dataSize, &deviceID)
        if (result != kAudioHardwareNoError) {
            print("Error getting default device")
            return 0
        }
        return deviceID
    }
    
    func getDeviceVolume(deviceID: AudioObjectID) -> Float32 {
        var volume = Float32(0.0)
        var volumeSize = UInt32(MemoryLayout.size(ofValue: volume))

        var volumePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        let result = AudioObjectGetPropertyData(deviceID, &volumePropertyAddress, 0, nil, &volumeSize, &volume)
        if (result != kAudioHardwareNoError) {
            print("Error getting device volume")
        }
        return volume
    }
    
    func addVolumeListenerForDevice(deviceID: AudioObjectID) {
        print("adding listener for \(deviceID)")
        alreadyListening.insert(deviceID)
        // we can query kAudioHardwareServiceDeviceProperty_VirtualMainVolume, but not listen to it
        // so we want to listen to the main channel if it's available, otherwise the left and right channels
        var mainChannelVolumeProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        let leftChannelVolumeProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 1) // 1 is left channel, apparently
        let rightChannelVolumeProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 2) // 2 is right channel, apparently
        if (AudioObjectHasProperty(deviceID, &mainChannelVolumeProperty)) {
            addListener(
                onAudioObjectID: deviceID,
                forPropertyAddress: mainChannelVolumeProperty,
                fn: onVolumeChange
            )
        } else {
            addListener(
                onAudioObjectID: deviceID,
                forPropertyAddress: leftChannelVolumeProperty,
                fn: onVolumeChange
            )
            addListener(
                onAudioObjectID: deviceID,
                forPropertyAddress: rightChannelVolumeProperty,
                fn: onVolumeChange
            )
        }
    }


    func onDeviceChange(prop: AudioObjectPropertyAddress) {
        let deviceID = getDefaultAudioOutputDevice()
        if (alreadyListening.contains(deviceID)) {
            print("already listening for volume changes for \(deviceID)")
            return
        }
        addVolumeListenerForDevice(deviceID: deviceID)
    }

    func onVolumeChange(prop: AudioObjectPropertyAddress) {
        let deviceID = getDefaultAudioOutputDevice()
        print("xx kAudioHardwarePropertyDefaultOutputDevice: \(deviceID)")
        print("xx volume: \(getDeviceVolume(deviceID: deviceID))")
    }

    init() {
        // add listener for default audio device changing

        addListener(
            onAudioObjectID: AudioObjectID(bitPattern: kAudioObjectSystemObject),
            forPropertyAddress: AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain),
            fn: onDeviceChange
        )
        
        // add listener for current device
        let mainDevice = getDefaultAudioOutputDevice()
        addVolumeListenerForDevice(deviceID: mainDevice)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
