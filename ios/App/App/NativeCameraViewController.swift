import UIKit
import AVFoundation

enum CameraMode {
    case photo, video
}

class NativeCameraViewController: UIViewController {

    // MARK: - Public

    var initialMode: CameraMode = .video
    var onCapture: ((URL, String, Double) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Capture

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var videoOutput: AVCaptureMovieFileOutput!
    private var photoOutput: AVCapturePhotoOutput!
    private var currentDevice: AVCaptureDevice?
    private var cameraPosition: AVCaptureDevice.Position = .back

    // MARK: - State

    private var mode: CameraMode = .video
    private var isRecording = false
    private var torchOn = false
    private var recordingStart: Date?
    private var displayLink: CADisplayLink?

    // MARK: - UI

    private let closeBtn = UIButton(type: .system)
    private let flashBtn = UIButton(type: .system)
    private let flipBtn = UIButton(type: .system)
    private let captureBtn = UIButton(type: .custom)
    private let captureRing = UIView()
    private let captureInner = UIView()
    private let modePhoto = UIButton(type: .system)
    private let modeVideo = UIButton(type: .system)
    private let timerLabel = UILabel()
    private let focusView = UIView()
    private let uploadBtn = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        mode = initialMode
        setupSession()
        setupPreview()
        setupUI()
        setupGestures()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
        displayLink?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - Session Setup

    private func setupSession() {
        session.beginConfiguration()

        // Best available preset
        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        // Video input
        if let cam = bestCamera(for: .back) {
            currentDevice = cam
            configure60fps(cam)
            if let input = try? AVCaptureDeviceInput(device: cam),
               session.canAddInput(input) {
                session.addInput(input)
            }
        }

        // Audio input
        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input) {
            session.addInput(input)
        }

        // Video file output
        videoOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            if let conn = videoOutput.connection(with: .video),
               conn.isVideoStabilizationSupported {
                conn.preferredVideoStabilizationMode = .cinematic
            }
        }

        // Photo output
        photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            if #available(iOS 16.0, *) {
                photoOutput.maxPhotoDimensions = currentDevice?.activeFormat.supportedMaxPhotoDimensions.last
                    ?? CMVideoDimensions(width: 4032, height: 3024)
            }
        }

        session.commitConfiguration()
    }

    private func bestCamera(for pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera,
            .builtInDualCamera, .builtInWideAngleCamera,
        ]
        for type in types {
            if let d = AVCaptureDevice.default(type, for: .video, position: pos) { return d }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func configure60fps(_ device: AVCaptureDevice) {
        var best: (AVCaptureDevice.Format, AVFrameRateRange)?
        for fmt in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            for r in fmt.videoSupportedFrameRateRanges where r.maxFrameRate >= 60 {
                if best == nil || d.width > CMVideoFormatDescriptionGetDimensions(best!.0.formatDescription).width {
                    best = (fmt, r)
                }
            }
        }
        // Fallback: highest fps at 1080p+
        if best == nil {
            for fmt in device.formats {
                let d = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                guard d.width >= 1920 else { continue }
                for r in fmt.videoSupportedFrameRateRanges {
                    if best == nil || r.maxFrameRate > best!.1.maxFrameRate {
                        best = (fmt, r)
                    }
                }
            }
        }
        guard let (fmt, range) = best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = fmt
            let fps = min(range.maxFrameRate, 60)
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Preview

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    // MARK: - UI

    private func setupUI() {
        let safe = view.safeAreaLayoutGuide

        // Close button
        closeBtn.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeBtn)

        // Flash button
        updateFlashIcon()
        flashBtn.tintColor = .white
        flashBtn.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        flashBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flashBtn)

        // Flip button
        flipBtn.setImage(UIImage(systemName: "camera.rotate.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)), for: .normal)
        flipBtn.tintColor = .white
        flipBtn.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        flipBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flipBtn)

        // Timer label
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        timerLabel.textAlignment = .center
        timerLabel.isHidden = true
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerLabel)

        // Mode toggle
        modePhoto.setTitle("Photo", for: .normal)
        modeVideo.setTitle("Video", for: .normal)
        modePhoto.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        modeVideo.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        modePhoto.addTarget(self, action: #selector(switchToPhoto), for: .touchUpInside)
        modeVideo.addTarget(self, action: #selector(switchToVideo), for: .touchUpInside)
        modePhoto.translatesAutoresizingMaskIntoConstraints = false
        modeVideo.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modePhoto)
        view.addSubview(modeVideo)
        updateModeUI()

        // Capture button (ring + inner)
        captureRing.layer.borderColor = UIColor.white.cgColor
        captureRing.layer.borderWidth = 4
        captureRing.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureRing)

        captureInner.translatesAutoresizingMaskIntoConstraints = false
        captureRing.addSubview(captureInner)
        updateCaptureButtonStyle()

        captureBtn.translatesAutoresizingMaskIntoConstraints = false
        captureBtn.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureBtn)

        // Focus indicator
        focusView.layer.borderColor = UIColor.yellow.cgColor
        focusView.layer.borderWidth = 1.5
        focusView.alpha = 0
        focusView.isUserInteractionEnabled = false
        view.addSubview(focusView)

        // Layout
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            closeBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeBtn.widthAnchor.constraint(equalToConstant: 44),
            closeBtn.heightAnchor.constraint(equalToConstant: 44),

            flashBtn.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            flashBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            flashBtn.widthAnchor.constraint(equalToConstant: 44),
            flashBtn.heightAnchor.constraint(equalToConstant: 44),

            flipBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            flipBtn.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            flipBtn.widthAnchor.constraint(equalToConstant: 44),
            flipBtn.heightAnchor.constraint(equalToConstant: 44),

            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 18),

            modePhoto.bottomAnchor.constraint(equalTo: captureRing.topAnchor, constant: -24),
            modePhoto.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -12),

            modeVideo.bottomAnchor.constraint(equalTo: captureRing.topAnchor, constant: -24),
            modeVideo.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 12),

            captureRing.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureRing.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -40),
            captureRing.widthAnchor.constraint(equalToConstant: 76),
            captureRing.heightAnchor.constraint(equalToConstant: 76),

            captureInner.centerXAnchor.constraint(equalTo: captureRing.centerXAnchor),
            captureInner.centerYAnchor.constraint(equalTo: captureRing.centerYAnchor),
            captureInner.widthAnchor.constraint(equalToConstant: 60),
            captureInner.heightAnchor.constraint(equalToConstant: 60),

            captureBtn.centerXAnchor.constraint(equalTo: captureRing.centerXAnchor),
            captureBtn.centerYAnchor.constraint(equalTo: captureRing.centerYAnchor),
            captureBtn.widthAnchor.constraint(equalToConstant: 76),
            captureBtn.heightAnchor.constraint(equalToConstant: 76),
        ])

        captureRing.layer.cornerRadius = 38
        captureInner.layer.cornerRadius = 30
    }

    private func updateCaptureButtonStyle() {
        if mode == .photo {
            captureInner.backgroundColor = .white
        } else {
            captureInner.backgroundColor = UIColor(red: 1, green: 0.22, blue: 0.19, alpha: 1)
        }
    }

    private func updateModeUI() {
        let active = UIColor.white
        let inactive = UIColor.white.withAlphaComponent(0.45)
        modePhoto.setTitleColor(mode == .photo ? active : inactive, for: .normal)
        modeVideo.setTitleColor(mode == .video ? active : inactive, for: .normal)
    }

    private func updateFlashIcon() {
        let name = torchOn ? "bolt.fill" : "bolt.slash.fill"
        flashBtn.setImage(UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
    }

    // MARK: - Gestures

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapFocus(_:)))
        view.addGestureRecognizer(tap)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = currentDevice else { return }
        switch gesture.state {
        case .changed:
            do {
                try device.lockForConfiguration()
                let zoom = max(1, min(device.activeFormat.videoMaxZoomFactor, device.videoZoomFactor * gesture.scale))
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
                gesture.scale = 1
            } catch {}
        default: break
        }
    }

    @objc private func handleTapFocus(_ gesture: UITapGestureRecognizer) {
        guard let device = currentDevice else { return }
        let point = gesture.location(in: view)
        let converted = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = converted
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = converted
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {}

        // Show focus indicator
        focusView.frame = CGRect(x: 0, y: 0, width: 70, height: 70)
        focusView.center = point
        focusView.alpha = 1
        focusView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.25, animations: {
            self.focusView.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.5, delay: 0.5) {
                self.focusView.alpha = 0
            }
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        if isRecording { stopRecording() }
        dismiss(animated: true) { [weak self] in
            self?.onCancel?()
        }
    }

    @objc private func flashTapped() {
        torchOn.toggle()
        updateFlashIcon()
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    @objc private func flipTapped() {
        let newPos: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        guard let newCam = bestCamera(for: newPos),
              let newInput = try? AVCaptureDeviceInput(device: newCam) else { return }

        session.beginConfiguration()
        // Remove old video input
        for input in session.inputs {
            if let devInput = input as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                session.removeInput(devInput)
            }
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
        }
        // Re-apply stabilization
        if let conn = videoOutput.connection(with: .video),
           conn.isVideoStabilizationSupported {
            conn.preferredVideoStabilizationMode = .cinematic
        }
        session.commitConfiguration()

        cameraPosition = newPos
        currentDevice = newCam
        configure60fps(newCam)

        // Mirror front camera
        if let conn = previewLayer.connection {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = newPos == .front
        }
    }

    @objc private func switchToPhoto() {
        guard mode != .photo else { return }
        mode = .photo
        updateModeUI()
        updateCaptureButtonStyle()
    }

    @objc private func switchToVideo() {
        guard mode != .video else { return }
        mode = .video
        updateModeUI()
        updateCaptureButtonStyle()
    }

    @objc private func captureTapped() {
        if mode == .photo {
            takePhoto()
        } else {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }
    }

    // MARK: - Video Recording

    private func startRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("pulse-\(Int(Date().timeIntervalSince1970)).mp4")
        videoOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        recordingStart = Date()

        // Animate button to square
        UIView.animate(withDuration: 0.2) {
            self.captureInner.layer.cornerRadius = 8
            self.captureInner.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }

        // Show timer
        timerLabel.text = "0:00"
        timerLabel.isHidden = false
        displayLink = CADisplayLink(target: self, selector: #selector(updateTimer))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 2)
        displayLink?.add(to: .main, forMode: .common)

        // Hide mode toggle
        modePhoto.isHidden = true
        modeVideo.isHidden = true
    }

    private func stopRecording() {
        videoOutput.stopRecording()
        isRecording = false
        displayLink?.invalidate()
        displayLink = nil

        // Restore button
        UIView.animate(withDuration: 0.2) {
            self.captureInner.layer.cornerRadius = 30
            self.captureInner.transform = .identity
        }

        timerLabel.isHidden = true
        modePhoto.isHidden = false
        modeVideo.isHidden = false
    }

    @objc private func updateTimer() {
        guard let start = recordingStart else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let m = elapsed / 60
        let s = elapsed % 60
        timerLabel.text = String(format: "%d:%02d", m, s)
    }

    // MARK: - Photo Capture

    private func takePhoto() {
        var settings = AVCapturePhotoSettings()
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        settings.flashMode = torchOn ? .on : .off
        settings.isHighResolutionPhotoEnabled = true
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }
        photoOutput.capturePhoto(with: settings, delegate: self)

        // Shutter flash animation
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)
        UIView.animate(withDuration: 0.1, animations: { flash.alpha = 0.8 }) { _ in
            UIView.animate(withDuration: 0.15, animations: { flash.alpha = 0 }) { _ in
                flash.removeFromSuperview()
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension NativeCameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        dismiss(animated: true) { [weak self] in
            self?.onCapture?(outputFileURL, "video", duration)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension NativeCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("pulse-\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url)
            dismiss(animated: true) { [weak self] in
                self?.onCapture?(url, "photo", 0)
            }
        } catch {
            dismiss(animated: true) { [weak self] in
                self?.onCancel?()
            }
        }
    }
}
