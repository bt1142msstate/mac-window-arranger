import AppKit

@MainActor
final class WindowPickerController {
    private let previewCaptureService: WindowPickingPreviewCapturing
    private let windowProvider: WindowPickingWindowProviding
    private var activeSession: WindowPickerSession?

    init(
        windowProvider: WindowPickingWindowProviding,
        previewCaptureService: WindowPickingPreviewCapturing
    ) {
        self.windowProvider = windowProvider
        self.previewCaptureService = previewCaptureService
    }

    func pickWindow(
        configuration: WindowPickerConfiguration = .default,
        completion: @escaping (WindowPickerResult) -> Void
    ) {
        cancel(notify: false)

        if configuration.behavior.requestsScreenCapturePermission {
            previewCaptureService.requestScreenCaptureAccessIfNeeded()
        }

        let session = WindowPickerSession(
            configuration: configuration,
            windowProvider: windowProvider,
            previewCaptureService: previewCaptureService
        ) { [weak self] result in
            self?.activeSession = nil
            completion(result)
        }

        activeSession = session
        session.start()
    }

    func start(
        configuration: WindowPickerConfiguration = .default,
        onPicked: @escaping (WindowPickerItem) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        pickWindow(configuration: configuration) { result in
            switch result {
            case .selected(let window):
                onPicked(window)
            case .cancelled:
                onCancelled()
            }
        }
    }

    func cancel() {
        cancel(notify: true)
    }

    private func cancel(notify: Bool) {
        activeSession?.cancel(notify: notify)
        activeSession = nil
    }
}
