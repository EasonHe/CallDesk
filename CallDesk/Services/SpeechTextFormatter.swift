import Foundation

/// Rewrites announcement text right before it is spoken so the bundled
/// Chinese voices pronounce every character in Chinese: digits come out as
/// "零/幺/二/…" and ASCII letters come out as their Chinese letter names
/// ("A" → "诶", "B" → "必"). A short pause (",") is inserted after a letter
/// when it is followed by a digit so lettered ticket codes like "A01" stay
/// clearly audible instead of blending into the number.
///
/// The TTS engines read raw ASCII digits and letters as English (or skip
/// them), which is wrong for a Chinese ordering/queue system. Converting
/// characters in place guarantees the voice stays fully Chinese while
/// preserved spaces and punctuation maintain natural Mandarin sentence
/// cadence and tone sandhi (变调).
nonisolated enum SpeechTextFormatter {
    static func speechText(for text: String) -> String {
        let formattedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var result = ""
        result.reserveCapacity(formattedText.count * 2)

        let characters = Array(formattedText)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isASCII, character.isNumber {
                var end = index
                while end + 1 < characters.count,
                      characters[end + 1].isASCII,
                      characters[end + 1].isNumber {
                    end += 1
                }
                result.append(numberReading(String(characters[index...end])))
                index = end + 1
            } else if character.isASCII, character.isLetter {
                let uppercased = Character(character.uppercased())
                result.append(letterReadings[uppercased] ?? String(uppercased))
                if index + 1 < characters.count,
                   characters[index + 1].isASCII,
                   characters[index + 1].isNumber {
                    result.append("，")
                }
                index += 1
            } else {
                result.append(character)
                index += 1
            }
        }
        return result
    }

    /// Zero-padded ticket numbers ("01", "021") are read digit by digit as
    /// standard queue calling conventions ("零幺", "零二幺"); other integers
    /// are read as their Chinese numerical value ("22" → "二十二", "120" →
    /// "一百二十"). Values above 9999 fall back to digit-by-digit reading.
    private static func numberReading(_ digits: String) -> String {
        let isZeroPadded = digits.first == "0" && digits.count > 1
        let fallback = { digits.compactMap { digitReadings[$0] }.joined() }
        if isZeroPadded {
            return fallback()
        }
        guard let value = Int(digits), value < 10000 else {
            return fallback()
        }
        return chineseNumber(value)
    }

    /// Converts an integer to its Chinese numeral reading ("22" → "二十二",
    /// "120" → "一百二十", "102" → "一百零二"). The leading "一" is dropped
    /// in the teens ("11" → "十一", "10" → "十"). "1" reads "一" here, not
    /// "幺": digit-by-digit "幺" is reserved for zero-padded ticket numbers.
    private static func chineseNumber(_ value: Int) -> String {
        guard value != 0 else { return "零" }
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let units = ["", "十", "百", "千"]
        var result = ""
        var number = value
        var position = 0
        var zeroPending = false
        var hasEmitted = false
        while number > 0 {
            let digit = number % 10
            if digit == 0 {
                if hasEmitted {
                    zeroPending = true
                }
            } else {
                if zeroPending {
                    result = "零" + result
                }
                zeroPending = false
                result = digits[digit] + units[position] + result
                hasEmitted = true
            }
            number /= 10
            position += 1
        }
        if value < 20 {
            result = result.replacingOccurrences(of: "一十", with: "十")
        }
        return result
    }

    /// Chinese pronunciation for the English letter names, so "A" is spoken
    /// as "诶" instead of the pinyin "啊".
    private static let letterReadings: [Character: String] = [
        "A": "诶", "B": "必", "C": "西", "D": "地",
        "E": "易", "F": "艾弗", "G": "记", "H": "诶曲",
        "I": "爱", "J": "杰", "K": "凯", "L": "艾勒",
        "M": "艾姆", "N": "恩", "O": "欧", "P": "屁",
        "Q": "扣", "R": "阿", "S": "艾斯", "T": "替",
        "U": "优", "V": "维", "W": "大波留", "X": "艾克斯",
        "Y": "外", "Z": "贼"
    ]

    /// Digits are spoken one by one as standard Chinese queue readings ("102" →
    /// 幺零二, "1号" → 幺号). Using "幺" for 1 matches standard Chinese queue
    /// calling conventions (零幺, 幺零幺).
    private static let digitReadings: [Character: String] = [
        "0": "零", "1": "幺", "2": "二", "3": "三", "4": "四",
        "5": "五", "6": "六", "7": "七", "8": "八", "9": "九"
    ]
}
