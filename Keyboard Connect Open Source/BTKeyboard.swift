//
//  BTKeyboard.swift
//  Keyboard Connect
//
//  Created by Arthur Yidi on 4/11/16.
//  Copyright © 2016 Arthur Yidi. All rights reserved.
//

import AppKit
import Foundation
import IOBluetooth

enum BTMessageType: UInt8 {
    case Handshake = 0,
         HIDControl
    case GetReport = 4,
         SetReport,
         GetProtocol,
         SetProtocol
    case Data = 0xA
}

enum BTHandshake: UInt8 {
    case Successful = 0,
         NotReady,
         ErrInvalidReport,
         ErrUnsupportedRequest,
         ErrInvalidParameter
    case ErrUnknown = 0xE
    case ErrFatal = 0xF
}

enum BTHIDControl: UInt8 {
    case Suspend = 3,
         ExitSuspend,
         VirtualCableUnplug
}

struct BTChannels {
    static let Control = BluetoothL2CAPPSM(kBluetoothL2CAPPSMHIDControl)
    static let Interrupt = BluetoothL2CAPPSM(kBluetoothL2CAPPSMHIDInterrupt)
}

private class CallbackWrapper: IOBluetoothDeviceAsyncCallbacks {
    var callback: ((_ device: IOBluetoothDevice?, _ status: IOReturn) -> Void)? = nil
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        if let callback = self.callback {
            callback(device, status)
        }
    }
    @objc func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
}

class BTDevice {
    var device: IOBluetoothDevice?
    var interruptChannel: IOBluetoothL2CAPChannel?
    var controlChannel: IOBluetoothL2CAPChannel?
}

class BTKeyboard: IOBluetoothL2CAPChannelDelegate {
    var curDevice: BTDevice?
    var service: IOBluetoothSDPServiceRecord?

    init() {
        let bluetoothHost = IOBluetoothHostController()

        // Detect if bluetooth is on using: bluetoothHost.powerState

        // Make the computer look like a keyboard device
        // 1 00101 010000 00
        // 3 21098 765432 10
        // Minor Device Class - Keyboard
        // Major Device Class - Peripheral
        // Limited Discoverable Mode
        bluetoothHost.setClassOfDevice(0x002540, forTimeInterval: 60)

        // Bluetooth SDP Service
        let dictPath = Bundle.main.path(forResource:"SerialPortDictionary", ofType: "plist")
        let sdpDict = NSDictionary.init(contentsOfFile: dictPath!)! as Dictionary<NSObject, AnyObject>
        service = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: sdpDict)

        // Open Channels for Incoming Connections
        guard IOBluetoothL2CAPChannel
            .register(forChannelOpenNotifications: self,
                                                 selector: #selector(newL2CAPChannelOpened),
                                                 withPSM: BTChannels.Control,
                                                 direction: kIOBluetoothUserNotificationChannelDirectionIncoming) != nil else
        {
            print("failed to register: \(BTChannels.Control)")
            return
        }
        guard IOBluetoothL2CAPChannel
            .register(forChannelOpenNotifications: self,
                                                 selector: #selector(newL2CAPChannelOpened),
                                                 withPSM: BTChannels.Interrupt,
                                                 direction: kIOBluetoothUserNotificationChannelDirectionIncoming) != nil else
        {
            print("failed to registered: \(BTChannels.Interrupt)")
            return
        }
    }

    func setupDevice(device: IOBluetoothDevice) -> Bool {
        var didfail = true
        var deviceWrapper = BTDevice()
        deviceWrapper.device = device
        self.curDevice = deviceWrapper

        guard device.openL2CAPChannelSync(&deviceWrapper.controlChannel, withPSM: BTChannels.Control, delegate: self) == kIOReturnSuccess else
        { return didfail }

        defer {
            if didfail { deviceWrapper.controlChannel?.close() }
        }

        guard device.openL2CAPChannelSync(&deviceWrapper.interruptChannel, withPSM: BTChannels.Interrupt, delegate: self) == kIOReturnSuccess else
        { return didfail }

        didfail = false
        return didfail
    }

    private func sendBytes(channel: IOBluetoothL2CAPChannel, _ bytes: [UInt8]) {
        let ioError = channel.writeAsync(UnsafeMutablePointer<UInt8>(mutating: bytes), length: UInt16(bytes.count), refcon: nil)

        if ioError != kIOReturnSuccess {
            print("Buff Data Failed \(channel.psm)")
        }
    }

    func sendHandshake(channel: IOBluetoothL2CAPChannel, _ status: BTHandshake) {
        guard channel.psm == BTChannels.Control else {
            print("Passing wrong channel to handshake")
            return
        }
        sendBytes(channel: channel, [0x0 | status.rawValue])
    }

    func sendData(bytes: [UInt8]) {
        if let interruptChannel = curDevice?.interruptChannel {
            sendBytes(channel: interruptChannel, bytes)
        }
    }


    func hidReport(keyCode: UInt8, _ modifier: UInt8) -> [UInt8] {
        let bytes: [UInt8] = [
            0xA1,      // 0 DATA | INPUT (HIDP Bluetooth)

            0x01,      // 0 Report ID
            modifier,  // 1 Modifier Keys
            0x00,      // 2 Reserved
            keyCode,   // 3 Keys ( 6 keys can be held at the same time )
            0x00,      // 4
            0x00,      // 5
            0x00,      // 6
            0x00,      // 7
            0x00,      // 8
            0x00       // 9
        ]

        return bytes
    }

    /**
     Sends a key by converting virtual key codes to HID key codes

     - Parameters:
     - vkeyCode: virtual keycode provided by NSEvent
     - modifierRawValue: raw modifier provided by NSEvent
     */
    func sendKey(vkeyCode: Int, _ modifierRawValue: UInt) {
        let keyCode = UInt8(virtualKeyCodeToHIDKeyCode(vKeyCode: vkeyCode))

        let vmodifier = NSEvent.ModifierFlags(rawValue: modifierRawValue)
        var modifier: UInt8 = 0

        if vmodifier.contains(NSEvent.ModifierFlags.command) {
            modifier |= (1 << 3)
        }
        if vmodifier.contains(NSEvent.ModifierFlags.option) {
            modifier |= (1 << 2)
        }
        if vmodifier.contains(NSEvent.ModifierFlags.shift) {
            modifier |= (1 << 1)
        }
        if vmodifier.contains(NSEvent.ModifierFlags.control) {
            modifier |= 1
        }

        sendData(bytes: hidReport(keyCode: keyCode, modifier))
    }

    func terminate() {
        curDevice?.device?.closeConnection()
    }

    @objc private func l2capChannelData(channel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafePointer<UInt8>, length dataLength: Int) {
        let data = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>?(dataPointer), count:dataLength)

        if channel.psm == BTChannels.Control {
            guard data.count > 0 else
            { return }

            guard let messageType = BTMessageType(rawValue: data[0] >> 4) else
            { return }

            switch messageType {
            case .Handshake:
                return
            case .HIDControl:
                channel.device.closeConnection()
            case .SetReport:
                sendHandshake(channel: channel, .Successful)
            case .SetProtocol:
                sendHandshake(channel: channel, .Successful)
            default:
                return
            }
        }
    }

    @objc func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        if !setupDevice(device: channel.device) { return }

        switch channel.psm {
        case BTChannels.Control:
            curDevice?.controlChannel = channel
            break
        case BTChannels.Interrupt:
            curDevice?.interruptChannel = channel
            break
        default:
            return
        }
    }

    @objc func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {

    }

    @objc private func l2capChannelWriteComplete(channel: IOBluetoothL2CAPChannel!, refcon: UnsafeMutableRawPointer, status error: IOReturn) {

    }

    @objc func newL2CAPChannelOpened(notification: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        channel.setDelegate(self)
    }
}
