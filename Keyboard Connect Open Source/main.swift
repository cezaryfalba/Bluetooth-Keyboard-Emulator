//
//  main.swift
//  Keyboard Connect
//
//  Created by Arthur Yidi on 4/11/16.
//  Copyright © 2016 Arthur Yidi. All rights reserved.
//

import Cocoa

func main(arguments: [String]?) {
    let application = NSApplication.shared
    let delegate = AppDelegate()

    application.delegate = delegate

    func quit(signal: Int32) {
        NSApplication.shared.terminate(NSNumber(value: signal))
    }

    signal(SIGHUP, quit)
    signal(SIGINT, quit)
    signal(SIGTERM, quit)
    signal(SIGQUIT, quit)
    
    application.run()
}

main(arguments: Process().arguments)
