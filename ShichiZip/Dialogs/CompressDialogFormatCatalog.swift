import Cocoa

@MainActor
extension CompressDialogController {
    private static func levelOption(title: String,
                                    value: Int,
                                    isDefault: Bool = false) -> LevelOption
    {
        LevelOption(title: title,
                    levelValue: value,
                    isDefault: isDefault)
    }

    private static func makeStandardLevelOptions(includeStore: Bool) -> [LevelOption] {
        var options: [LevelOption] = []
        if includeStore {
            options.append(levelOption(title: SZL10n.string("level.store"), value: 0))
        }
        options.append(levelOption(title: SZL10n.string("level.fastest"), value: 1))
        options.append(levelOption(title: SZL10n.string("level.fast"), value: 3))
        options.append(levelOption(title: SZL10n.string("level.normal"), value: 5, isDefault: true))
        options.append(levelOption(title: SZL10n.string("level.maximum"), value: 7))
        options.append(levelOption(title: SZL10n.string("level.ultra"), value: 9))
        options.append(levelOption(title: SZL10n.string("level.ultra") + "+", value: 255))
        return options
    }

    private static func numberedLevelTitle(_ value: Int,
                                           namedLabel: String?) -> String
    {
        let base = "Level \(value)"
        guard let namedLabel else {
            return base
        }
        return "\(base) (\(namedLabel))"
    }

    private static func makeNumberedLevelOptions(range: ClosedRange<Int>,
                                                 namedLabels: [Int: String],
                                                 defaultValue: Int,
                                                 highestTitle: String? = nil) -> [LevelOption]
    {
        var options = range.map { value in
            levelOption(title: numberedLevelTitle(value, namedLabel: namedLabels[value]),
                        value: value,
                        isDefault: value == defaultValue)
        }
        options.append(levelOption(title: highestTitle ?? (SZL10n.string("level.ultra") + "+"), value: 255))
        return options
    }

    private static func localizedLevelLabels(_ keyMap: [Int: String]) -> [Int: String] {
        keyMap.mapValues { SZL10n.string($0) }
    }

    private static func zstdNamedLabel(for value: Int) -> String? {
        switch value {
        case -64:
            "Ultimate Fast"
        case -7:
            "Ultra Fast"
        case -1:
            "Super Fast"
        case 1:
            SZL10n.string("level.fastest")
        case 3:
            SZL10n.string("level.fast")
        case 11:
            SZL10n.string("level.normal")
        case 19:
            SZL10n.string("level.maximum")
        case 20:
            SZL10n.string("level.ultra")
        default:
            nil
        }
    }

    private static func zstdLevelTitle(for value: Int) -> String {
        let base = value < 0 ? "Fast \(value)" : "Level \(value)"
        guard let namedLabel = zstdNamedLabel(for: value) else {
            return base
        }
        return "\(base) (\(namedLabel))"
    }

    private static func makeZstdLevelOptions() -> [LevelOption] {
        var options: [LevelOption] = []
        for value in -64 ... 22 where value != 0 {
            options.append(levelOption(title: zstdLevelTitle(for: value),
                                       value: value,
                                       isDefault: value == 11))
        }
        options.append(levelOption(title: SZL10n.string("level.ultra") + "+", value: 255))
        return options
    }

    private static var levelOptions: [LevelOption] {
        makeStandardLevelOptions(includeStore: true)
    }

    private static var nonStoreLevelOptions: [LevelOption] {
        makeStandardLevelOptions(includeStore: false)
    }

    private static var storeOnlyLevelOptions: [LevelOption] {
        [levelOption(title: SZL10n.string("level.store"), value: 0, isDefault: true)]
    }

    private static var zstdLevelOptions: [LevelOption] {
        makeZstdLevelOptions()
    }

    private static var brotliLevelOptions: [LevelOption] {
        makeNumberedLevelOptions(range: 0 ... 11,
                                 namedLabels: localizedLevelLabels([0: "level.store", 1: "level.fastest", 3: "level.fast", 6: "level.normal", 9: "level.maximum", 11: "level.ultra"]),
                                 defaultValue: 6)
    }

    private static var lz4LevelOptions: [LevelOption] {
        makeNumberedLevelOptions(range: 1 ... 12,
                                 namedLabels: localizedLevelLabels([1: "level.fastest", 3: "level.fast", 6: "level.normal", 9: "level.maximum", 12: "level.ultra"]),
                                 defaultValue: 6)
    }

    private static var lz5LevelOptions: [LevelOption] {
        makeNumberedLevelOptions(range: 1 ... 15,
                                 namedLabels: localizedLevelLabels([1: "level.fastest", 3: "level.fast", 7: "level.normal", 11: "level.maximum", 15: "level.ultra"]),
                                 defaultValue: 7)
    }

    private static var lizardMethod1LevelOptions: [LevelOption] {
        makeNumberedLevelOptions(range: 10 ... 19,
                                 namedLabels: localizedLevelLabels([10: "level.fastest", 13: "level.fast", 15: "level.normal", 17: "level.maximum", 19: "level.ultra"]),
                                 defaultValue: 15)
    }

    private static var lizardMethod2LevelOptions: [LevelOption] {
        makeNumberedLevelOptions(range: 20 ... 29,
                                 namedLabels: localizedLevelLabels([20: "level.fastest", 23: "level.fast", 25: "level.normal", 27: "level.maximum", 29: "level.ultra"]),
                                 defaultValue: 25)
    }

    private static var lizardMethod3LevelOptions: [LevelOption] {
        makeNumberedLevelOptions(range: 30 ... 39,
                                 namedLabels: localizedLevelLabels([30: "level.fastest", 33: "level.fast", 35: "level.normal", 37: "level.maximum", 39: "level.ultra"]),
                                 defaultValue: 35)
    }

    private static var lizardMethod4LevelOptions: [LevelOption] {
        makeNumberedLevelOptions(range: 40 ... 49,
                                 namedLabels: localizedLevelLabels([40: "level.fastest", 43: "level.fast", 45: "level.normal", 47: "level.maximum", 49: "level.ultra"]),
                                 defaultValue: 45)
    }

    private static let standardDictionaryOptions: [Option<UInt64>] = [
        Option(title: "Auto", value: 0),
        Option(title: "64 KB", value: 64 * 1024),
        Option(title: "256 KB", value: 256 * 1024),
        Option(title: "1 MB", value: 1 << 20),
        Option(title: "4 MB", value: 4 << 20),
        Option(title: "8 MB", value: 8 << 20),
        Option(title: "16 MB", value: 16 << 20),
        Option(title: "32 MB", value: 32 << 20),
        Option(title: "64 MB", value: 64 << 20),
        Option(title: "128 MB", value: 128 << 20),
        Option(title: "256 MB", value: 256 << 20),
    ]

    private static let ppmdDictionaryOptions: [Option<UInt64>] = [
        Option(title: "Auto", value: 0),
        Option(title: "1 MB", value: 1 << 20),
        Option(title: "2 MB", value: 2 << 20),
        Option(title: "4 MB", value: 4 << 20),
        Option(title: "8 MB", value: 8 << 20),
        Option(title: "16 MB", value: 16 << 20),
        Option(title: "32 MB", value: 32 << 20),
        Option(title: "64 MB", value: 64 << 20),
        Option(title: "128 MB", value: 128 << 20),
        Option(title: "256 MB", value: 256 << 20),
    ]

    private static let standardWordOptions: [Option<UInt32>] = [
        Option(title: "Auto", value: 0),
        Option(title: "8", value: 8),
        Option(title: "12", value: 12),
        Option(title: "16", value: 16),
        Option(title: "24", value: 24),
        Option(title: "32", value: 32),
        Option(title: "48", value: 48),
        Option(title: "64", value: 64),
        Option(title: "96", value: 96),
        Option(title: "128", value: 128),
        Option(title: "192", value: 192),
        Option(title: "256", value: 256),
        Option(title: "273", value: 273),
    ]

    private static let orderOptions: [Option<UInt32>] =
        [Option(title: "Auto", value: 0)] + (2 ... 32).map { Option(title: "\($0)", value: UInt32($0)) }

    static var solidOptions: [Option<Bool>] {
        [
            Option(title: SZL10n.string("compress.nonSolid"), value: false),
            Option(title: SZL10n.string("compress.solid"), value: true),
        ]
    }

    private static var dictLabel: String {
        SZL10n.string("compress.dictionarySize")
    }

    private static var wordLbl: String {
        SZL10n.string("compress.wordSize")
    }

    private static var ppmdDictLabel: String {
        SZL10n.string("benchmark.memoryUsage")
    }

    private static var ppmdWordLabel: String {
        SZL10n.string("app.compress.order")
    }

    private static var sevenZipMethods: [MethodOption] {
        var methods: [MethodOption] = [
            MethodOption(title: "LZMA2", enumValue: .LZMA2, methodName: "LZMA2", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "LZMA", enumValue: .LZMA, methodName: "LZMA", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "PPMd", enumValue: .ppMd, methodName: "PPMd", dictionaryLabel: ppmdDictLabel, dictionaryOptions: ppmdDictionaryOptions, wordLabel: ppmdWordLabel, wordOptions: orderOptions),
            MethodOption(title: "BZip2", enumValue: .bZip2, methodName: "BZip2", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "Deflate", enumValue: .deflate, methodName: "Deflate", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "Deflate64", enumValue: .deflate64, methodName: "Deflate64", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
        ]
        #if SHICHIZIP_ZS_VARIANT
            methods += [
                MethodOption(title: "ZSTD", enumValue: nil, methodName: "ZSTD", levelOptions: zstdLevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "Brotli", enumValue: nil, methodName: "Brotli", levelOptions: brotliLevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "LZ4", enumValue: nil, methodName: "LZ4", levelOptions: lz4LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "LZ5", enumValue: nil, methodName: "LZ5", levelOptions: lz5LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "Lizard FastLZ4", enumValue: nil, methodName: "Lizard-FastLZ4", levelOptions: lizardMethod1LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "Lizard LIZv1", enumValue: nil, methodName: "Lizard-LIZv1", levelOptions: lizardMethod2LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "Lizard FastLZ4 + Huffman", enumValue: nil, methodName: "Lizard-FastLZ4-Huffman", levelOptions: lizardMethod3LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "Lizard LIZv1 + Huffman", enumValue: nil, methodName: "Lizard-LIZv1-Huffman", levelOptions: lizardMethod4LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
                MethodOption(title: "FLZMA2", enumValue: nil, methodName: "FLZMA2", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            ]
        #endif
        methods.append(MethodOption(title: "Copy", enumValue: .copy, methodName: "Copy", levelOptions: storeOnlyLevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []))
        return methods
    }

    private static var zipMethods: [MethodOption] {
        var methods: [MethodOption] = [
            MethodOption(title: "Deflate", enumValue: .deflate, methodName: "Deflate", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "Deflate64", enumValue: .deflate64, methodName: "Deflate64", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "BZip2", enumValue: .bZip2, methodName: "BZip2", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "LZMA", enumValue: .LZMA, methodName: "LZMA", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions),
            MethodOption(title: "PPMd", enumValue: .ppMd, methodName: "PPMd", dictionaryLabel: ppmdDictLabel, dictionaryOptions: ppmdDictionaryOptions, wordLabel: ppmdWordLabel, wordOptions: orderOptions),
        ]
        #if SHICHIZIP_ZS_VARIANT
            methods.append(MethodOption(title: "ZSTD", enumValue: nil, methodName: "ZSTD", levelOptions: zstdLevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []))
        #endif
        methods.append(MethodOption(title: "Copy", enumValue: .copy, methodName: "Copy", levelOptions: storeOnlyLevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []))
        return methods
    }

    private static var gzipMethods: [MethodOption] {
        [MethodOption(title: "Deflate", enumValue: .deflate, methodName: "Deflate", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions)]
    }

    private static var bzip2Methods: [MethodOption] {
        [MethodOption(title: "BZip2", enumValue: .bZip2, methodName: "BZip2", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions)]
    }

    private static var xzMethods: [MethodOption] {
        [MethodOption(title: "LZMA2", enumValue: .LZMA2, methodName: "LZMA2", dictionaryLabel: dictLabel, dictionaryOptions: standardDictionaryOptions, wordLabel: wordLbl, wordOptions: standardWordOptions)]
    }

    private static var tarMethods: [MethodOption] {
        [
            MethodOption(title: "GNU", enumValue: nil, methodName: "GNU", dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
            MethodOption(title: "POSIX", enumValue: nil, methodName: "POSIX", dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
        ]
    }

    private static var zstdMethods: [MethodOption] {
        [MethodOption(title: "ZSTD", enumValue: nil, methodName: "ZSTD", levelOptions: zstdLevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: [])]
    }

    private static var brotliMethods: [MethodOption] {
        [MethodOption(title: "Brotli", enumValue: nil, methodName: "Brotli", levelOptions: brotliLevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: [])]
    }

    private static var lizardMethods: [MethodOption] {
        [
            MethodOption(title: "FastLZ4", enumValue: nil, methodName: "Lizard-FastLZ4", levelOptions: lizardMethod1LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
            MethodOption(title: "LIZv1", enumValue: nil, methodName: "Lizard-LIZv1", levelOptions: lizardMethod2LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
            MethodOption(title: "FastLZ4 + Huffman", enumValue: nil, methodName: "Lizard-FastLZ4-Huffman", levelOptions: lizardMethod3LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
            MethodOption(title: "LIZv1 + Huffman", enumValue: nil, methodName: "Lizard-LIZv1-Huffman", levelOptions: lizardMethod4LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: []),
        ]
    }

    private static var lz4Methods: [MethodOption] {
        [MethodOption(title: "LZ4", enumValue: nil, methodName: "LZ4", levelOptions: lz4LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: [])]
    }

    private static var lz5Methods: [MethodOption] {
        [MethodOption(title: "LZ5", enumValue: nil, methodName: "LZ5", levelOptions: lz5LevelOptions, dictionaryLabel: dictLabel, dictionaryOptions: [], wordLabel: wordLbl, wordOptions: [])]
    }

    private static var formatCatalog: [FormatOption] {
        var formats: [FormatOption] = [
            FormatOption(title: "7z", codecName: "7z", format: .format7z, defaultExtension: "7z", levelOptions: levelOptions, methods: sevenZipMethods, supportsSolid: true, supportsThreads: true, encryptionOptions: [Option(title: "AES-256", value: .AES256)], supportsEncryptFileNames: true, keepsName: false),
            FormatOption(title: "zip", codecName: "zip", format: .formatZip, defaultExtension: "zip", levelOptions: levelOptions, methods: zipMethods, supportsSolid: false, supportsThreads: true, encryptionOptions: [Option(title: "ZipCrypto", value: .zipCrypto), Option(title: "AES-256", value: .AES256)], supportsEncryptFileNames: false, keepsName: false),
            FormatOption(title: "gzip", codecName: "gzip", format: .formatGZip, defaultExtension: "gz", levelOptions: nonStoreLevelOptions, methods: gzipMethods, supportsSolid: false, supportsThreads: false, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
            FormatOption(title: "bzip2", codecName: "bzip2", format: .formatBZip2, defaultExtension: "bz2", levelOptions: nonStoreLevelOptions, methods: bzip2Methods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
            FormatOption(title: "xz", codecName: "xz", format: .formatXz, defaultExtension: "xz", levelOptions: nonStoreLevelOptions, methods: xzMethods, supportsSolid: true, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
        ]
        #if SHICHIZIP_ZS_VARIANT
            formats += [
                FormatOption(title: "zstd", codecName: "zstd", format: .formatZstd, defaultExtension: "zst", levelOptions: zstdLevelOptions, methods: zstdMethods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
                FormatOption(title: "Brotli", codecName: "brotli", format: .formatBrotli, defaultExtension: "br", levelOptions: brotliLevelOptions, methods: brotliMethods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
                FormatOption(title: "Lizard", codecName: "lizard", format: .formatLizard, defaultExtension: "liz", levelOptions: lizardMethod1LevelOptions, methods: lizardMethods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
                FormatOption(title: "LZ4", codecName: "lz4", format: .formatLz4, defaultExtension: "lz4", levelOptions: lz4LevelOptions, methods: lz4Methods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
                FormatOption(title: "LZ5", codecName: "lz5", format: .formatLz5, defaultExtension: "lz5", levelOptions: lz5LevelOptions, methods: lz5Methods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: true),
            ]
        #endif
        formats.append(FormatOption(title: "tar", codecName: "tar", format: .formatTar, defaultExtension: "tar", levelOptions: storeOnlyLevelOptions, methods: tarMethods, supportsSolid: false, supportsThreads: false, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: false))
        formats.append(FormatOption(title: "wim", codecName: "wim", format: .formatWim, defaultExtension: "wim", levelOptions: storeOnlyLevelOptions, methods: [], supportsSolid: false, supportsThreads: false, encryptionOptions: [], supportsEncryptFileNames: false, keepsName: false))
        return formats
    }

    static func encryptionOptions(for format: SZArchiveFormat) -> [Option<SZEncryptionMethod>] {
        formatCatalog.first { $0.format == format }?.encryptionOptions ?? []
    }

    static func makeSupportedFormatInfoByName() -> [String: SZFormatInfo] {
        SZArchive.supportedFormats().reduce(into: [:]) { partialResult, info in
            partialResult[info.name.lowercased()] = info
        }
    }

    static func makeAvailableFormats(supportedFormatInfoByName: [String: SZFormatInfo],
                                     sourceURLs: [URL]) -> [FormatOption]
    {
        let isSingleFile = isSingleFileSource(sourceURLs)
        let supportedNames = Set(
            supportedFormatInfoByName.values
                .filter(\.canWrite)
                .map { $0.name.lowercased() },
        )
        let filteredFormats = formatCatalog.filter {
            guard supportedNames.isEmpty || supportedNames.contains($0.codecName.lowercased()) else {
                return false
            }

            let keepsName = supportedFormatInfoByName[$0.codecName.lowercased()]?.keepsName ?? $0.keepsName
            return isSingleFile || !keepsName
        }
        if !filteredFormats.isEmpty {
            return filteredFormats
        }

        return formatCatalog.filter { isSingleFile || !$0.keepsName }
    }

    private static func isSingleFileSource(_ sourceURLs: [URL]) -> Bool {
        guard sourceURLs.count == 1,
              let sourceURL = sourceURLs.first
        else {
            return false
        }

        let resourceValues = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == false
    }
}
