import Cocoa
import AVFoundation
import CoreAudio
import AudioToolbox

// MARK: - Preview view

/// Простой NSView с layer-бэкингом, внутри которого живёт AVCaptureVideoPreviewLayer.
final class PreviewView: NSView {

    let previewLayer = AVCaptureVideoPreviewLayer()
    /// Затемнение у нижнего края — чтобы наложенные контролы читались на видео.
    private let scrim = CAGradientLayer()
    /// Сетка третей — только на превью, в записанное видео не попадает.
    private let gridLayer = CAShapeLayer()

    var gridVisible: Bool {
        get { !gridLayer.isHidden }
        set { gridLayer.isHidden = !newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // Заполняем всю область — без чёрных полос по бокам (лишнее обрезается).
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)

        scrim.colors = [NSColor.black.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
        scrim.startPoint = CGPoint(x: 0.5, y: 0.0)   // низ
        scrim.endPoint = CGPoint(x: 0.5, y: 1.0)     // верх
        layer?.addSublayer(scrim)

        // Светло-серые полупрозрачные линии; тонкая тень, чтобы читались и на светлом фоне.
        gridLayer.fillColor = nil
        gridLayer.strokeColor = NSColor(calibratedWhite: 0.92, alpha: 0.5).cgColor
        gridLayer.lineWidth = 1
        gridLayer.shadowColor = NSColor.black.cgColor
        gridLayer.shadowOpacity = 0.35
        gridLayer.shadowRadius = 0.6
        gridLayer.shadowOffset = .zero
        layer?.addSublayer(gridLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        scrim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(150, bounds.height * 0.32))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gridLayer.frame = bounds
        let path = CGMutablePath()
        for i in 1...2 {
            let x = bounds.width * CGFloat(i) / 3
            let y = bounds.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: bounds.height))
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        gridLayer.path = path
        CATransaction.commit()
    }
}

// MARK: - Кнопка записи с кольцевым индикатором звука

/// Круглая красная кнопка (кружок → квадрат при записи), а вокруг неё —
/// кольцевой индикатор уровня звука: зелёный → жёлтый → красный, с меткой пика.
final class RecordButton: NSButton {

    var recording = false {
        didSet { needsDisplay = true }
    }

    private var displayLevel: CGFloat = 0     // сглаженное значение для отрисовки

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        setButtonType(.momentaryChange)
        setAccessibilityLabel("Кнопка записи")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    override var wantsUpdateLayer: Bool { false }

    /// Значение 0…1 (уже нормализованное из dBFS). Вызывается ~30 раз/с.
    func setLevel(_ value: CGFloat) {
        let target = value.isFinite ? max(0, min(1, value)) : 0
        // Баллистика VU: быстрая атака, медленный спад — убирает дёрганье.
        let k: CGFloat = target > displayLevel ? 0.55 : 0.15
        displayLevel += (target - displayLevel) * k
        if displayLevel < 0.004 { displayLevel = 0 }
        needsDisplay = true
    }

    func resetLevel() {
        displayLevel = 0
        needsDisplay = true
    }

    private func meterColor(_ x: CGFloat) -> NSColor {
        if x < 0.6 { return .systemGreen }
        if x < 0.85 { return .systemYellow }
        return .systemRed
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let side = min(bounds.width, bounds.height)
        let ringWidth = max(3, side * 0.075)
        let ringR = side / 2 - ringWidth / 2 - 1
        let buttonD = (ringR - ringWidth / 2 - side * 0.07) * 2

        // --- Кольцевой индикатор ---
        // Пустой трек виден всегда.
        let track = NSBezierPath(ovalIn: NSRect(x: c.x - ringR, y: c.y - ringR,
                                                width: ringR * 2, height: ringR * 2))
        track.lineWidth = ringWidth
        NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
        track.stroke()

        // Заполнение от 6 часов (снизу) ПО ЧАСОВОЙ СТРЕЛКЕ на угол 360·level.
        // Точки считаем вручную — никакой зависимости от флагов appendArc.
        if displayLevel > 0.01 {
            let arc = NSBezierPath()
            let steps = max(2, Int(ceil(displayLevel * 160)))
            let fy: CGFloat = isFlipped ? -1 : 1     // где «верх» в этой системе
            for i in 0...steps {
                let phi = Double.pi + Double(displayLevel) * 2 * Double.pi * Double(i) / Double(steps)
                let p = NSPoint(x: c.x + ringR * CGFloat(sin(phi)),
                                y: c.y + fy * ringR * CGFloat(cos(phi)))
                if i == 0 { arc.move(to: p) } else { arc.line(to: p) }
            }
            arc.lineWidth = ringWidth
            arc.lineCapStyle = .round
            arc.lineJoinStyle = .round
            meterColor(displayLevel).setStroke()
            arc.stroke()
        }

        // --- Кнопка ---
        let btn = NSRect(x: c.x - buttonD / 2, y: c.y - buttonD / 2, width: buttonD, height: buttonD)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        let base: NSColor = recording
            ? NSColor(calibratedRed: 0.72, green: 0.0, blue: 0.0, alpha: 1)
            : NSColor.systemRed
        (isHighlighted ? base.blended(withFraction: 0.18, of: .black) ?? base : base).setFill()
        NSBezierPath(ovalIn: btn).fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let inner = NSBezierPath(ovalIn: btn.insetBy(dx: buttonD * 0.07, dy: buttonD * 0.07))
        inner.lineWidth = max(1.5, buttonD * 0.05)
        inner.stroke()

        NSColor.white.setFill()
        if recording {
            let d = buttonD * 0.34
            NSBezierPath(roundedRect: NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d),
                         xRadius: d * 0.18, yRadius: d * 0.18).fill()
        } else {
            let d = buttonD * 0.44
            NSBezierPath(ovalIn: NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)).fill()
        }

        if !isEnabled {
            NSColor(calibratedWhite: 0.5, alpha: 0.45).setFill()
            NSBezierPath(ovalIn: btn).fill()
        }
    }
}

// MARK: - Контроллер приложения

final class AppController: NSObject, NSApplicationDelegate,
                           AVCaptureFileOutputRecordingDelegate,
                           AVCaptureAudioDataOutputSampleBufferDelegate {

    // Окно и UI
    private var window: NSWindow!
    private var previewView: PreviewView!
    private var devicePopup: NSPopUpButton!
    private var audioPopup: NSPopUpButton!
    private var orientationControl: NSSegmentedControl!
    private var recordButton: RecordButton!
    private var timerLabel: NSTextField!
    private var folderButton: NSButton!
    private var audioCheckbox: NSButton!
    private var statusLabel: NSTextField!
    private var barView: NSView!

    // Геометрия компоновки
    private let barH: CGFloat = 136
    private let statusH: CGFloat = 22

    // Capture
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.emil.sonyrecorder.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let audioMeterQueue = DispatchQueue(label: "com.emil.sonyrecorder.audiometer")
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var videoDevices: [AVCaptureDevice] = []
    private var audioDevices: [AVCaptureDevice] = []

    // Состояние записи
    private var isRecording = false
    private var recordingStart: Date?
    private var recordingTimer: Timer?
    private var meterTimer: Timer?

    /// Записываем ли текущий/следующий дубль в вертикали.
    private var vertical: Bool { orientationControl?.selectedSegmentTag() == 1 }
    private var recordedVertical = false
    /// Удалось ли повернуть картинку «на лету» через capture-connection.
    private var liveRotationApplied = false

    // Папка сохранения
    private var outputFolder: URL!
    private let outputFolderKey = "outputFolder"
    private let sidecarKey = "sidecarWav"
    private let gainKey = "sidecarGainDB"

    // Усиление внешнего микрофона в .wav (линейный множитель, применяется в тапе).
    private var gainSlider: NSSlider!
    private var gainCaption: NSTextField!
    private var gainLabel: NSTextField!
    private var sidecarGainDB: Double = 6
    private var gainLinear: Float = 2.0

    // Поправка синхронизации звук/видео в .mov (мс). Положительная — сдвигает
    // звук ПОЗЖЕ (когда видео с камеры отстаёт от звука, частый случай для UVC).
    // Сетка третей на превью (галочка справа от кнопки записи).
    private let gridKey = "showGrid"
    private var timerPill: NSView!
    private var gridPill: NSView!
    private var gridCheckbox: NSButton!

    private let syncKey = "avSyncOffsetMs"
    private var syncSlider: NSSlider!
    private var syncCaption: NSTextField!
    private var syncLabel: NSTextField!
    private var syncOffsetMs: Double = 0

    // Отдельный .wav: устройство из списка «Звук», пишется через AVAudioEngine
    // (мимо AVCaptureSession — не может сломать звук в .mov). В .mov при этом идёт
    // звук камеры.
    private var sidecarCheckbox: NSButton!
    private var sidecarEngine: AVAudioEngine?
    private var sidecarAudioFile: AVAudioFile?
    private var sidecarMonoFormat: AVAudioFormat?
    private var sidecarActive = false
    private var sidecarURL: URL?
    private var pendingSidecarURL: URL?   // старт файла откладываем до реального начала .mov

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOutputFolder()
        buildWindow()
        audioDataOutput.setSampleBufferDelegate(self, queue: audioMeterQueue)
        setStatus("Запрашиваю доступ к камере и микрофону…")

        requestPermissions { [weak self] videoGranted in
            guard let self = self else { return }
            self.reloadDevices()
            if videoGranted {
                self.reconfigureSession(with: self.selectedVideoDevice())
                self.startSession()
                self.ensureSidecarEngine()
                self.refreshMeter()
                if !self.videoDevices.isEmpty {
                    self.setStatus("Готово к записи")
                }
            } else {
                self.recordButton.isEnabled = false
                self.setStatus("Нет доступа к камере. Системные настройки → Конфиденциальность → Камера")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isRecording {
            movieOutput.stopRecording()
        }
        teardownSidecarEngine()
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Разрешения

    private func requestPermissions(completion: @escaping (_ videoGranted: Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { videoGranted in
            // Микрофон запрашиваем всегда — вдруг пользователь включит галочку позже.
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    completion(videoGranted)
                }
            }
        }
    }

    // MARK: - Устройства

    private func reloadDevices() {
        videoDevices = AVCaptureDevice.devices(for: .video)
        audioDevices = AVCaptureDevice.devices(for: .audio)

        // --- Видео ---
        devicePopup.removeAllItems()
        if videoDevices.isEmpty {
            devicePopup.addItem(withTitle: "Камеры не найдены")
            devicePopup.isEnabled = false
            recordButton.isEnabled = false
            setStatus("Видео-устройства не найдены. Подключите камеру по USB и включите на ней USB-стриминг.")
        } else {
            devicePopup.isEnabled = true
            for device in videoDevices {
                devicePopup.addItem(withTitle: device.localizedName)
            }
            devicePopup.selectItem(at: 0)
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                recordButton.isEnabled = true
            }
        }

        // --- Звук ---
        audioPopup.removeAllItems()
        if audioDevices.isEmpty {
            audioPopup.addItem(withTitle: "Микрофоны не найдены")
            audioPopup.isEnabled = false
        } else {
            audioPopup.isEnabled = true
            for device in audioDevices {
                audioPopup.addItem(withTitle: device.localizedName)
            }
            // По умолчанию — системный микрофон.
            let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
            if let idx = audioDevices.firstIndex(where: { $0.uniqueID == defaultID }) {
                audioPopup.selectItem(at: idx)
            } else {
                audioPopup.selectItem(at: 0)
            }
        }
    }

    private func selectedVideoDevice() -> AVCaptureDevice? {
        let index = devicePopup.indexOfSelectedItem
        guard index >= 0, index < videoDevices.count else { return nil }
        return videoDevices[index]
    }

    private func selectedAudioDevice() -> AVCaptureDevice? {
        let index = audioPopup.indexOfSelectedItem
        guard index >= 0, index < audioDevices.count else { return nil }
        return audioDevices[index]
    }

    /// Аудиоустройство камеры (для дорожки в .mov) — по совпадению имени с камерой.
    private func cameraAudioDevice() -> AVCaptureDevice? {
        guard let cam = selectedVideoDevice() else { return nil }
        let n = cam.localizedName.lowercased()
        if let exact = audioDevices.first(where: { $0.localizedName.lowercased() == n }) { return exact }
        if let part = audioDevices.first(where: {
            let a = $0.localizedName.lowercased()
            return a.contains(n) || n.contains(a)
        }) { return part }
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
        }
        let ct = tokens(cam.localizedName)
        return audioDevices.first(where: { !tokens($0.localizedName).isDisjoint(with: ct) })
    }

    /// AudioDeviceID CoreAudio по uniqueID устройства AVCaptureDevice (для аудио они совпадают).
    private func coreAudioDeviceID(uid: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return nil }
        for id in ids {
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var cf: Unmanaged<CFString>?
            var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &s, &cf) == noErr,
                  let str = cf?.takeRetainedValue() as String? else { continue }
            if str == uid { return id }
        }
        return nil
    }

    // MARK: - Конфигурация сессии

    /// Полностью пересобирает video-input под выбранное устройство.
    private func reconfigureSession(with device: AVCaptureDevice?) {
        session.beginConfiguration()

        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        if let existing = videoInput {
            session.removeInput(existing)
            videoInput = nil
        }

        if let device = device {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                    videoInput = input
                } else {
                    setStatus("Не удалось подключить камеру «\(device.localizedName)» к сессии")
                }
            } catch {
                setStatus("Ошибка камеры: \(error.localizedDescription)")
            }
        }

        applyAudioInput()

        if !session.outputs.contains(where: { $0 === movieOutput }) {
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        }
        if !session.outputs.contains(where: { $0 === audioDataOutput }) {
            if session.canAddOutput(audioDataOutput) {
                session.addOutput(audioDataOutput)
            }
        }

        session.commitConfiguration()
        previewView.previewLayer.session = session
        applyOrientation()
    }

    /// Звук в .mov: если включён «+.wav» — берём аудио камеры (микрофон из списка
    /// уходит в отдельный .wav), иначе — выбранный в списке микрофон.
    /// Вызывать внутри begin/commit.
    private func applyAudioInput() {
        if let existing = audioInput {
            session.removeInput(existing)
            audioInput = nil
        }

        guard audioCheckbox.state == .on else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            setStatus("Нет доступа к микрофону — запись пойдёт без звука")
            return
        }

        let dev: AVCaptureDevice?
        if sidecarCheckbox?.state == .on {
            dev = cameraAudioDevice()
            if dev == nil { setStatus("Аудио камеры не найдено — .mov без звука") }
        } else {
            dev = selectedAudioDevice() ?? AVCaptureDevice.default(for: .audio)
        }
        guard let mic = dev else { return }

        do {
            let input = try AVCaptureDeviceInput(device: mic)
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
        } catch {
            setStatus("Ошибка звука .mov: \(error.localizedDescription)")
        }
    }

    /// Поворачивает картинку под выбранный формат (вертикаль/горизонталь).
    private func applyOrientation() {
        let v = vertical

        var movieRotated = false
        if let conn = movieOutput.connection(with: .video) {
            movieRotated = setRotation(conn, vertical: v)
        }
        if let conn = previewView.previewLayer.connection {
            _ = setRotation(conn, vertical: v)
        }
        liveRotationApplied = movieRotated

        if v && !movieRotated {
            setStatus("Вертикаль: камера не поворачивает на лету — доверну файл при сохранении")
        }
    }

    /// Возвращает true, если поворот удалось применить к connection.
    private func setRotation(_ conn: AVCaptureConnection, vertical: Bool) -> Bool {
        if #available(macOS 14.0, *) {
            let angle: CGFloat = vertical ? 90 : 0
            if conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
                return true
            }
            return !vertical
        } else {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = vertical ? .portrait : .landscapeRight
                return true
            }
            return !vertical
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // MARK: - Действия UI

    @objc private func deviceChanged() {
        if isRecording { stopRecording() }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.reconfigureSession(with: self.selectedVideoDevice())
                self.startSession()
                self.setStatus("Камера: \(self.selectedVideoDevice()?.localizedName ?? "—")")
            }
        }
    }

    @objc private func audioSourceChanged() {
        session.beginConfiguration()
        applyAudioInput()
        session.commitConfiguration()
        teardownSidecarEngine()          // движок наводится на другое устройство
        ensureSidecarEngine()
        refreshMeter()
        setStatus("Микрофон (в .wav): \(selectedAudioDevice()?.localizedName ?? "—")")
    }

    @objc private func audioToggled() {
        session.beginConfiguration()
        applyAudioInput()
        session.commitConfiguration()
        let on = audioCheckbox.state == .on
        audioPopup.isEnabled = on && !audioDevices.isEmpty
        sidecarCheckbox.isEnabled = on
        ensureSidecarEngine()
        updateGainControlsEnabled()
        refreshMeter()
        setStatus(on ? "Звук будет записан" : "Звук отключён")
    }

    @objc private func sidecarToggled() {
        let on = sidecarCheckbox.state == .on
        UserDefaults.standard.set(on, forKey: sidecarKey)
        // «+.wav» меняет и источник звука в .mov: вкл → камера, выкл → микрофон из списка.
        session.beginConfiguration()
        applyAudioInput()
        session.commitConfiguration()
        ensureSidecarEngine()
        updateGainControlsEnabled()
        refreshMeter()
        setStatus(on
            ? "Звук: камера → в .mov, микрофон из списка → отдельный .wav"
            : "Звук: микрофон из списка → в .mov")
    }

    @objc private func gainChanged() {
        sidecarGainDB = gainSlider.doubleValue
        gainLinear = Float(pow(10.0, sidecarGainDB / 20.0))
        gainLabel.stringValue = String(format: "%+.0f дБ", sidecarGainDB)
        UserDefaults.standard.set(sidecarGainDB, forKey: gainKey)
    }

    @objc private func gridToggled() {
        let on = gridCheckbox.state == .on
        previewView.gridVisible = on
        UserDefaults.standard.set(on, forKey: gridKey)
    }

    @objc private func syncChanged() {
        syncOffsetMs = syncSlider.doubleValue.rounded()
        syncLabel.stringValue = String(format: "%+.0f мс", syncOffsetMs)
        UserDefaults.standard.set(syncOffsetMs, forKey: syncKey)
    }

    private func updateGainControlsEnabled() {
        let on = sidecarCheckbox?.state == .on && audioCheckbox?.state == .on
        gainSlider?.isEnabled = on
        gainCaption?.textColor = on ? .secondaryLabelColor : .tertiaryLabelColor
        gainLabel?.textColor = on ? .secondaryLabelColor : .tertiaryLabelColor
    }

    @objc private func orientationChanged() {
        applyOrientation()
        layoutWindow(vertical: vertical)
        if !vertical {
            setStatus("Формат: горизонтально 16:9")
        } else if liveRotationApplied {
            setStatus("Формат: вертикально 9:16")
        }
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputFolder
        panel.prompt = "Выбрать"
        panel.message = "Куда сохранять записи"

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            self.outputFolder = url
            UserDefaults.standard.set(url, forKey: self.outputFolderKey)   // запоминаем выбор
            self.setStatus("Папка сохранения: \(url.path)")
        }
    }

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard videoInput != nil else {
            setStatus("Нет активной камеры — запись невозможна")
            return
        }
        guard session.isRunning else {
            setStatus("Сессия ещё не запущена, подождите секунду")
            return
        }

        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let ts = timestamp()
        let fileURL = outputFolder.appendingPathComponent("sonyrecorder-\(ts).mov")
        recordedVertical = vertical
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)

        // .wav стартует не здесь, а в didStartRecordingTo — чтобы совпасть с видео.
        pendingSidecarURL = (sidecarCheckbox.state == .on)
            ? outputFolder.appendingPathComponent("sonyrecorder-\(ts)-audio.wav")
            : nil
        sidecarActive = false

        isRecording = true
        recordingStart = Date()
        setControlsLocked(true)
        updateRecordButtonAppearance()
        startTimer()
        setStatus("Идёт запись…")
    }

    private func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
        endSidecarFile()                 // движок оставляем для индикатора
        pendingSidecarURL = nil
        isRecording = false
        stopTimer()
        timerLabel.stringValue = "00:00"
        setControlsLocked(false)
        updateRecordButtonAppearance()
        // Итоговый статус выставит делегат didFinishRecordingTo.
    }

    // MARK: - Отдельный .wav через AVAudioEngine (устройство из списка «Звук»)

    /// Держит движок запущенным, пока включён «+.wav» — для индикатора и готовности к записи.
    private func ensureSidecarEngine() {
        guard sidecarCheckbox?.state == .on else { teardownSidecarEngine(); return }
        if sidecarEngine != nil { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }

        let engine = AVAudioEngine()
        // Навести вход на устройство, выбранное в списке (а не «по умолчанию»).
        if let uid = selectedAudioDevice()?.uniqueID,
           let devID = coreAudioDeviceID(uid: uid),
           let unit = engine.inputNode.audioUnit {
            var mut = devID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &mut,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let node = engine.inputNode
        let fmt = node.inputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            setStatus("«+.wav»: у выбранного устройства нет входа"); return
        }

        // Пишем строго МОНО: даунмикс всех каналов входа в один.
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: fmt.sampleRate, channels: 1, interleaved: false) else {
            setStatus("«+.wav»: не удалось создать моно-формат"); return
        }
        sidecarMonoFormat = mono

        node.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
            guard let self = self else { return }
            let n = Int(buffer.frameLength)
            let srcCh = Int(buffer.format.channelCount)
            guard n > 0, let src = buffer.floatChannelData,
                  let monoBuf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(n)) else { return }
            monoBuf.frameLength = AVAudioFrameCount(n)
            let dst = monoBuf.floatChannelData![0]
            let g = self.gainLinear
            let inv = 1 / Float(srcCh)
            var peak: Float = 0
            for i in 0..<n {
                var acc: Float = 0
                for c in 0..<srcCh { acc += src[c][i] }
                var v = acc * inv * g
                if v > 1 { v = 1 } else if v < -1 { v = -1 }
                dst[i] = v
                let a = abs(v); if a > peak { peak = a }
            }

            if let f = self.sidecarAudioFile { try? f.write(from: monoBuf) }

            let db = peak > 0 ? 20 * log10(peak) : -120
            DispatchQueue.main.async { self.recordButton.setLevel(CGFloat((db + 60) / 57)) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            setStatus("«+.wav»: движок не запустился (\(error.localizedDescription))")
            return
        }
        sidecarEngine = engine
    }

    private func teardownSidecarEngine() {
        endSidecarFile()
        sidecarMonoFormat = nil
        guard let engine = sidecarEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sidecarEngine = nil
    }

    /// Начинает писать .wav в текущий тап (движок уже прогрет) — вызывается из didStartRecordingTo.
    private func beginSidecarFile(_ base: URL) {
        guard let mono = sidecarMonoFormat else {
            setStatus("«+.wav»: движок не готов"); return
        }
        let wavURL = base.deletingPathExtension().appendingPathExtension("wav")
        let cafURL = base.deletingPathExtension().appendingPathExtension("caf")
        try? FileManager.default.removeItem(at: wavURL)
        try? FileManager.default.removeItem(at: cafURL)

        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: mono.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        if let f = try? AVAudioFile(forWriting: wavURL, settings: wavSettings) {
            sidecarAudioFile = f; sidecarURL = wavURL
        } else if let f = try? AVAudioFile(forWriting: cafURL, settings: mono.settings) {
            sidecarAudioFile = f; sidecarURL = cafURL
        } else {
            setStatus("Не удалось создать отдельный аудиофайл"); return
        }
        sidecarActive = true
        setStatus("Пишу видео + \(sidecarURL!.lastPathComponent) (моно)")
    }

    private func endSidecarFile() {
        sidecarAudioFile = nil   // релиз финализирует файл
    }

    private func setControlsLocked(_ locked: Bool) {
        devicePopup.isEnabled = !locked && !videoDevices.isEmpty
        audioPopup.isEnabled = !locked && !audioDevices.isEmpty && audioCheckbox.state == .on
        audioCheckbox.isEnabled = !locked
        sidecarCheckbox.isEnabled = !locked && audioCheckbox.state == .on
        orientationControl.isEnabled = !locked
        folderButton.isEnabled = !locked
    }

    // MARK: - Таймер и индикатор звука

    private func startTimer() {
        timerLabel.stringValue = "00:00"
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.recordingStart else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            self.timerLabel.stringValue = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingTimer = timer
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    /// Кольцо вокруг кнопки. Если включён «+.wav» — уровень идёт из тапа
    /// AVAudioEngine (микрофон из списка). Иначе — из аудио .mov по таймеру.
    private func refreshMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        recordButton.resetLevel()

        guard audioCheckbox.state == .on, sidecarCheckbox?.state != .on else { return }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let channels = self.audioDataOutput.connection(with: .audio)?.audioChannels ?? []
            guard !channels.isEmpty else {
                self.recordButton.setLevel(0)
                return
            }
            // Берём максимум по всем каналам — у звуковых карт сигнал может быть
            // только на 2-м входе. averagePowerLevel — в dBFS (~ -120…0).
            let db = channels
                .map { CGFloat($0.averagePowerLevel) }
                .filter { $0.isFinite }
                .max() ?? -120
            // -60 дБ → пусто, -3 дБ → полностью.
            self.recordButton.setLevel((db + 60) / 57)
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    // Нужен, чтобы включился поток метрик уровня. Буферы не трогаем.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) { }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            // .mov реально начал писаться — запускаем .wav в этот же момент.
            if let url = self.pendingSidecarURL {
                self.pendingSidecarURL = nil
                if self.sidecarEngine == nil { self.ensureSidecarEngine() }
                self.beginSidecarFile(url)
            }
            if !self.sidecarActive {
                self.setStatus("Запись: \(fileURL.lastPathComponent)…")
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async {
            if let error = error as NSError? {
                let finishedOK = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
                if !finishedOK {
                    self.setStatus("Ошибка записи: \(error.localizedDescription)")
                    return
                }
            }

            if self.recordedVertical && !self.liveRotationApplied {
                self.setStatus("Поворачиваю видео в вертикаль…")
                self.rotateToVertical(outputFileURL) { finalURL, rotateError in
                    if let rotateError = rotateError {
                        self.setStatus("Сохранено без поворота: \(outputFileURL.lastPathComponent) — \(rotateError.localizedDescription)")
                        return
                    }
                    self.finishSaving(finalURL)
                }
            } else {
                self.finishSaving(outputFileURL)
            }
        }
    }

    /// Последний шаг: если задана поправка синхронизации — довороты звука, иначе сразу готово.
    private func finishSaving(_ url: URL) {
        let wavSuffix = sidecarActive ? "  + \(sidecarURL?.lastPathComponent ?? ".wav")" : ""
        guard syncOffsetMs != 0 else {
            setStatus("Сохранено: \(url.lastPathComponent)\(wavSuffix)")
            return
        }
        setStatus("Подстраиваю синхронизацию звука…")
        applySyncOffset(to: url, offsetMs: syncOffsetMs) { finalURL, syncError in
            if let syncError = syncError {
                self.setStatus("Сохранено без синхро-правки: \(url.lastPathComponent) — \(syncError.localizedDescription)\(wavSuffix)")
            } else {
                self.setStatus("Сохранено: \(finalURL.lastPathComponent)\(wavSuffix)")
            }
        }
    }

    /// Сдвигает звук в .mov относительно видео на offsetMs (плюс — звук позже).
    /// Компенсирует фиксированную задержку обработки видео у UVC-камер.
    private func applySyncOffset(to url: URL, offsetMs: Double, completion: @escaping (URL, Error?) -> Void) {
        let asset = AVURLAsset(url: url)
        guard let vTrack = asset.tracks(withMediaType: .video).first,
              let aTrack = asset.tracks(withMediaType: .audio).first else {
            completion(url, nil)
            return
        }

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            completion(url, nil)
            return
        }

        let duration = asset.duration
        do {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: vTrack, at: .zero)
            compVideo.preferredTransform = vTrack.preferredTransform

            if offsetMs > 0 {
                // Видео отстаёт — сдвигаем звук позже на offsetMs.
                let delay = CMTime(seconds: offsetMs / 1000, preferredTimescale: 600)
                try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: aTrack, at: delay)
            } else {
                // Звук отстаёт — обрезаем его начало на -offsetMs, сдвигая раньше.
                let trim = CMTime(seconds: -offsetMs / 1000, preferredTimescale: 600)
                let remain = CMTimeSubtract(duration, trim)
                if remain > .zero {
                    try compAudio.insertTimeRange(CMTimeRange(start: trim, duration: remain), of: aTrack, at: .zero)
                }
            }
        } catch {
            completion(url, error)
            return
        }

        let base = url.deletingPathExtension().lastPathComponent
        let finalURL = url.deletingLastPathComponent().appendingPathComponent(base + "-synced.mov")
        try? FileManager.default.removeItem(at: finalURL)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(url, nil)
            return
        }
        export.outputURL = finalURL
        export.outputFileType = .mov
        export.exportAsynchronously {
            DispatchQueue.main.async {
                if export.status == .completed {
                    try? FileManager.default.removeItem(at: url)
                    completion(finalURL, nil)
                } else {
                    completion(url, export.error)
                }
            }
        }
    }

    // MARK: - Поворот файла в вертикаль (запасной путь)

    private func rotateToVertical(_ url: URL, completion: @escaping (URL, Error?) -> Void) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            completion(url, nil)
            return
        }

        let size = track.naturalSize
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: size.height, height: size.width)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // Поворот на 90° по часовой стрелке.
        let transform = CGAffineTransform(translationX: size.height, y: 0).rotated(by: .pi / 2)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]
        videoComposition.instructions = [instruction]

        let base = url.deletingPathExtension().lastPathComponent
        let finalURL = url.deletingLastPathComponent().appendingPathComponent(base + "-vertical.mov")
        try? FileManager.default.removeItem(at: finalURL)

        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetHighestQuality) else {
            completion(url, nil)
            return
        }
        export.outputURL = finalURL
        export.outputFileType = .mov
        export.videoComposition = videoComposition
        export.exportAsynchronously {
            DispatchQueue.main.async {
                if export.status == .completed {
                    try? FileManager.default.removeItem(at: url)
                    completion(finalURL, nil)
                } else {
                    completion(url, export.error)
                }
            }
        }
    }

    // MARK: - Вспомогательное

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private func updateRecordButtonAppearance() {
        recordButton.recording = isRecording
        recordButton.toolTip = isRecording ? "Остановить запись" : "Начать запись"
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func setupOutputFolder() {
        let fm = FileManager.default
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let fallback = desktop.appendingPathComponent("SonyRecorder")

        // Восстанавливаем последнюю выбранную папку, иначе — папка на Рабочем столе.
        outputFolder = UserDefaults.standard.url(forKey: outputFolderKey) ?? fallback

        do {
            try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        } catch {
            outputFolder = fallback
            try? fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        }
    }

    // MARK: - Построение окна

    private func setupMenu() {
        let app = NSApplication.shared

        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        app.mainMenu = mainMenu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.title = "StreamRecord"

        let content = NSView(frame: window.contentView!.bounds)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = content

        // Превью на всё окно.
        previewView = PreviewView(frame: .zero)
        content.addSubview(previewView)

        // Тёмная панель управления снизу.
        barView = NSView(frame: .zero)
        barView.wantsLayer = true
        barView.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        content.addSubview(barView)

        // --- Компактные настройки (верхний ряд панели) ---
        devicePopup = compactPopup(action: #selector(deviceChanged))
        barView.addSubview(devicePopup)

        audioPopup = compactPopup(action: #selector(audioSourceChanged))
        barView.addSubview(audioPopup)

        orientationControl = NSSegmentedControl(labels: ["16:9", "9:16"],
                                                trackingMode: .selectOne,
                                                target: self,
                                                action: #selector(orientationChanged))
        orientationControl.controlSize = .small
        orientationControl.segmentDistribution = .fillEqually
        orientationControl.selectedSegment = 1          // по умолчанию — вертикаль
        barView.addSubview(orientationControl)

        audioCheckbox = NSButton(checkboxWithTitle: "Звук",
                                 target: self, action: #selector(audioToggled))
        audioCheckbox.controlSize = .small
        audioCheckbox.font = .systemFont(ofSize: 11)
        audioCheckbox.state = .on
        barView.addSubview(audioCheckbox)

        sidecarCheckbox = NSButton(checkboxWithTitle: "+.wav",
                                   target: self, action: #selector(sidecarToggled))
        sidecarCheckbox.controlSize = .small
        sidecarCheckbox.font = .systemFont(ofSize: 11)
        sidecarCheckbox.state = ((UserDefaults.standard.object(forKey: sidecarKey) as? Bool) ?? true) ? .on : .off
        sidecarCheckbox.toolTip = "Микрофон из списка → отдельный .wav; в .mov при этом идёт звук камеры"
        barView.addSubview(sidecarCheckbox)

        // Усиление внешнего микрофона (для .wav): 0…+18 дБ
        if let stored = UserDefaults.standard.object(forKey: gainKey) as? Double {
            sidecarGainDB = min(max(stored, 0), 18)
        }
        gainLinear = Float(pow(10.0, sidecarGainDB / 20.0))

        gainCaption = NSTextField(labelWithString: "Усиление .wav")
        gainCaption.font = .systemFont(ofSize: 11)
        gainCaption.textColor = .secondaryLabelColor
        barView.addSubview(gainCaption)

        gainSlider = NSSlider(value: sidecarGainDB, minValue: 0, maxValue: 18,
                              target: self, action: #selector(gainChanged))
        gainSlider.controlSize = .small
        gainSlider.numberOfTickMarks = 7          // 0·3·6·9·12·15·18 дБ
        gainSlider.tickMarkPosition = .below
        gainSlider.toolTip = "Программное усиление внешнего микрофона в .wav (0…18 дБ, деления по 3)"
        barView.addSubview(gainSlider)

        gainLabel = NSTextField(labelWithString: String(format: "%+.0f дБ", sidecarGainDB))
        gainLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        gainLabel.textColor = .secondaryLabelColor
        gainLabel.alignment = .right
        barView.addSubview(gainLabel)

        // Поправка синхронизации звук/видео в .mov: ±300 мс
        if let stored = UserDefaults.standard.object(forKey: syncKey) as? Double {
            syncOffsetMs = min(max(stored, -300), 300)
        }

        syncCaption = NSTextField(labelWithString: "Синхро A/V")
        syncCaption.font = .systemFont(ofSize: 11)
        syncCaption.textColor = .secondaryLabelColor
        barView.addSubview(syncCaption)

        syncSlider = NSSlider(value: syncOffsetMs, minValue: -300, maxValue: 300,
                              target: self, action: #selector(syncChanged))
        syncSlider.controlSize = .small
        syncSlider.numberOfTickMarks = 7          // -300…+300, деления по 100
        syncSlider.tickMarkPosition = .below
        syncSlider.toolTip = "Сдвиг звука в .mov относительно видео. Плюс — видео отстаёт от звука (сдвигаем звук позже)"
        barView.addSubview(syncSlider)

        syncLabel = NSTextField(labelWithString: String(format: "%+.0f мс", syncOffsetMs))
        syncLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        syncLabel.textColor = .secondaryLabelColor
        syncLabel.alignment = .right
        barView.addSubview(syncLabel)

        folderButton = NSButton(title: "Папка", target: self, action: #selector(chooseFolder))
        folderButton.bezelStyle = .rounded
        folderButton.controlSize = .small
        folderButton.font = .systemFont(ofSize: 11)
        if let img = NSImage(systemSymbolName: "folder", accessibilityDescription: "Папка") {
            folderButton.image = img
            folderButton.imagePosition = .imageLeading
        }
        folderButton.toolTip = "Выбрать папку сохранения"
        barView.addSubview(folderButton)

        // --- Запись: таймер и кнопка наложены прямо на видео (внизу по центру) ---
        timerLabel = NSTextField(labelWithString: "00:00")
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timerLabel.textColor = .white
        timerLabel.alignment = .center
        timerLabel.usesSingleLineMode = true
        // Плашка отдельным view, а текст внутри центрируется по высоте вручную
        // (у NSTextField текст прижат к верху фрейма).
        timerPill = NSView(frame: .zero)
        timerPill.wantsLayer = true
        timerPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        timerPill.layer?.cornerRadius = 9
        timerPill.addSubview(timerLabel)
        content.addSubview(timerPill)

        recordButton = RecordButton(frame: .zero)   // кольцо-индикатор видно всегда
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.isEnabled = false
        content.addSubview(recordButton)

        // Галочка «Сетка» — плашка справа от кнопки записи (зеркально таймеру).
        gridPill = NSView(frame: .zero)
        gridPill.wantsLayer = true
        gridPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        gridPill.layer?.cornerRadius = 9
        gridCheckbox = NSButton(checkboxWithTitle: "Сетка", target: self, action: #selector(gridToggled))
        gridCheckbox.controlSize = .small
        gridCheckbox.font = .systemFont(ofSize: 12, weight: .medium)
        gridCheckbox.appearance = NSAppearance(named: .darkAqua)   // белый текст на тёмной плашке
        let gridOn = (UserDefaults.standard.object(forKey: gridKey) as? Bool) ?? true
        gridCheckbox.state = gridOn ? .on : .off
        gridCheckbox.toolTip = "Сетка третей на превью (в записанное видео не попадает)"
        gridCheckbox.sizeToFit()
        gridPill.addSubview(gridCheckbox)
        content.addSubview(gridPill)
        previewView.gridVisible = gridOn

        updateRecordButtonAppearance()

        // --- Статус (строка у самого низа) ---
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingMiddle
        content.addSubview(statusLabel)

        setupMenu()
        window.makeKeyAndOrderFront(nil)
        layoutWindow(vertical: true)
        window.center()
    }

    private func compactPopup(action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.target = self
        popup.action = action
        return popup
    }

    // MARK: - Раскладка под формат

    /// Пересчитывает размер окна под формат картинки и раскладывает контролы.
    private func layoutWindow(vertical: Bool) {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Размер области превью = размер картинки (без боковых рамок).
        let previewSize: NSSize
        if vertical {
            let h = max(480, min(860, visible.height - 60 - barH - statusH))
            previewSize = NSSize(width: (h * 9 / 16).rounded(), height: h.rounded())
        } else {
            let w = max(600, min(960, visible.width - 120))
            previewSize = NSSize(width: w.rounded(), height: (w * 9 / 16).rounded())
        }

        let contentW = previewSize.width
        let contentH = previewSize.height + barH + statusH

        // Меняем размер окна, сохраняя верхнюю грань на месте.
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: contentW, height: contentH))
        var f = window.frame
        f.origin.y = top - f.height
        if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
            f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
            f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
        }
        window.setFrame(f, display: true, animate: false)

        previewView.frame = NSRect(x: 0, y: barH + statusH, width: contentW, height: previewSize.height)
        barView.frame = NSRect(x: 0, y: statusH, width: contentW, height: barH)
        statusLabel.frame = NSRect(x: 12, y: 3, width: contentW - 24, height: statusH - 6)

        // Кнопка записи — поверх видео, у нижнего края по центру; таймер слева от неё.
        let ctl: CGFloat = 60
        let previewBottom = barH + statusH
        let btnX = ((contentW - ctl) / 2).rounded()
        let btnY = previewBottom + 16
        recordButton.frame = NSRect(x: btnX, y: btnY, width: ctl, height: ctl)

        let timerW: CGFloat = 78, timerHt: CGFloat = 26
        timerPill.frame = NSRect(x: btnX - 12 - timerW,
                                 y: (btnY + ctl / 2 - timerHt / 2).rounded(),
                                 width: timerW, height: timerHt)
        let textH = timerLabel.fittingSize.height
        timerLabel.frame = NSRect(x: 0, y: ((timerHt - textH) / 2).rounded(),
                                  width: timerW, height: textH)

        // Плашка «Сетка» — справа от кнопки, на той же линии, что и таймер.
        let cbSize = gridCheckbox.frame.size
        let pillW = cbSize.width + 22
        gridPill.frame = NSRect(x: btnX + ctl + 12,
                                y: (btnY + ctl / 2 - timerHt / 2).rounded(),
                                width: pillW, height: timerHt)
        gridCheckbox.frame.origin = NSPoint(x: 11, y: ((timerHt - cbSize.height) / 2).rounded())

        layoutBar(width: contentW)
    }

    /// Раскладка панели настроек: четыре ряда, всё центрировано, размеры по факту.
    private func layoutBar(width w: CGFloat) {
        let pad: CGFloat = 12
        let gap: CGFloat = 12
        let mid = w / 2
        let row1CY = barH - 10 - 11
        let row2CY = barH - 10 - 11 - 30
        let row3CY: CGFloat = 46   // усиление .wav
        let row4CY: CGFloat = 17   // синхро A/V

        func center(_ v: NSView, x: CGFloat, cy: CGFloat) {
            var f = v.frame
            f.origin = NSPoint(x: x.rounded(), y: (cy - f.height / 2).rounded())
            v.frame = f
        }

        // Ряд 1: две равные выпадашки, зеркальные отступы.
        let popupW = ((w - pad * 2 - gap) / 2).rounded()
        for p in [devicePopup!, audioPopup!] {
            p.frame.size = NSSize(width: popupW, height: p.fittingSize.height)
        }
        center(devicePopup, x: pad, cy: row1CY)
        center(audioPopup, x: w - pad - popupW, cy: row1CY)

        // Ряд 2: формат · звук · +.wav · папка — по фактической ширине, группа по центру.
        let row2: [NSView] = [orientationControl, audioCheckbox, sidecarCheckbox, folderButton]
        orientationControl.sizeToFit()
        audioCheckbox.sizeToFit()
        sidecarCheckbox.sizeToFit()
        folderButton.sizeToFit()
        let g2: CGFloat = 9
        let w2 = row2.map { $0.frame.width }
        let total2 = w2.reduce(0, +) + g2 * CGFloat(row2.count - 1)
        var x2 = (mid - total2 / 2).rounded()
        for (i, v) in row2.enumerated() {
            center(v, x: x2, cy: row2CY)
            x2 += w2[i] + g2
        }

        // Ряд 3: «Усиление .wav» [ползунок] +N дБ — на всю ширину.
        gainCaption.sizeToFit()
        gainLabel.sizeToFit()
        let capW = gainCaption.frame.width
        let valW = max(44, gainLabel.frame.width)
        let sliderX = pad + capW + 8
        let sliderW = max(60, w - pad - valW - 8 - sliderX)
        gainSlider.frame = NSRect(x: sliderX.rounded(), y: 32, width: sliderW.rounded(), height: 26)
        center(gainCaption, x: pad, cy: row3CY)
        center(gainLabel, x: w - pad - valW, cy: row3CY)
        gainLabel.frame.size.width = valW
        updateGainControlsEnabled()

        // Ряд 4: «Синхро A/V» [ползунок] ±N мс — на всю ширину.
        syncCaption.sizeToFit()
        syncLabel.sizeToFit()
        let capW4 = syncCaption.frame.width
        let valW4 = max(48, syncLabel.frame.width)
        let sliderX4 = pad + capW4 + 8
        let sliderW4 = max(60, w - pad - valW4 - 8 - sliderX4)
        syncSlider.frame = NSRect(x: sliderX4.rounded(), y: 3, width: sliderW4.rounded(), height: 26)
        center(syncCaption, x: pad, cy: row4CY)
        center(syncLabel, x: w - pad - valW4, cy: row4CY)
        syncLabel.frame.size.width = valW4
    }
}

private extension NSSegmentedControl {
    /// Индекс выбранного сегмента как «тег»: 0 — горизонталь, 1 — вертикаль.
    func selectedSegmentTag() -> Int { selectedSegment }
}

// MARK: - Точка входа

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
