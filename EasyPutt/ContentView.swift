//
//  ContentView.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 2/28/25.
//

import SwiftUI
import RealityKit
import ARKit
import simd

struct ContentView: View {
    @StateObject var arViewModel: ARViewModel = ARViewModel()
 
    var body: some View{
        ZStack{
            ARViewControllerRepresentable()
                .environmentObject(arViewModel)
                .edgesIgnoringSafeArea(.all)
            Image(systemName: "viewfinder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.orange) // 주황색으로 설정
                            .allowsHitTesting(false)
                            .scaleEffect(x: 0.5, y: 1.0) 
        }
        .safeAreaInset(edge: .bottom){
            HStack{
                Button(action: {
                    // 버튼 클릭 시 실행할 코드
                    var point : CGPoint = .zero
                    point.x = UIScreen.main.bounds.midX
                    point.y = UIScreen.main.bounds.midY
                    if let arView = arViewModel.arView {
                        findRaycastResult(for: arView, point: point)
                    }
                    print("삭제")
                }) {
                    Text("Delete")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                   
                   
                }
                .frame(maxWidth: .infinity) //
            }
        }
        .padding(.bottom, 0)
        .background(Color.clear)
    }
}

// MARK: - UIViewControllerRepresentable을 사용한 ARView 관리
struct ARViewControllerRepresentable: UIViewControllerRepresentable {
    
    @EnvironmentObject var arViewModel: ARViewModel
    
    public class Coordinator: NSObject, ARSessionDelegate {
        public var arViewController: ARViewController
        init(arViewController: ARViewController) {
            self.arViewController = arViewController
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            print("session frame didupdate")
            updateRealPointPosition(frame: frame)
            
        }
        
        func updateRealPointPosition(frame: ARFrame) {
            let cameraTransform = frame.camera.transform
            arViewController.targetPoint = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
            print("targetPoint:", arViewController.targetPoint)
        }
        
       func session(_ session: ARSession, didFailWithError error: Error) {
            print("Session failed: \(error.localizedDescription)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("Session was interrupted")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("Session interruption ended")
        }
        
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .notAvailable:
                print("Tracking not available")
            case .limited(let reason):
                print("Tracking limited: \(reason)")
            case .normal:
                print("Tracking normal")
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        // sigleton 으로 유일한 ARViewController.shared 를 참조한다.
        return Coordinator(arViewController: ARViewController(arViewModel: arViewModel))
    }
    
    func makeUIViewController(context: Context) -> ARViewController {
        //        let viewController = ARViewController.shared
        //        viewController.arView.session.delegate = context.coordinator
        //        return viewController(arViewModel: arViewModel)
        return ARViewController(arViewModel: arViewModel)
    }
    
    func updateUIViewController(_ uiViewController: ARViewController, context: Context) {
        print("\(Date()) updateUIViewController")
    }
}

// MARK: - ARView를 포함하는 UIViewController
class ARViewController: UIViewController, ARSessionDelegate {
 
    //   static let shared = ARViewController() // Singleton으로 관리
    
    var arView: ARView!
    var arViewModel: ARViewModel
    
    var targetPoint = SIMD3<Float>(0.0, 0.0, 0.0)
    init(arViewModel: ARViewModel) {
        self.arViewModel = arViewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupARView()
    }
    
    private func setupARView() {
    
        arView = arViewModel.arView
        arView.session.delegate = self
        view.addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                    arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    arView.topAnchor.constraint(equalTo: view.topAnchor),
                    arView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
        
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = []
        arView.session.run(configuration)
    }
}

#Preview {
    ContentView()
}
