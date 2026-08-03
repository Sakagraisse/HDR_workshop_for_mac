import Foundation

enum UltraHDRBridgeError: LocalizedError {
    case invalidResponse(String)
    case missingInputs
    case missingOutputFolder
    case invalidHDRSource(String)
    case mismatchedDimensions
    case missingGainMap
    case unsupportedInstagramRatio(Double)
    case fileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(message): "Invalid response from ultrahdr_bridge: \(message)"
        case .missingInputs: "Missing required HDR/SDR input."
        case .missingOutputFolder: "Missing output folder."
        case let .invalidHDRSource(name): "\(name) is SDR-only. Ultra HDR creation requires a real HDR source."
        case .mismatchedDimensions: "HDR and SDR files must have exactly matching dimensions and orientation."
        case .missingGainMap: "The selected existing file does not contain a detectable gain map."
        case let .unsupportedInstagramRatio(ratio): "Instagram ratio \(ratio.formatted(.number.precision(.fractionLength(3)))) is outside the supported 1.91:1 to 3:4 range."
        case let .fileTooLarge(size): "The Instagram JPEG is \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)); quality 85 would still exceed the 8 MB target."
        }
    }
}

struct UltraHDRBridgeClient {
    private let processRunner = ProcessRunner()
    private let analyzer = ImageAnalyzer()

    func inspect(url: URL, toolsDirectory: URL) async throws -> UltraHDRInspection {
        let response = try await execute(
            UltraHDRBridgeRequest(operation: .inspect, input: url.path(percentEncoded: false)),
            toolsDirectory: toolsDirectory
        )
        return response.inspection
    }

    func convertUltraHDR(request: UltraHDRConversionRequest, toolsDirectory: URL) async throws -> ConversionJob {
        guard let outputFolder = request.outputFolder else { throw UltraHDRBridgeError.missingOutputFolder }
        guard request.hdrSources.isEmpty == false else { throw UltraHDRBridgeError.missingInputs }
        if request.inputMode == .hdrAndSDR, request.hdrSources.count != 1 || request.sdrBase == nil {
            throw UltraHDRBridgeError.missingInputs
        }

        var outputs: [URL] = []
        var log: [String] = ["Batch size: \(request.hdrSources.count)"]
        for hdrURL in request.hdrSources {
            try await validateHDR(url: hdrURL, toolsDirectory: toolsDirectory)
            if let sdrBase = request.sdrBase {
                try validateMatchingDimensions(hdr: hdrURL, sdr: sdrBase)
            }
            let outputURL = outputFolder.appending(path: "\(hdrURL.deletingPathExtension().lastPathComponent)-ultrahdr.jpg")
            let response = try await execute(
                bridgeRequest(
                    operation: request.sdrBase == nil ? .encodeHDR : .encodePair,
                    hdrURL: hdrURL,
                    sdrURL: request.sdrBase,
                    outputURL: outputURL,
                    baseQuality: request.baseQuality,
                    gainMapQuality: request.gainMapQuality,
                    gainMapScale: request.gainMapScale,
                    multiChannel: request.multiChannel,
                    preset: request.preset.rawValue,
                    colorSpace: request.colorSpace,
                    maxWidth: nil
                ),
                toolsDirectory: toolsDirectory
            )
            guard response.success else { throw UltraHDRBridgeError.invalidResponse(response.messages.joined(separator: " ")) }
            outputs.append(outputURL)
            log.append("\(hdrURL.lastPathComponent): \(response.messages.joined(separator: " "))")
        }

        return ConversionJob(
            title: "Ultra HDR Android Export",
            engine: .libUltraHDR,
            status: .succeeded,
            log: log,
            outputURLs: outputs
        )
    }

    func packageForInstagram(request: InstagramPackageRequest, toolsDirectory: URL) async throws -> ConversionJob {
        guard let outputFolder = request.outputFolder else { throw UltraHDRBridgeError.missingOutputFolder }

        let sourceURL: URL
        let sdrURL: URL?
        let policy: ExistingGainMapPolicy
        switch request.inputMode {
        case .existingGainMap:
            guard let existing = request.existingGainMap else { throw UltraHDRBridgeError.missingInputs }
            let inspection = try await inspect(url: existing, toolsDirectory: toolsDirectory)
            guard inspection.hasGainMap else { throw UltraHDRBridgeError.missingGainMap }
            sourceURL = existing
            sdrURL = existing
            policy = request.existingPolicy
        case .hdrAndSDR:
            guard let hdr = request.hdrSource, let sdr = request.sdrBase else { throw UltraHDRBridgeError.missingInputs }
            try await validateHDR(url: hdr, toolsDirectory: toolsDirectory)
            try validateMatchingDimensions(hdr: hdr, sdr: sdr)
            sourceURL = hdr
            sdrURL = sdr
            policy = .normalized
        }

        let sourceRecord = try analyzer.analyze(url: sourceURL)
        guard let size = sourceRecord.pixelSize else { throw UltraHDRBridgeError.missingInputs }
        let ratio = Double(size.width / size.height)
        guard Self.isInstagramRatioSupported(ratio) else {
            throw UltraHDRBridgeError.unsupportedInstagramRatio(ratio)
        }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = outputFolder.appending(path: "\(stem)-instagram.jpg")
        let reportURL = outputFolder.appending(path: "\(stem)-instagram.report.md")
        let existingInspection = request.inputMode == .existingGainMap
            ? try await inspect(url: sourceURL, toolsDirectory: toolsDirectory)
            : nil
        let sourceFileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        let canCopyLosslessly =
            request.inputMode == .existingGainMap &&
            sourceRecord.container == .jpeg &&
            size.width <= 1080 &&
            sourceFileSize <= request.maxFileSize &&
            existingInspection?.hasSDRFallback == true

        var finalBaseQuality = request.baseQuality
        var finalGainQuality = request.gainMapQuality
        var modeDescription = "Normalized"

        if policy == .lossless || (policy == .automatic && canCopyLosslessly) {
            guard canCopyLosslessly else {
                throw UltraHDRBridgeError.invalidResponse("Lossless mode requires a conforming JPEG gain-map file, width ≤ 1080 px and size ≤ 8 MB.")
            }
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: outputURL, options: .atomic)
            modeDescription = "Lossless byte-identical copy"
        } else {
            var encoded = false
            for quality in stride(from: min(request.baseQuality, request.gainMapQuality), through: 85, by: -2) {
                finalBaseQuality = min(request.baseQuality, quality)
                finalGainQuality = min(request.gainMapQuality, quality)
                _ = try await execute(
                    bridgeRequest(
                        operation: request.inputMode == .existingGainMap ? .normalizeExisting : .encodePair,
                        hdrURL: sourceURL,
                        sdrURL: sdrURL,
                        outputURL: outputURL,
                        baseQuality: finalBaseQuality,
                        gainMapQuality: finalGainQuality,
                        gainMapScale: request.gainMapScale,
                        multiChannel: request.multiChannel,
                        preset: UltraHDRPreset.bestQuality.rawValue,
                        colorSpace: request.colorSpace,
                        maxWidth: 1080
                    ),
                    toolsDirectory: toolsDirectory
                )
                let fileSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                if fileSize <= request.maxFileSize {
                    encoded = true
                    break
                }
            }
            if !encoded {
                let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try? FileManager.default.removeItem(at: outputURL)
                throw UltraHDRBridgeError.fileTooLarge(size)
            }
        }

        let verification = try await inspect(url: outputURL, toolsDirectory: toolsDirectory)
        guard verification.hasGainMap, verification.hasSDRFallback else {
            throw UltraHDRBridgeError.invalidResponse("Post-export verification did not find a valid gain map and SDR fallback.")
        }
        let report = try Self.instagramReport(
            source: sourceURL,
            output: outputURL,
            mode: modeDescription,
            ratio: ratio,
            inspection: verification,
            baseQuality: finalBaseQuality,
            gainMapQuality: finalGainQuality,
            colorSpace: request.colorSpace
        )
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        return ConversionJob(
            title: "Instagram Package",
            engine: .libUltraHDR,
            status: .succeeded,
            log: [
                modeDescription,
                "Verified SDR fallback and \(verification.gainMapKind) gain map.",
                "Generated \(reportURL.lastPathComponent)"
            ],
            outputURLs: [outputURL, reportURL]
        )
    }

    static func isInstagramRatioSupported(_ ratio: Double) -> Bool {
        ratio >= 0.75 && ratio <= 1.91
    }

    private func execute(_ request: UltraHDRBridgeRequest, toolsDirectory: URL) async throws -> UltraHDRBridgeResponse {
        let executableURL = toolsDirectory.appending(path: "ultrahdr_bridge")
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
        try JSONEncoder().encode(request).write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try await processRunner.run(
            executableURL: executableURL,
            arguments: ["--request", tempURL.path(percentEncoded: false)]
        )
        let text = result.standardOutput.isEmpty ? result.standardError : result.standardOutput
        guard let data = text.data(using: .utf8) else {
            throw UltraHDRBridgeError.invalidResponse(result.combinedOutput)
        }
        do {
            let response = try JSONDecoder().decode(UltraHDRBridgeResponse.self, from: data)
            guard response.success else {
                throw UltraHDRBridgeError.invalidResponse(response.messages.joined(separator: " "))
            }
            return response
        } catch let error as UltraHDRBridgeError {
            throw error
        } catch {
            throw UltraHDRBridgeError.invalidResponse("\(error.localizedDescription)\n\(text)")
        }
    }

    private func bridgeRequest(
        operation: UltraHDRBridgeOperation,
        hdrURL: URL,
        sdrURL: URL?,
        outputURL: URL,
        baseQuality: Int,
        gainMapQuality: Int,
        gainMapScale: Int,
        multiChannel: Bool,
        preset: String,
        colorSpace: ColorSpaceKind,
        maxWidth: Int?
    ) -> UltraHDRBridgeRequest {
        UltraHDRBridgeRequest(
            operation: operation,
            input: operation == .normalizeExisting ? hdrURL.path(percentEncoded: false) : nil,
            hdrInput: hdrURL.path(percentEncoded: false),
            sdrInput: sdrURL?.path(percentEncoded: false),
            output: outputURL.path(percentEncoded: false),
            baseQuality: baseQuality,
            gainMapQuality: gainMapQuality,
            gainMapScale: gainMapScale,
            multiChannel: multiChannel,
            preset: preset,
            colorGamut: colorSpace.bridgeName,
            maxWidth: maxWidth
        )
    }

    private func validateHDR(url: URL, toolsDirectory: URL) async throws {
        let inspection = try await inspect(url: url, toolsDirectory: toolsDirectory)
        guard inspection.isHDRSignal else {
            throw UltraHDRBridgeError.invalidHDRSource(url.lastPathComponent)
        }
    }

    private func validateMatchingDimensions(hdr: URL, sdr: URL) throws {
        let hdrRecord = try analyzer.analyze(url: hdr)
        let sdrRecord = try analyzer.analyze(url: sdr)
        guard hdrRecord.pixelSize == sdrRecord.pixelSize else {
            throw UltraHDRBridgeError.mismatchedDimensions
        }
    }

    private static func instagramReport(
        source: URL,
        output: URL,
        mode: String,
        ratio: Double,
        inspection: UltraHDRInspection,
        baseQuality: Int,
        gainMapQuality: Int,
        colorSpace: ColorSpaceKind
    ) throws -> String {
        let byteCount = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let warnings = [
            inspection.hasISO21496 ? nil : "ISO 21496-1 marker was not detected.",
            inspection.hasXMP ? nil : "Ultra HDR XMP marker was not detected; ISO metadata remains available.",
            byteCount > 8_000_000 ? "File exceeds the conservative 8 MB Instagram target." : nil
        ].compactMap { $0 }

        return """
        # Instagram HDR package report

        - Source: `\(source.lastPathComponent)`
        - Output: `\(output.lastPathComponent)`
        - Processing: \(mode)
        - Dimensions: \(inspection.width) × \(inspection.height)
        - Aspect ratio: \(ratio.formatted(.number.precision(.fractionLength(3))))
        - Color space target: \(colorSpace.rawValue)
        - Gain map: \(inspection.gainMapKind), \(inspection.multiChannel ? "RGB" : "monochrome")
        - Gain map dimensions: \(inspection.gainMapWidth) × \(inspection.gainMapHeight)
        - SDR fallback: \(inspection.hasSDRFallback ? "verified" : "missing")
        - Ultra HDR XMP: \(inspection.hasXMP ? "present" : "not detected")
        - ISO 21496-1: \(inspection.hasISO21496 ? "present" : "not detected")
        - Base JPEG quality: \(baseQuality)
        - Gain map quality: \(gainMapQuality)
        - File size: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))

        ## Warnings

        \(warnings.isEmpty ? "- None." : warnings.map { "- \($0)" }.joined(separator: "\n"))

        Compatibility remains dependent on Instagram's current ingestion pipeline.
        """
    }
}

private extension ColorSpaceKind {
    var bridgeName: String {
        switch self {
        case .sRGB, .extendedLinearSRGB, .unknown: "sRGB"
        case .displayP3: "DisplayP3"
        case .rec2020: "Rec2020"
        }
    }
}
