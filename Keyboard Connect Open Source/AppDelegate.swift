//
//  AppDelegate.swift
//  Keyboard Connect Open Source
//
//  Created by Arthur Yidi on 4/11/16.
//  Copyright © 2016 Arthur Yidi. All rights reserved.
//

import AppKit
import Foundation
import IOBluetooth

func myCGEventTapCallBack(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let btKey = UnsafeMutableRawPointer(refcon!).load(as: BTKeyboard.self)
    
    switch type {
    case .keyUp:
        if let nsEvent = NSEvent(cgEvent: event) {
            btKey.sendKey(vkeyCode: -1, nsEvent.modifierFlags.rawValue)
        }
        break
    case .keyDown:
        if let nsEvent = NSEvent(cgEvent: event) {
            btKey.sendKey(vkeyCode: Int(nsEvent.keyCode), nsEvent.modifierFlags.rawValue)
        }
        break
    default:
        break
    }

    return Unmanaged.passUnretained(event)
}

var btKey: BTKeyboard?
var statusItem: NSStatusItem?
var connected: Bool = false

class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func buttonAction() {
        if !connected { self.connect() }
    }
    
    func connect() {
        btKey = BTKeyboard()

        if !AXIsProcessTrusted() {
            print("Enable accessibility setting to read keyboard events.")
        }

        // capture all key events
        var eventMask: CGEventMask = 0
        eventMask |= (1 << CGEventMask(CGEventType.keyUp.rawValue))
        eventMask |= (1 << CGEventMask(CGEventType.keyDown.rawValue))
        eventMask |= (1 << CGEventMask(CGEventType.flagsChanged.rawValue))

        if let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                            place: .headInsertEventTap,
                                            options: CGEventTapOptions.defaultTap,
                                            eventsOfInterest: eventMask,
                                            callback: myCGEventTapCallBack,
                                            userInfo: &btKey) {
            connected = true

            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let itemImage = NSImage(named: "keyboard")
        itemImage?.isTemplate = true
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = itemImage
        statusItem?.button?.action = #selector(buttonAction)
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        print("Will terminate...")

        btKey?.terminate()
    }
}
