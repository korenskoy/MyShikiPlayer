//
//  MyShikiPlayerApp.swift
//  MyShikiPlayer
//
//  Created by Anton Korenskoy on 07.04.2026.
//

import SwiftUI

@main
@MainActor
struct MyShikiPlayerApp: App {
    @StateObject private var shikimoriAuth = ShikimoriAuthController()

    var body: some Scene {
        Window("MyShikiPlayer", id: "main") {
            ContentView()
                .environmentObject(shikimoriAuth)
        }
        .handlesExternalEvents(matching: ["*"])
    }
}
