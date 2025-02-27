import Cocoa
import CoreAudio
import AudioToolbox

var alreadyListening: Set<AudioObjectID> = Set()

extension UserDefaults {
    @objc dynamic var showPercentage: Bool {
        get {
            return bool(forKey: "showPercentage")
        }
        set {
            set(newValue, forKey: "showPercentage")
        }
    }
    @objc dynamic var showIcon: Bool {
        get {
            return bool(forKey: "showIcon") || !bool(forKey: "showIconKeyExists")
        }
        set {
            set(newValue, forKey: "showIcon")
            set(true, forKey: "showIconKeyExists")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var showPercentage: Bool = UserDefaults.standard.showPercentage
    private var showIcon: Bool = UserDefaults.standard.showIcon
    private var showPercentageMenuItem: NSMenuItem!
    private var showIconMenuItem: NSMenuItem!

    func addListener(onAudioObjectID: AudioObjectID, forPropertyAddress: AudioObjectPropertyAddress, fn: @escaping (AudioObjectPropertyAddress) -> Void) {
        var fp = forPropertyAddress
        let listener = listenerFor(selector: fp.mSelector, fn: fn)
        let result = AudioObjectAddPropertyListenerBlock(onAudioObjectID, &fp, nil, listener)
        if (result != kAudioHardwareNoError) {
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
        var muted = UInt32()
        var mutedSize = UInt32(MemoryLayout.size(ofValue: muted))
        var mutedPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        let mutedResult = AudioObjectGetPropertyData(deviceID, &mutedPropertyAddress, 0, nil, &mutedSize, &muted)
        if (mutedResult != kAudioHardwareNoError) {
            print("Error getting device volume")
        }
        if (muted == 1) {
            return 0.0
        }
        
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
        if (alreadyListening.contains(deviceID)) {
            print("already listening for volume changes for \(deviceID)")
            return
        }

        print("adding listener for \(deviceID)")
        alreadyListening.insert(deviceID)

        let muteListener = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        addListener(
            onAudioObjectID: deviceID,
            forPropertyAddress: muteListener,
            fn: onVolumeChange
        )

        // we can query kAudioHardwareServiceDeviceProperty_VirtualMainVolume, but not listen to it
        // also sometimes devices change whether they have a main volmue
        // (e.g. starting to listen to the mic on bluetooth headphones)
        // so just listen to all three, I guess
        let mainChannelVolumeProperty = AudioObjectPropertyAddress(
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
        addListener(
            onAudioObjectID: deviceID,
            forPropertyAddress: mainChannelVolumeProperty,
            fn: onVolumeChange
        )
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

    func fourCharCodeToString(_ code: UInt32) -> String {
        return String(format: "%c%c%c%c",
            (code >> 24) & 0xFF,
            (code >> 16) & 0xFF,
            (code >> 8) & 0xFF,
            code & 0xFF)
    }

    func debugListAllPropertyChanges(deviceID: AudioObjectID) {
        let listener: AudioObjectPropertyListenerBlock = { (inNumberAddresses, inAddresses) in
            let addresses = UnsafeBufferPointer(start: inAddresses, count: Int(inNumberAddresses))
            for address in addresses {
                print("Property changed:")
                print("  Selector: \(self.fourCharCodeToString(address.mSelector)) (\(address.mSelector))")
                print("  Scope: \(self.fourCharCodeToString(address.mScope)) (\(address.mScope))")
                print("  Element: \(address.mElement)")
            }
            print("------")
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertySelectorWildcard,
            mScope: kAudioObjectPropertyScopeWildcard,
            mElement: kAudioObjectPropertyElementWildcard)

        let result = AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, listener)
        if result != kAudioHardwareNoError {
            print("Error setting up debug listener: \(result)")
        }
    }

    
    func onDeviceChange(prop: AudioObjectPropertyAddress) {
        let deviceID = getDefaultAudioOutputDevice()
        addVolumeListenerForDevice(deviceID: deviceID)
        updateIcon()
    }
    
    func onVolumeChange(prop: AudioObjectPropertyAddress) {
        updateIcon()
    }
    
    func updateIcon() {
        let deviceID = getDefaultAudioOutputDevice()
        print("kAudioHardwarePropertyDefaultOutputDevice: \(deviceID)")
        let volume = getDeviceVolume(deviceID: deviceID)
        print("volume: \(volume)")

        var image: NSImage
        if (volume == 0) {
            image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "mute")!
        } else if #available(macOS 13.0, *) {
            image = NSImage(systemSymbolName: "speaker.wave.3.fill", variableValue: Double(volume), accessibilityDescription: "volume \(volume * 100)%")!
        } else if (volume < 0.33) {
            image = NSImage(systemSymbolName: "speaker.wave.1.fill", accessibilityDescription: "volume 33%")!
        } else if (volume < 0.66) {
            image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "volume 66%")!
        } else {
            image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "volume 100%")!
        }
        DispatchQueue.main.async {
            if (self.showPercentage) {
                let volumeText = String(format: "%.0f%%", volume * 100)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.menuBarFont(ofSize: 11) // Claude claims this is what Apple uses for theirs
                ]
                let attributedString = NSAttributedString(string: volumeText, attributes: attributes)
                self.statusItem.button?.attributedTitle = attributedString
            } else {
                self.statusItem.button?.attributedTitle = NSAttributedString(string: "")
            }
            self.statusItem.button?.image = image
            self.statusItem.button?.image = self.showIcon ? image : nil

            // avoid the possibility of disabling both
            self.showPercentageMenuItem.isEnabled = self.showIcon
            self.showIconMenuItem.isEnabled = self.showPercentage
        }
    }
    
    private var statusItem: NSStatusItem!
    
    @IBAction func openURL(_ sender: AnyObject) {
        let url = URL(string: "https://github.com/bakkot/MenuBarVolume")!
        NSWorkspace.shared.open(url)
    }

    @objc func toggleShowPercentage() {
        showPercentage = !showPercentage
        UserDefaults.standard.showPercentage = showPercentage
        showPercentageMenuItem.state = showPercentage ? .on : .off
        updateIcon()
    }

    @objc func toggleShowIcon() {
        showIcon = !showIcon
        UserDefaults.standard.showIcon = showIcon
        showIconMenuItem.state = showIcon ? .on : .off
        updateIcon()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(NSMenuItem(title: "About MenuBarVolume", action: #selector(openURL), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        showPercentageMenuItem = NSMenuItem(
            title: "Show Percentage",
            action: #selector(toggleShowPercentage),
            keyEquivalent: "")
        showPercentageMenuItem.state = showPercentage ? .on : .off
        menu.addItem(showPercentageMenuItem)
        showIconMenuItem = NSMenuItem(
            title: "Show Icon",
            action: #selector(toggleShowIcon),
            keyEquivalent: "")
        showIconMenuItem.state = showIcon ? .on : .off
        menu.addItem(showIconMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.menu = menu
        self.statusItem.button?.imagePosition = NSControl.ImagePosition.imageRight

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

        // debugListAllPropertyChanges(deviceID: mainDevice)
        updateIcon()
    }
}
