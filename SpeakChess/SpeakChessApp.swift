//
//  SpeakChessApp.swift
//  SpeakChess
//
//  Created by Cade Harger on 4/14/26.
//

import SwiftUI

@main
struct SpeakChessApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
