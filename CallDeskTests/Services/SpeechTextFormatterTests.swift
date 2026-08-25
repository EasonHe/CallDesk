import Testing
@testable import CallDesk

@Suite("Speech text formatter")
struct SpeechTextFormatterTests {
    @Test("Ticket codes are spoken in place as Chinese characters using 幺 for 1")
    func ticketCodeSpeaksLettersAndDigitsIndividually() {
        #expect(SpeechTextFormatter.speechText(for: "A102") == "诶，一百零二")
        #expect(SpeechTextFormatter.speechText(for: "B07") == "必，零七")
    }

    @Test("Codes inside a Chinese sentence are rewritten in place with 幺 for 1")
    func codeInsideSentenceIsRewrittenInPlace() {
        #expect(
            SpeechTextFormatter.speechText(for: "请 A102 号，到 3 号柜台")
                == "请 诶，一百零二 号，到 三 号柜台"
        )
    }

    @Test("Sentence initial 请 passes through unchanged without a lead-in")
    func sentenceInitialQingPassesThrough() {
        #expect(
            SpeechTextFormatter.speechText(for: "请01号到1号窗口")
                == "请零幺号到一号窗口"
        )
    }

    @Test("Lowercase letters read the same as uppercase ones")
    func lowercaseLettersReadLikeUppercase() {
        #expect(SpeechTextFormatter.speechText(for: "b12") == "必，十二")
        #expect(SpeechTextFormatter.speechText(for: "a12") == "诶，十二")
    }

    @Test("Every ASCII digit is spoken as its Chinese reading with 1 as 幺")
    func everyDigitIsConverted() {
        #expect(SpeechTextFormatter.speechText(for: "108") == "一百零八")
        #expect(SpeechTextFormatter.speechText(for: "302") == "三百零二")
    }

    @Test("Numbers read as Chinese numerals with zero-padded tickets read digit by digit")
    func numbersReadAsChineseNumerals() {
        #expect(SpeechTextFormatter.speechText(for: "22") == "二十二")
        #expect(SpeechTextFormatter.speechText(for: "120") == "一百二十")
        #expect(SpeechTextFormatter.speechText(for: "102") == "一百零二")
        #expect(SpeechTextFormatter.speechText(for: "11") == "十一")
        #expect(SpeechTextFormatter.speechText(for: "10") == "十")
        #expect(SpeechTextFormatter.speechText(for: "01") == "零幺")
        #expect(SpeechTextFormatter.speechText(for: "100") == "一百")
    }

    @Test("Chinese-only text passes through unchanged when not starting with 请")
    func chineseTextIsUnchanged() {
        #expect(SpeechTextFormatter.speechText(for: "到三号窗口取餐") == "到三号窗口取餐")
    }
}
