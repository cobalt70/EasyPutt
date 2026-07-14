//
//  AppDelegate.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 2/25/25.
//


import SwiftUI
import ARKit

//@main
//struct EasyPuttApp: App {
//  
//    @StateObject private var arViewModel = ARViewModel() // 앱 진입점에서 초기화
//
//    var body: some Scene {
//        WindowGroup {
////            ContentView()
////                .environmentObject(arViewModel) // 최상위 뷰에서 environmentObject로 설정
//            ContentView2()
//                .environmentObject(arViewModel)
//        }
//    }
//}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
 
    var window: UIWindow?
 //   private var arViewModel = ARViewModel()
//    var arSession: ARSession?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Create the SwiftUI view that provides the window contents.
        let contentView =   ContentView2()
            //.environmentObject(arViewModel)

        // Use a UIHostingController as window root view controller.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
         
    }


}

