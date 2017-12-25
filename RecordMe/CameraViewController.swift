//
//  CameraController.swift
//  Toastmasters
//
//  Created by Joseph Tobing on 12/19/17.
//  Copyright © 2017 Joseph Tobing. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    var timer: Timer!
    var totalTime = 60
    
    @IBOutlet private weak var timerLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        styleCaptureButton()
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        captureButton.isEnabled = false
        
        //Set up the video preview view.
        previewView.session = session
        
        /*
            Check video authorization status. Video access is required and audio
            access is optional. If audio access is denied, audio is not recorded
            during media recording.
        */
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                // The user has previously granted acess to the camera.
                break
            
            case .notDetermined:
                /*
                    The user has not yet been presented with the option to grant
                    video acess. We suspend the session queue to delay session
                    setup until the access request has completed.
     
                    Note that audio access will be implicitly requested when we
                    create an AVCaptureDeviceInput for audio during session setup.
                */
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted
                    in
                    if !granted {
                        self.setupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                })
            
            default:
                // The user has previously denied access
                setupResult = . notAuthorized
        }
        
        /*
            Setup the capture session.
            In general it is not safe to mutate an AVCaptureSession or any of its
            inputs, outputs, or connections from multiple threads at the same time.
 
            Why not do all of this in the main queue
            Because AVCaptureSession.startRunning is a blocking call which can
            take a long time. We dispatch session setup to the sessionQueue so
            that the main queue isn't blocked, which keeps the UI responsive.
        */
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult{
                case .success:
                    // Only setup observers and start the session running if setup succedded.
                    self.addObservers()
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "RecordMe doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "RecordMe", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "RecordMe", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    
    private var isSessionRunning = false
    
    private let sessionQueue = DispatchQueue(label: "session queue") // Communicate with the session and other session objects on this queue.
    
    private var setupResult: SessionSetupResult = .success
    
    var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    // Call this on the session queue.
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        /*
            We do not create an AVCaptureMovieFileOutput when setting up the session because the
            AVcaptureMevieFileOutput does not support movie recording with AVCaptureSession.Preset.Photo.
        */
        session.sessionPreset = .high
        
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the front only
            defaultVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                session.commitConfiguration()
                self.videoDeviceInput = videoDeviceInput
            } else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Could not create nideo device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add audio output.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
    }
    
    // MARK: Focus
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: GUI Button
    
    func styleCaptureButton() {
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.layer.borderWidth = 5
        
        captureButton.layer.cornerRadius = min(captureButton.frame.width, captureButton.frame.height) / 2
        
    }
    
    // MARK: Timer Functions
    
    func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateTime), userInfo: nil, repeats: true)
    }
    
    @objc func updateTime() {
        timerLabel.text = "\(timeFormatted(totalTime))"
        
        if totalTime != 0 {
            totalTime -= 1
        } else {
            endTimer()
        }
    }
    
    func endTimer() {
        timer.invalidate()
        performSegue(withIdentifier: "lastController", sender: nil)
    }
    
    func timeFormatted(_ totalSeconds: Int) -> String {
        let seconds: Int = totalSeconds
        return String(format: "%02d", seconds)
    }

    // MARK: Recording Movies
    
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    @IBOutlet weak var captureButton: UIButton!
    
    @IBAction func captureButton(_ sender: UIButton) {
            sender.flash()
            startTimer()
        
            /*
             Disable the Camera button until recording finishes, and disable
             the Record button until recording starts or finishes.
         
             See the AVCaptureFileOutputRecordingDelegate methods.
             */
            captureButton.isEnabled = false
        
            /*
             Retrieve the video preview layer's video orientation on the main queue
             before entering the session queue. We do this to ensure UI elements are
             accessed on the main thread and session configuration is done on the session queue.
             */
            let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
            sessionQueue.async {
                let movieFileOutput = AVCaptureMovieFileOutput()
                
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.beginConfiguration()
                    self.session.addOutput(movieFileOutput)
                    self.session.sessionPreset = .high
                    if let connection = movieFileOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    self.session.commitConfiguration()
                    
                    self.movieFileOutput = movieFileOutput
                    
                    DispatchQueue.main.async {
                        self.captureButton.isEnabled = true
                    }
                
                if !movieFileOutput.isRecording {
                    if UIDevice.current.isMultitaskingSupported {
                        /*
                         Setup background task.
                         This is needed because the `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)`
                         callback is not received until AVCam returns to the foreground unless you request background execution time.
                         This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                         To conclude this background execution, endBackgroundTask(_:) is called in
                         `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)` after the recorded file has been saved.
                         */
                        self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                    }
                    
                    // Update the orientation on the movie file output video connection before starting recording.
                    let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                    movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!
                    
                    let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                    
                    if availableVideoCodecTypes.contains(.hevc) {
                        movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                    }
                    
                    // Start recording to a temporary file.
                    let outputFileName = NSUUID().uuidString
                    let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                    movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
                } else {
                    movieFileOutput.stopRecording()
                }
            }
        }
    }
    
//        func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
//            // Enable the Record button to let the user stop the recording.
//            DispatchQueue.main.async {
//                self.captureButton.isEnabled = true
//                self.captureButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), for: [])
//            }
//        }
    
        func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
            /*
             Note that currentBackgroundRecordingID is used to end the background task
             associated with this recording. This allows a new recording to be started,
             associated with a new UIBackgroundTaskIdentifier, once the movie file output's
             `isRecording` property is back to false — which happens sometime after this method
             returns.
             
             Note: Since we use a unique file path for each recording, a new recording will
             not overwrite a recording currently being saved.
             */
            func cleanUp() {
                let path = outputFileURL.path
                if FileManager.default.fileExists(atPath: path) {
                    do {
                        try FileManager.default.removeItem(atPath: path)
                    } catch {
                        print("Could not remove file at url: \(outputFileURL)")
                    }
                }
                
                if let currentBackgroundRecordingID = backgroundRecordingID {
                    backgroundRecordingID = UIBackgroundTaskInvalid
                    
                    if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                        UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                    }
                }
            }
            
            var success = true
            
            if error != nil {
                print("Movie file finishing error: \(String(describing: error))")
                success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
            }
            
            if success {
                // Check authorization status.
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        // Save the movie file to the photo library and cleanup.
                        PHPhotoLibrary.shared().performChanges({
                            let options = PHAssetResourceCreationOptions()
                            options.shouldMoveFile = true
                            let creationRequest = PHAssetCreationRequest.forAsset()
                            creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                        }, completionHandler: { success, error in
                            if !success {
                                print("Could not save movie to photo library: \(String(describing: error))")
                            }
                            cleanUp()
                        }
                        )
                    } else {
                        cleanUp()
                    }
                }
            } else {
                cleanUp()
            }
        }
    
    // MARK: KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.captureButton.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionCount: Int {
        var uniqueDevicePositions: [AVCaptureDevice.Position] = []
        
        for device in devices {
            if !uniqueDevicePositions.contains(device.position) {
                uniqueDevicePositions.append(device.position)
            }
        }
    
        return uniqueDevicePositions.count
    }
}
