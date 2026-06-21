//
//  ZeusApp.swift
//  Zeus
//
//  Created by tomtomtom on 6/19/26.
//
//  Composition root: builds the shared SettingsStore + HubDataStore once and injects them into
//  both the main constellation window and the Settings scene (so edits in Settings drive the
//  same store the Hub observes).
//

import SwiftUI
import ZeusUI

@main
struct ZeusApp: App {
    @State private var settings: SettingsStore
    @State private var hubData: HubDataStore

    init() {
        let settingsStore = SettingsStore(store: AppComposition.makeSettingsStore())
        _settings = State(initialValue: settingsStore)
        _hubData = State(initialValue: AppComposition.makeHubStore(settings: settingsStore))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(hubData: hubData, settings: settings)
        }
        .defaultSize(width: 1320, height: 860)

        Settings {
            RootsSettingsView(store: settings)
        }
    }
}
